-- =====================================================================
-- MI AGENCIA — esquema completo
-- Las 10 migraciones de supabase/migrations/ concatenadas en orden.
-- Generado automaticamente: no editar a mano, editar las migraciones.
--
-- Para usarlo: pegar entero en el SQL Editor de Supabase y ejecutar.
-- Es idempotente, se puede volver a correr sin romper nada.
-- =====================================================================


-- >>>>>>>>>>>>>>>>>>>>  0001_extensiones_enums.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0001: extensiones y tipos enumerados
-- =====================================================================
create extension if not exists "pgcrypto";
create extension if not exists "citext";
create extension if not exists "pg_trgm";     -- busqueda difusa marca/modelo
create extension if not exists "unaccent";    -- busqueda sin tildes

-- Rol de un usuario DENTRO de una agencia.
-- El rol de plataforma (desarrollador) vive en perfiles.es_desarrollador,
-- porque no pertenece a ninguna agencia en particular.
do $$ begin
  create type rol_membresia as enum ('owner','admin','vendedor','solo_lectura');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_vehiculo as enum ('en_stock','en_preparacion','reservado','vendido','dado_de_baja');
exception when duplicate_object then null; end $$;

do $$ begin
  create type categoria_gasto as enum (
    'service','reparaciones','cubiertas','chapa_y_pintura','lavado_detallado',
    'transferencia','patentamiento','gestoria','almacenamiento','comision','otros');
exception when duplicate_object then null; end $$;

-- Embudo de venta. El semaforo (rojo/amarillo/verde) NO es un estado del
-- embudo: se deriva de la situacion crediticia BCRA. Son ejes distintos.
do $$ begin
  create type estado_oportunidad as enum
    ('nuevo','contactado','visita_agendada','visita_realizada','negociacion','reservado','ganado','perdido');
exception when duplicate_object then null; end $$;

do $$ begin
  create type semaforo_crediticio as enum ('verde','amarillo','rojo','sin_datos');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_interaccion as enum ('llamada','whatsapp','email','visita','mensaje_web','otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_campana as enum ('borrador','programada','enviando','enviada','cancelada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_envio as enum ('pendiente','enviado','entregado','abierto','click','rebote','baja','error');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_cotizacion as enum ('oficial','blue','mayorista','mep','ccl','tarjeta');
exception when duplicate_object then null; end $$;

-- >>>>>>>>>>>>>>>>>>>>  0002_tenancy.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0002: multi-tenant (agencias, perfiles, membresias)
-- =====================================================================

-- Cada agencia es un inquilino aislado. Todo dato de negocio cuelga de aca.
create table if not exists public.agencias (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  slug            citext not null unique,
  cuit            text,
  email_contacto  citext,
  telefono        text,
  direccion       text,
  localidad       text,
  provincia       text,
  logo_url        text,
  -- La cuenta de desarrollador da de alta agencias y puede suspenderlas.
  activa          boolean not null default true,
  plan            text not null default 'basico',
  -- Hasta cuando esta paga. null = sin vencimiento.
  vigente_hasta   date,
  creada_por      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.agencias is 'Inquilinos (tenants). Una fila por agencia de autos cliente.';

-- Espejo de auth.users con los datos que la app necesita mostrar.
create table if not exists public.perfiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  nombre           text,
  apellido         text,
  email            citext not null,
  telefono         text,
  avatar_url       text,
  -- Rol de PLATAFORMA: nosotros. Permite crear agencias y ver todo.
  -- No se puede setear desde el cliente (ver policies en 0009).
  es_desarrollador boolean not null default false,
  ultima_sesion    timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on column public.perfiles.es_desarrollador is
  'Superusuario de plataforma. Solo se cambia con service_role o SQL directo, nunca desde la app.';

-- Un usuario puede pertenecer a varias agencias (gestor con varias sucursales).
create table if not exists public.membresias (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  usuario_id  uuid not null references auth.users(id) on delete cascade,
  rol         rol_membresia not null default 'vendedor',
  activa      boolean not null default true,
  invitado_por uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (agencia_id, usuario_id)
);
create index if not exists idx_membresias_usuario on public.membresias(usuario_id) where activa;
create index if not exists idx_membresias_agencia on public.membresias(agencia_id) where activa;

-- Invitaciones pendientes: el owner invita por email antes de que exista el usuario.
create table if not exists public.invitaciones (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  email       citext not null,
  rol         rol_membresia not null default 'vendedor',
  token       text not null unique default encode(gen_random_bytes(24),'hex'),
  expira_at   timestamptz not null default now() + interval '7 days',
  aceptada_at timestamptz,
  invitado_por uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_invitaciones_email on public.invitaciones(email) where aceptada_at is null;

-- Al registrarse un usuario en auth, se crea su perfil automaticamente.
create or replace function public.handle_nuevo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, email, nombre, apellido)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'apellido'
  )
  on conflict (id) do nothing;

  -- Si fue invitado, se convierte la invitacion vigente en membresia.
  insert into public.membresias (agencia_id, usuario_id, rol, invitado_por)
  select i.agencia_id, new.id, i.rol, i.invitado_por
  from public.invitaciones i
  where i.email = new.email
    and i.aceptada_at is null
    and i.expira_at > now()
  on conflict (agencia_id, usuario_id) do nothing;

  update public.invitaciones
     set aceptada_at = now()
   where email = new.email and aceptada_at is null and expira_at > now();

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_nuevo_usuario();

-- updated_at automatico, reutilizado por todas las tablas.
create or replace function public.tocar_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_agencias_updated on public.agencias;
create trigger trg_agencias_updated before update on public.agencias
  for each row execute function public.tocar_updated_at();

drop trigger if exists trg_perfiles_updated on public.perfiles;
create trigger trg_perfiles_updated before update on public.perfiles
  for each row execute function public.tocar_updated_at();

-- >>>>>>>>>>>>>>>>>>>>  0003_helpers_rls.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0003: funciones auxiliares para RLS
--
-- Todas son SECURITY DEFINER a proposito: si una policy de `vehiculos`
-- consultara `membresias` directamente y `membresias` tambien tiene RLS,
-- Postgres entra en recursion infinita. Estas funciones leen con los
-- permisos del owner y cortan esa cadena.
-- =====================================================================

-- ¿El usuario actual es de nuestro equipo (plataforma)?
create or replace function public.es_desarrollador()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.es_desarrollador from public.perfiles p where p.id = auth.uid()),
    false);
$$;

-- Agencias a las que pertenece el usuario actual.
create or replace function public.mis_agencias()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.agencia_id
  from public.membresias m
  where m.usuario_id = auth.uid()
    and m.activa
$$;

-- ¿Tiene el usuario acceso de lectura a esta agencia?
create or replace function public.puede_ver_agencia(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.es_desarrollador()
      or exists (
        select 1 from public.membresias m
        where m.agencia_id = p_agencia
          and m.usuario_id = auth.uid()
          and m.activa);
$$;

-- ¿Tiene alguno de estos roles en la agencia? (el desarrollador siempre si)
create or replace function public.tiene_rol(p_agencia uuid, p_roles rol_membresia[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.es_desarrollador()
      or exists (
        select 1 from public.membresias m
        where m.agencia_id = p_agencia
          and m.usuario_id = auth.uid()
          and m.activa
          and m.rol = any(p_roles));
$$;

-- Atajo: puede escribir datos de negocio (todos menos solo_lectura).
create or replace function public.puede_editar(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.tiene_rol(p_agencia, array['owner','admin','vendedor']::rol_membresia[]);
$$;

-- Atajo: puede tocar configuracion, usuarios y borrar (owner/admin).
create or replace function public.puede_administrar(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.tiene_rol(p_agencia, array['owner','admin']::rol_membresia[]);
$$;

revoke all on function public.es_desarrollador()            from public;
revoke all on function public.mis_agencias()                from public;
revoke all on function public.puede_ver_agencia(uuid)       from public;
revoke all on function public.tiene_rol(uuid, rol_membresia[]) from public;
revoke all on function public.puede_editar(uuid)            from public;
revoke all on function public.puede_administrar(uuid)       from public;

grant execute on function public.es_desarrollador()            to authenticated;
grant execute on function public.mis_agencias()                to authenticated;
grant execute on function public.puede_ver_agencia(uuid)       to authenticated;
grant execute on function public.tiene_rol(uuid, rol_membresia[]) to authenticated;
grant execute on function public.puede_editar(uuid)            to authenticated;
grant execute on function public.puede_administrar(uuid)       to authenticated;

-- >>>>>>>>>>>>>>>>>>>>  0004_catalogo_referencia.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0004: datos de referencia COMPARTIDOS entre agencias
--
-- Nada de esto lleva agencia_id: el IPC del INDEC, el dolar y el valor
-- de revista de un Corolla 2021 son los mismos para todos los clientes.
-- Se leen por cualquier usuario autenticado; solo el backend escribe.
-- =====================================================================

-- ---------- Espejo del catalogo de ArgAutos (argautos.com/api/v1) ------
-- Replicamos su catalogo en nuestra base y lo refrescamos una vez por mes
-- con una Edge Function. Motivo: su API anonima corta a 3 req/min y la app
-- necesita autocompletar marca/modelo/version al instante y sin internet.
create table if not exists public.ref_marcas (
  id         integer primary key,          -- id de ArgAutos, se respeta tal cual
  nombre     text not null,
  slug       text not null unique,
  tipo       text not null default 'auto', -- auto | moto
  created_at timestamptz not null default now()
);

create table if not exists public.ref_modelos (
  id         integer primary key,
  marca_id   integer not null references public.ref_marcas(id) on delete cascade,
  nombre     text not null,
  slug       text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_ref_modelos_marca on public.ref_modelos(marca_id);

create table if not exists public.ref_versiones (
  id         integer primary key,
  modelo_id  integer not null references public.ref_modelos(id) on delete cascade,
  nombre     text not null,               -- "4P 2,0 Xei CVT Safety 2025"
  nombre_raw text,
  created_at timestamptz not null default now()
);
create index if not exists idx_ref_versiones_modelo on public.ref_versiones(modelo_id);
-- Busqueda difusa: el usuario escribe "corola xei" y igual lo encuentra.
create index if not exists idx_ref_versiones_trgm
  on public.ref_versiones using gin (nombre gin_trgm_ops);

-- Precio por version y anio-modelo. Es la tabla que reemplaza a las 13
-- filas cargadas a mano del HTML original.
create table if not exists public.ref_precios (
  version_id     integer not null references public.ref_versiones(id) on delete cascade,
  anio           smallint not null,
  precio_usd     numeric(14,2),
  precio_ars     numeric(16,2),
  -- Cotizacion usada para convertir, para poder reconstruir el ARS despues.
  tc_usado       numeric(12,4),
  actualizado_at timestamptz not null default now(),
  primary key (version_id, anio)
);
create index if not exists idx_ref_precios_anio on public.ref_precios(anio);

create table if not exists public.ref_sync_log (
  id             bigserial primary key,
  fuente         text not null default 'argautos',
  iniciado_at    timestamptz not null default now(),
  finalizado_at  timestamptz,
  ok             boolean,
  marcas         integer default 0,
  modelos        integer default 0,
  versiones      integer default 0,
  precios        integer default 0,
  error          text
);

-- Vista plana para el buscador de la app: una fila por version con su marca
-- y modelo ya resueltos, para no hacer 3 joins desde el cliente.
create or replace view public.ref_catalogo as
select v.id              as version_id,
       ma.id             as marca_id,
       ma.nombre         as marca,
       mo.id             as modelo_id,
       mo.nombre         as modelo,
       v.nombre          as version,
       ma.tipo           as tipo,
       ma.nombre || ' ' || mo.nombre || ' ' || v.nombre as etiqueta
from public.ref_versiones v
join public.ref_modelos  mo on mo.id = v.modelo_id
join public.ref_marcas   ma on ma.id = mo.marca_id;

-- ---------- IPC INDEC ---------------------------------------------------
-- El HTML original guardaba la serie dentro de config. Va aca porque es
-- un dato publico unico, no un parametro de cada agencia.
create table if not exists public.ipc_serie (
  mes           date primary key,            -- siempre dia 1: 2026-08-01
  variacion     numeric(8,5),                -- 0.021 = 2,1% mensual
  indice        numeric(16,6),               -- base 100 en el primer mes
  fuente        text,
  url           text,
  es_proyeccion boolean not null default false,
  updated_at    timestamptz not null default now()
);
comment on column public.ipc_serie.indice is
  'Indice acumulado base 100. Se recalcula entero con recalcular_ipc() al insertar o corregir un mes.';

-- Recalcula la columna indice encadenando variaciones desde el mes mas viejo.
create or replace function public.recalcular_ipc()
returns void
language plpgsql
as $$
declare
  r record;
  acc numeric := 100;
  primero boolean := true;
begin
  for r in select mes, variacion from public.ipc_serie order by mes loop
    if primero then
      primero := false;                       -- el mes base vale 100
    else
      acc := acc * (1 + coalesce(r.variacion, 0));
    end if;
    update public.ipc_serie set indice = acc, updated_at = now() where mes = r.mes;
  end loop;
end $$;

-- Indice IPC vigente para una fecha cualquiera. Si la fecha cae despues del
-- ultimo mes publicado, devuelve el ultimo (no extrapola: mejor subestimar
-- la inflacion que inventarla).
create or replace function public.ipc_indice_en(p_fecha date)
returns numeric
language sql
stable
as $$
  select coalesce(
    (select indice from public.ipc_serie
      where mes <= date_trunc('month', p_fecha)::date
      order by mes desc limit 1),
    (select indice from public.ipc_serie order by mes limit 1),
    100);
$$;

create or replace function public.ipc_indice_hoy()
returns numeric language sql stable as $$
  select public.ipc_indice_en(current_date);
$$;

-- ---------- Cotizaciones del dolar --------------------------------------
create table if not exists public.cotizaciones (
  fecha      date not null,
  tipo       tipo_cotizacion not null,
  compra     numeric(12,4),
  venta      numeric(12,4),
  fuente     text,
  created_at timestamptz not null default now(),
  primary key (fecha, tipo)
);

create or replace function public.cotizacion_vigente(p_tipo tipo_cotizacion default 'oficial')
returns numeric
language sql
stable
as $$
  select venta from public.cotizaciones
   where tipo = p_tipo and venta is not null
   order by fecha desc limit 1;
$$;

-- >>>>>>>>>>>>>>>>>>>>  0005_vehiculos.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0005: nucleo del negocio (stock, gastos, precios, ventas)
-- Equivale a las hojas Vehiculos / Gastos / Precios / Ventas del Excel.
-- =====================================================================

create table if not exists public.vehiculos (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references public.agencias(id) on delete cascade,
  -- Codigo visible tipo "V001". Unico por agencia, no global: cada agencia
  -- arranca su propia numeracion desde 1.
  codigo         text not null,

  marca          text not null,
  modelo         text not null,
  anio           smallint not null,
  version        text,
  -- Enlace opcional al catalogo de ArgAutos para traer el valor de revista.
  ref_version_id integer references public.ref_versiones(id) on delete set null,

  km             integer,
  patente        text,
  color          text,
  combustible    text,
  transmision    text,
  nro_motor      text,
  nro_chasis     text,

  fecha_compra    date not null,
  fecha_ingreso   date not null,          -- arranca el reloj de dias en stock
  precio_compra   numeric(16,2) not null check (precio_compra >= 0),
  precio_objetivo numeric(16,2) check (precio_objetivo >= 0),

  estado         estado_vehiculo not null default 'en_stock',
  observaciones  text,

  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Borrado logico: nunca se pierde el historial de una unidad.
  deleted_at     timestamptz,

  unique (agencia_id, codigo),
  constraint fecha_ingreso_coherente check (fecha_ingreso >= fecha_compra)
);
create index if not exists idx_vehiculos_agencia  on public.vehiculos(agencia_id) where deleted_at is null;
create index if not exists idx_vehiculos_estado   on public.vehiculos(agencia_id, estado) where deleted_at is null;
create index if not exists idx_vehiculos_busqueda on public.vehiculos
  using gin ((marca || ' ' || modelo || ' ' || coalesce(version, '')) gin_trgm_ops);
-- El scroll infinito pagina por fecha_ingreso descendente: este indice lo sostiene.
create index if not exists idx_vehiculos_orden    on public.vehiculos(agencia_id, fecha_ingreso desc, id desc)
  where deleted_at is null;

drop trigger if exists trg_vehiculos_updated on public.vehiculos;
create trigger trg_vehiculos_updated before update on public.vehiculos
  for each row execute function public.tocar_updated_at();

-- Numerador por agencia: V001, V002... sin colisiones entre inquilinos.
create or replace function public.siguiente_codigo_vehiculo(p_agencia uuid)
returns text
language sql
stable
as $fn$
  select 'V' || lpad(
    (coalesce(max(nullif(regexp_replace(codigo, '[^0-9]', '', 'g'), ''))::int, 0) + 1)::text,
    3, '0')
  from public.vehiculos
  where agencia_id = p_agencia;
$fn$;

-- ---------- Fotos (Supabase Storage) ------------------------------------
create table if not exists public.vehiculo_fotos (
  id           uuid primary key default gen_random_uuid(),
  agencia_id   uuid not null references public.agencias(id) on delete cascade,
  vehiculo_id  uuid not null references public.vehiculos(id) on delete cascade,
  storage_path text not null,
  orden        smallint not null default 0,
  es_principal boolean not null default false,
  subida_por   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_fotos_vehiculo on public.vehiculo_fotos(vehiculo_id, orden);
-- Una sola foto principal por vehiculo.
create unique index if not exists idx_fotos_principal
  on public.vehiculo_fotos(vehiculo_id) where es_principal;

-- ---------- Gastos -------------------------------------------------------
create table if not exists public.gastos (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references public.agencias(id) on delete cascade,
  vehiculo_id     uuid not null references public.vehiculos(id) on delete cascade,
  fecha           date not null,
  categoria       categoria_gasto not null default 'otros',
  descripcion     text,
  importe         numeric(16,2) not null check (importe >= 0),
  proveedor       text,
  comprobante_url text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists idx_gastos_vehiculo on public.gastos(vehiculo_id);
create index if not exists idx_gastos_agencia  on public.gastos(agencia_id, fecha desc);

-- ---------- Historial de precios publicados ------------------------------
create table if not exists public.cambios_precio (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references public.agencias(id) on delete cascade,
  vehiculo_id     uuid not null references public.vehiculos(id) on delete cascade,
  fecha           date not null default current_date,
  precio_anterior numeric(16,2),
  precio_nuevo    numeric(16,2) not null check (precio_nuevo >= 0),
  motivo          text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists idx_precios_vehiculo on public.cambios_precio(vehiculo_id, fecha desc);

-- Completa precio_anterior solo: el usuario carga el precio nuevo y el
-- sistema recuerda de donde venia, sin que nadie lo tipee mal.
create or replace function public.completar_precio_anterior()
returns trigger language plpgsql as $fn$
begin
  if new.precio_anterior is null then
    select coalesce(
             (select precio_nuevo from public.cambios_precio
               where vehiculo_id = new.vehiculo_id
               order by fecha desc, created_at desc limit 1),
             (select precio_objetivo from public.vehiculos where id = new.vehiculo_id))
      into new.precio_anterior;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_precio_anterior on public.cambios_precio;
create trigger trg_precio_anterior before insert on public.cambios_precio
  for each row execute function public.completar_precio_anterior();

-- ---------- Ventas -------------------------------------------------------
create table if not exists public.ventas (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references public.agencias(id) on delete cascade,
  -- Un vehiculo se vende UNA sola vez. El HTML original tenia que chequear
  -- esto a mano en integrityChecks(); aca lo garantiza la base.
  vehiculo_id    uuid not null unique references public.vehiculos(id) on delete cascade,
  fecha_venta    date not null,
  precio_final   numeric(16,2) not null check (precio_final >= 0),
  gastos_finales numeric(16,2) not null default 0 check (gastos_finales >= 0),
  cliente_id     uuid,   -- FK agregada en 0006, cuando ya existe la tabla clientes
  vendedor_id    uuid references auth.users(id) on delete set null,
  forma_pago     text,
  cuotas         smallint,
  observaciones  text,
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists idx_ventas_agencia on public.ventas(agencia_id, fecha_venta desc);

-- Vender marca el vehiculo como vendido; anular la venta lo devuelve a stock.
create or replace function public.sincronizar_estado_por_venta()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    update public.vehiculos set estado = 'en_stock' where id = old.vehiculo_id;
    return old;
  else
    update public.vehiculos set estado = 'vendido' where id = new.vehiculo_id;
    return new;
  end if;
end $fn$;

drop trigger if exists trg_venta_estado on public.ventas;
create trigger trg_venta_estado after insert or delete on public.ventas
  for each row execute function public.sincronizar_estado_por_venta();

-- >>>>>>>>>>>>>>>>>>>>  0006_crm_bcra.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0006: CRM (clientes, oportunidades) + BCRA
--
-- El HTML original tenia una sola tabla "interesados" con nombre, telefono
-- y una observacion suelta. Aca se separa en dos cosas distintas:
--   clientes      -> la PERSONA (se repite entre vehiculos y entre anios)
--   oportunidades -> el INTERES de esa persona en UN vehiculo concreto
-- Sin esa separacion no se puede hacer ni email marketing ni semaforo
-- crediticio, porque ambos son propiedades de la persona, no del interes.
-- =====================================================================

create table if not exists public.clientes (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  nombre      text not null,
  apellido    text,
  -- CUIT/CUIL es la clave para consultar el BCRA. 11 digitos sin guiones.
  cuit        text,
  dni         text,
  email       citext,
  telefono    text,
  whatsapp    text,
  localidad   text,
  provincia   text,
  origen      text,           -- de donde vino: web, showroom, referido, MercadoLibre...
  notas       text,
  -- Baja de la lista de email marketing. Obligatorio por buenas practicas
  -- anti-spam: nunca se le vuelve a escribir a quien pidio la baja.
  acepta_marketing boolean not null default true,
  baja_marketing_at timestamptz,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  constraint cuit_formato check (cuit is null or cuit ~ '^[0-9]{11}$')
);
create index if not exists idx_clientes_agencia on public.clientes(agencia_id) where deleted_at is null;
create index if not exists idx_clientes_cuit    on public.clientes(agencia_id, cuit) where cuit is not null;
create index if not exists idx_clientes_email   on public.clientes(agencia_id, email) where email is not null;
create index if not exists idx_clientes_busqueda on public.clientes
  using gin ((nombre || ' ' || coalesce(apellido, '')) gin_trgm_ops);
-- Un mismo CUIT no se carga dos veces en la misma agencia.
create unique index if not exists idx_clientes_cuit_unico
  on public.clientes(agencia_id, cuit) where cuit is not null and deleted_at is null;

drop trigger if exists trg_clientes_updated on public.clientes;
create trigger trg_clientes_updated before update on public.clientes
  for each row execute function public.tocar_updated_at();

-- Ahora que existe clientes, se cierra la FK que quedo pendiente en 0005.
alter table public.ventas
  drop constraint if exists ventas_cliente_id_fkey;
alter table public.ventas
  add constraint ventas_cliente_id_fkey
  foreign key (cliente_id) references public.clientes(id) on delete set null;

-- ---------- Oportunidades (el embudo) -----------------------------------
create table if not exists public.oportunidades (
  id                uuid primary key default gen_random_uuid(),
  agencia_id        uuid not null references public.agencias(id) on delete cascade,
  cliente_id        uuid not null references public.clientes(id) on delete cascade,
  -- Puede ser null: alguien que "busca una pickup" sin unidad definida.
  vehiculo_id       uuid references public.vehiculos(id) on delete set null,
  estado            estado_oportunidad not null default 'nuevo',
  -- 1 = frio, 5 = caliente. Lo pone el vendedor a mano.
  interes           smallint not null default 3 check (interes between 1 and 5),
  presupuesto_max   numeric(16,2),
  necesita_financiacion boolean not null default false,
  -- Si entrega un usado como parte de pago, se anota aca.
  entrega_usado     boolean not null default false,
  usado_descripcion text,
  usado_valor_estimado numeric(16,2),
  proxima_accion    text,
  proxima_accion_fecha date,
  asignado_a        uuid references auth.users(id) on delete set null,
  motivo_perdida    text,
  notas             text,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  cerrada_at        timestamptz
);
create index if not exists idx_oport_agencia  on public.oportunidades(agencia_id, estado);
create index if not exists idx_oport_cliente  on public.oportunidades(cliente_id);
create index if not exists idx_oport_vehiculo on public.oportunidades(vehiculo_id);
create index if not exists idx_oport_agenda   on public.oportunidades(agencia_id, proxima_accion_fecha)
  where proxima_accion_fecha is not null and cerrada_at is null;

drop trigger if exists trg_oport_updated on public.oportunidades;
create trigger trg_oport_updated before update on public.oportunidades
  for each row execute function public.tocar_updated_at();

-- Sella la fecha de cierre cuando la oportunidad se gana o se pierde.
create or replace function public.sellar_cierre_oportunidad()
returns trigger language plpgsql as $fn$
begin
  if new.estado in ('ganado', 'perdido') and old.estado not in ('ganado', 'perdido') then
    new.cerrada_at := now();
  elsif new.estado not in ('ganado', 'perdido') then
    new.cerrada_at := null;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_oport_cierre on public.oportunidades;
create trigger trg_oport_cierre before update on public.oportunidades
  for each row execute function public.sellar_cierre_oportunidad();

-- ---------- Bitacora de contactos ---------------------------------------
create table if not exists public.interacciones (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references public.agencias(id) on delete cascade,
  oportunidad_id  uuid references public.oportunidades(id) on delete cascade,
  cliente_id      uuid not null references public.clientes(id) on delete cascade,
  tipo            tipo_interaccion not null default 'llamada',
  fecha           timestamptz not null default now(),
  resumen         text,
  usuario_id      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists idx_interacciones_oport   on public.interacciones(oportunidad_id, fecha desc);
create index if not exists idx_interacciones_cliente on public.interacciones(cliente_id, fecha desc);

-- =====================================================================
-- BCRA — Central de Deudores
--
-- API publica y gratuita del Banco Central:
--   GET https://api.bcra.gob.ar/centraldedeudores/v1.0/Deudas/{cuit}
--   GET .../Deudas/Historicas/{cuit}          (24 meses)
--   GET .../Deudas/ChequesRechazados/{cuit}
--
-- Se consulta desde una Edge Function (no desde la app) por dos razones:
-- el BCRA no manda cabeceras CORS, y asi cacheamos para no golpear su API
-- cada vez que alguien abre una ficha.
--
-- Situacion BCRA: 1 normal .. 6 irrecuperable. Ese numero es el insumo
-- del semaforo que pidio el cliente.
-- =====================================================================
create table if not exists public.bcra_consultas (
  id                uuid primary key default gen_random_uuid(),
  agencia_id        uuid not null references public.agencias(id) on delete cascade,
  cliente_id        uuid references public.clientes(id) on delete cascade,
  cuit              text not null,
  denominacion      text,                  -- nombre que devuelve el BCRA
  -- Peor situacion informada entre todas las entidades (1..6).
  situacion_maxima  smallint,
  total_deuda_miles numeric(16,2),         -- el BCRA informa en miles de pesos
  cantidad_entidades smallint,
  tiene_cheques_rechazados boolean not null default false,
  cheques_sin_pagar smallint not null default 0,
  -- Banderas que el BCRA informa por entidad y que agravan el riesgo aunque
  -- la situacion sea baja. Se guardan desnormalizadas para poder filtrar
  -- "mostrame todos los interesados con juicio" sin abrir el jsonb.
  dias_atraso_max        smallint not null default 0,
  tiene_proceso_judicial boolean not null default false,
  tiene_refinanciaciones boolean not null default false,
  tiene_situacion_juridica boolean not null default false,
  en_revision            boolean not null default false,
  periodo                text,                  -- "202607": mes informado por el BCRA
  -- Detalle crudo por entidad, tal como llego, para poder mostrar el desglose
  -- sin volver a consultar y para auditar si el BCRA cambia su respuesta.
  entidades         jsonb,
  cheques           jsonb,
  payload_deudas    jsonb,
  payload_cheques   jsonb,
  consultado_por    uuid references auth.users(id) on delete set null,
  consultado_at     timestamptz not null default now(),
  -- El BCRA actualiza mensualmente; no tiene sentido reconsultar antes.
  expira_at         timestamptz not null default now() + interval '30 days',
  error             text
);
create index if not exists idx_bcra_cliente on public.bcra_consultas(cliente_id, consultado_at desc);
create index if not exists idx_bcra_cuit    on public.bcra_consultas(cuit, consultado_at desc);

-- Traduce la situacion BCRA al semaforo que pidio el cliente.
--   verde    -> situacion 1-2, sin cheques rechazados: apto para financiar
--   amarillo -> situacion 3, o cheques rechazados ya pagados: mirar con lupa
--   rojo     -> situacion 4-6, o cheques sin pagar: no dar credito
create or replace function public.semaforo_de_situacion(
  p_situacion smallint,
  p_cheques_sin_pagar smallint default 0,
  p_tiene_cheques boolean default false,
  p_proceso_judicial boolean default false,
  p_dias_atraso smallint default 0)
returns semaforo_crediticio
language sql
immutable
as $fn$
  select case
    when p_situacion is null then 'sin_datos'::semaforo_crediticio
    -- Rojo: irrecuperable/con alto riesgo de insolvencia, cheques impagos o juicio.
    when p_situacion >= 4
      or coalesce(p_cheques_sin_pagar, 0) > 0
      or coalesce(p_proceso_judicial, false) then 'rojo'::semaforo_crediticio
    -- Amarillo: cumplimiento deficiente, o senales tempranas de mora.
    when p_situacion = 3
      or coalesce(p_tiene_cheques, false)
      or coalesce(p_dias_atraso, 0) > 30 then 'amarillo'::semaforo_crediticio
    when p_situacion <= 2 then 'verde'::semaforo_crediticio
    else 'sin_datos'::semaforo_crediticio
  end;
$fn$;

-- Ultima consulta vigente de cada cliente, ya traducida a semaforo.
-- Es lo que consume la pantalla de Interesados.
create or replace view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       b.situacion_maxima,
       b.total_deuda_miles,
       b.cantidad_entidades,
       b.cheques_sin_pagar,
       b.tiene_cheques_rechazados,
       b.dias_atraso_max,
       b.tiene_proceso_judicial,
       b.tiene_refinanciaciones,
       b.tiene_situacion_juridica,
       b.en_revision,
       b.periodo,
       b.entidades,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                        as consulta_vencida,
       coalesce(
         public.semaforo_de_situacion(
           b.situacion_maxima, b.cheques_sin_pagar, b.tiene_cheques_rechazados,
           b.tiene_proceso_judicial, b.dias_atraso_max),
         'sin_datos'::semaforo_crediticio)          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;

-- >>>>>>>>>>>>>>>>>>>>  0007_config_marketing.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0007: configuracion por agencia + email marketing
-- =====================================================================

-- Umbrales y parametros del motor de calculo. Una fila por agencia: cada
-- concesionaria define su propio margen objetivo y sus propios plazos de
-- rotacion, y todo el sistema se recalcula solo (igual que el HTML original).
create table if not exists public.agencia_config (
  agencia_id  uuid primary key references public.agencias(id) on delete cascade,

  -- Semaforo de ANTIGUEDAD en stock (dias). Ojo: es otro semaforo distinto
  -- al crediticio del cliente; este mide cuanto tarda en rotar la unidad.
  dias_verde     smallint not null default 30,
  dias_amarillo  smallint not null default 60,
  dias_rojo      smallint not null default 90,

  margen_minimo  numeric(6,4) not null default 0.10,
  margen_objetivo numeric(6,4) not null default 0.30,
  tolerancia_caida_margen numeric(6,4) not null default 0.005,
  tolerancia_desvio_precio numeric(6,4) not null default 0.02,
  umbral_gastos_altos numeric(16,2) not null default 1000000,

  -- A cuanto se redondea el precio a publicar (50.000 -> termina en 00.000).
  redondeo       numeric(12,2) not null default 50000,
  capacidad      smallint not null default 60,   -- unidades que entran en el predio
  tasa_financiacion_mensual numeric(6,4) not null default 0.06,

  -- Que dolar usa esta agencia para expresar la ganancia real en USD.
  tipo_cambio_preferido tipo_cotizacion not null default 'oficial',

  updated_at timestamptz not null default now(),

  constraint dias_ordenados check (dias_verde < dias_amarillo and dias_amarillo < dias_rojo),
  constraint margenes_ordenados check (margen_minimo <= margen_objetivo),
  constraint margenes_en_rango check (margen_objetivo < 1 and margen_minimo >= 0)
);

drop trigger if exists trg_config_updated on public.agencia_config;
create trigger trg_config_updated before update on public.agencia_config
  for each row execute function public.tocar_updated_at();

-- Toda agencia nace con la configuracion por defecto: nunca hay una agencia
-- sin config, asi el motor de calculo no tiene que contemplar el caso null.
create or replace function public.crear_config_por_defecto()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.agencia_config (agencia_id) values (new.id)
  on conflict (agencia_id) do nothing;
  return new;
end $fn$;

drop trigger if exists trg_agencia_config on public.agencias;
create trigger trg_agencia_config after insert on public.agencias
  for each row execute function public.crear_config_por_defecto();

-- =====================================================================
-- EMAIL MARKETING
-- El envio real lo hace una Edge Function contra un proveedor (Resend o
-- Brevo). La base guarda que se mando, a quien y que paso con cada envio.
-- =====================================================================

create table if not exists public.plantillas_email (
  id         uuid primary key default gen_random_uuid(),
  agencia_id uuid not null references public.agencias(id) on delete cascade,
  nombre     text not null,
  asunto     text not null,
  cuerpo_html text not null,
  -- Variables disponibles para reemplazo: {{nombre}}, {{vehiculo}}, {{precio}}...
  variables  text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.campanas (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  nombre      text not null,
  asunto      text not null,
  cuerpo_html text not null,
  remitente_nombre text,
  remitente_email  citext,
  estado      estado_campana not null default 'borrador',
  -- Criterio de audiencia guardado como filtro, no como lista congelada:
  -- {"semaforo":["verde"],"interes_min":4,"vehiculo_marca":"Toyota"}
  filtro      jsonb not null default '{}'::jsonb,
  programada_para timestamptz,
  enviada_at  timestamptz,
  total_destinatarios integer not null default 0,
  total_enviados integer not null default 0,
  total_aperturas integer not null default 0,
  total_clicks   integer not null default 0,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_campanas_agencia on public.campanas(agencia_id, created_at desc);
create index if not exists idx_campanas_programadas on public.campanas(programada_para)
  where estado = 'programada';

create table if not exists public.campana_destinatarios (
  id          uuid primary key default gen_random_uuid(),
  campana_id  uuid not null references public.campanas(id) on delete cascade,
  cliente_id  uuid not null references public.clientes(id) on delete cascade,
  email       citext not null,
  estado      estado_envio not null default 'pendiente',
  -- Id que devuelve el proveedor, para casar los webhooks de apertura/click.
  proveedor_id text,
  enviado_at  timestamptz,
  abierto_at  timestamptz,
  click_at    timestamptz,
  error       text,
  unique (campana_id, cliente_id)
);
create index if not exists idx_destinatarios_campana on public.campana_destinatarios(campana_id, estado);
create index if not exists idx_destinatarios_proveedor on public.campana_destinatarios(proveedor_id)
  where proveedor_id is not null;

drop trigger if exists trg_campanas_updated on public.campanas;
create trigger trg_campanas_updated before update on public.campanas
  for each row execute function public.tocar_updated_at();

drop trigger if exists trg_plantillas_updated on public.plantillas_email;
create trigger trg_plantillas_updated before update on public.plantillas_email
  for each row execute function public.tocar_updated_at();

-- Cuando un cliente pide la baja, queda registrado el momento exacto.
create or replace function public.sellar_baja_marketing()
returns trigger language plpgsql as $fn$
begin
  if old.acepta_marketing and not new.acepta_marketing then
    new.baja_marketing_at := now();
  elsif not old.acepta_marketing and new.acepta_marketing then
    new.baja_marketing_at := null;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_baja_marketing on public.clientes;
create trigger trg_baja_marketing before update on public.clientes
  for each row execute function public.sellar_baja_marketing();

-- =====================================================================
-- AUDITORIA — quien toco que y cuando.
-- En un ERP donde se manejan precios de compra y margenes, poder responder
-- "quien bajo el precio de esta unidad" no es opcional.
-- =====================================================================
create table if not exists public.auditoria (
  id          bigserial primary key,
  agencia_id  uuid,
  tabla       text not null,
  registro_id uuid,
  accion      text not null,           -- INSERT | UPDATE | DELETE
  usuario_id  uuid,
  datos_antes  jsonb,
  datos_despues jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists idx_auditoria_registro on public.auditoria(tabla, registro_id, created_at desc);
create index if not exists idx_auditoria_agencia  on public.auditoria(agencia_id, created_at desc);

create or replace function public.registrar_auditoria()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_agencia uuid;
  v_id      uuid;
begin
  if tg_op = 'DELETE' then
    v_agencia := (to_jsonb(old)->>'agencia_id')::uuid;
    -- agencia_config no tiene columna id: su clave es agencia_id.
    v_id      := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'agencia_id')::uuid;
    insert into public.auditoria (agencia_id, tabla, registro_id, accion, usuario_id, datos_antes)
    values (v_agencia, tg_table_name, v_id, tg_op, auth.uid(), to_jsonb(old));
    return old;
  else
    v_agencia := (to_jsonb(new)->>'agencia_id')::uuid;
    v_id      := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'agencia_id')::uuid;
    insert into public.auditoria (agencia_id, tabla, registro_id, accion, usuario_id, datos_antes, datos_despues)
    values (v_agencia, tg_table_name, v_id, tg_op, auth.uid(),
            case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
    return new;
  end if;
end $fn$;

-- Se audita lo que toca plata. Gastos e interacciones generan mucho ruido
-- y poco valor, asi que quedan afuera a proposito.
drop trigger if exists trg_audit_vehiculos on public.vehiculos;
create trigger trg_audit_vehiculos after insert or update or delete on public.vehiculos
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_precios on public.cambios_precio;
create trigger trg_audit_precios after insert or update or delete on public.cambios_precio
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_ventas on public.ventas;
create trigger trg_audit_ventas after insert or update or delete on public.ventas
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_config on public.agencia_config;
create trigger trg_audit_config after update on public.agencia_config
  for each row execute function public.registrar_auditoria();

-- >>>>>>>>>>>>>>>>>>>>  0008_motor_calculo.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0008: MOTOR DE CALCULO
--
-- Port 1:1 de computeInventory() del HTML original (rotacion_1.html,
-- lineas 677-747), que a su vez replicaba las formulas de la hoja
-- "Inventario" del Excel del cliente.
--
-- Por que en SQL y no en Dart: estas formulas definen cuanta plata gana
-- la agencia. Si viven en la app, hay que reimplementarlas en cada
-- plataforma y cualquier divergencia se paga en pesos. Aca hay UNA sola
-- definicion; la app solo la lee. Los simuladores interactivos (precio
-- sugerido, cuotas) si viven en Dart, porque son "que pasaria si" que no
-- se persisten.
--
-- Las diferencias intencionales respecto del original estan comentadas
-- con [CAMBIO].
-- =====================================================================

-- Gastos de cada vehiculo, en nominal y ajustados por IPC a valor de hoy.
create or replace view public.v_vehiculo_gastos as
select g.vehiculo_id,
       count(*)::int                                    as cantidad_gastos,
       coalesce(sum(g.importe), 0)                      as gastos_nominal,
       -- Cada gasto se trae a moneda de hoy con el IPC del mes en que se hizo:
       --   importe * indice_hoy / indice_del_mes_del_gasto
       coalesce(sum(g.importe * public.ipc_indice_hoy()
                    / nullif(public.ipc_indice_en(g.fecha), 0)), 0) as gastos_ajustados
from public.gastos g
group by g.vehiculo_id;

-- Ultimo precio publicado de cada vehiculo.
create or replace view public.v_vehiculo_precio_actual as
select distinct on (cp.vehiculo_id)
       cp.vehiculo_id,
       cp.precio_nuevo as precio_publicado,
       cp.fecha        as fecha_precio,
       cp.motivo       as motivo_precio
from public.cambios_precio cp
order by cp.vehiculo_id, cp.fecha desc, cp.created_at desc;

-- ---------------------------------------------------------------------
-- VISTA PRINCIPAL: una fila por vehiculo con todo ya calculado.
-- Es la que alimenta el Dashboard, el Inventario y la Ficha.
-- ---------------------------------------------------------------------
create or replace view public.v_inventario as
with base as (
  select
    v.*,
    cfg.dias_verde, cfg.dias_amarillo, cfg.dias_rojo,
    cfg.margen_minimo, cfg.margen_objetivo,
    cfg.tolerancia_caida_margen, cfg.tolerancia_desvio_precio,
    cfg.umbral_gastos_altos, cfg.redondeo, cfg.tipo_cambio_preferido,

    vt.id             as venta_id,
    vt.fecha_venta,
    vt.precio_final,
    coalesce(vt.gastos_finales, 0) as gastos_finales,

    coalesce(vg.gastos_nominal, 0)   as gastos_vehiculo,
    coalesce(vg.gastos_ajustados, 0) as gastos_vehiculo_ajustados,
    coalesce(vg.cantidad_gastos, 0)  as cantidad_gastos,

    -- Si nunca se cambio el precio, rige el precio objetivo de alta.
    coalesce(vpa.precio_publicado, v.precio_objetivo) as precio_actual,
    vpa.fecha_precio,

    public.ipc_indice_hoy()                as indice_hoy,
    public.ipc_indice_en(v.fecha_ingreso)  as indice_ingreso,
    coalesce(public.cotizacion_vigente(cfg.tipo_cambio_preferido), 0) as tipo_cambio
  from public.vehiculos v
  join public.agencia_config cfg           on cfg.agencia_id = v.agencia_id
  left join public.ventas vt               on vt.vehiculo_id = v.id
  left join public.v_vehiculo_gastos vg    on vg.vehiculo_id = v.id
  left join public.v_vehiculo_precio_actual vpa on vpa.vehiculo_id = v.id
  where v.deleted_at is null
),
calc as (
  select
    b.*,
    (b.venta_id is not null) as vendido,
    -- gastos_acum = gastos del vehiculo + gastos de cierre de la venta
    (b.gastos_vehiculo + b.gastos_finales) as gastos_acum,
    (b.precio_compra + b.gastos_vehiculo + b.gastos_finales) as costo_total,
    -- El reloj para: si se vendio cuenta hasta la venta, si no hasta hoy.
    (coalesce(b.fecha_venta, current_date) - b.fecha_ingreso) as dias_en_stock,
    -- Costo a valor de hoy. Nota: gastos_finales NO se ajusta por IPC,
    -- igual que en el original, porque la venta es reciente por definicion.
    (b.precio_compra * b.indice_hoy / nullif(b.indice_ingreso, 0)
       + b.gastos_vehiculo_ajustados
       + b.gastos_finales) as costo_total_hoy
  from base b
)
select
  c.id,
  c.agencia_id,
  c.codigo,
  c.marca,
  c.modelo,
  c.anio,
  c.version,
  c.km,
  c.patente,
  c.fecha_compra,
  c.fecha_ingreso,
  c.precio_compra,
  c.precio_objetivo,
  c.observaciones,
  c.ref_version_id,
  c.created_at,

  -- La venta manda sobre el estado guardado, igual que en el original.
  case when c.vendido then 'vendido'::estado_vehiculo else c.estado end as estado,
  c.vendido,
  c.venta_id,
  c.fecha_venta,
  c.precio_final,

  c.cantidad_gastos,
  c.gastos_acum,
  c.gastos_finales,
  c.costo_total,
  c.dias_en_stock,
  c.precio_actual,
  c.fecha_precio,

  -- Capital parado en el predio. Lo vendido ya no inmoviliza plata.
  case when c.vendido then 0 else c.costo_total end            as capital_inmovilizado,
  (c.precio_actual - c.costo_total)                            as ganancia_estimada,

  -- Margen sobre PRECIO DE VENTA (no sobre costo): (precio - costo) / precio.
  (c.precio_objetivo - c.costo_total) / nullif(c.precio_objetivo, 0) as margen_esperado,
  (c.precio_actual   - c.costo_total) / nullif(c.precio_actual, 0)   as margen_actual,
  case when c.vendido
       then (c.precio_final - c.costo_total) / nullif(c.precio_final, 0)
  end                                                                as margen_real,

  -- Precio al que habria que publicarlo para alcanzar cada margen.
  c.costo_total / nullif(1 - c.margen_objetivo, 0)             as precio_para_margen_objetivo,
  c.costo_total / nullif(1 - c.margen_minimo, 0)               as precio_para_margen_minimo,
  c.costo_total                                                as precio_equilibrio,
  -- Redondeado hacia arriba al multiplo que use la agencia: el precio que
  -- se publica de verdad (el original usaba roundUp con step = redondeo).
  ceil((c.costo_total / nullif(1 - c.margen_objetivo, 0)) / nullif(c.redondeo, 0))
    * c.redondeo                                               as precio_sugerido,

  (c.costo_total / nullif(1 - c.margen_objetivo, 0)) / nullif(c.precio_actual, 0) - 1
                                                               as ajuste_necesario,
  c.precio_actual / nullif(c.precio_objetivo, 0) - 1            as var_vs_objetivo,
  c.gastos_acum / nullif(c.precio_compra, 0)                   as gastos_ratio,
  case when c.dias_en_stock > 0 then c.costo_total / c.dias_en_stock else c.costo_total end
                                                               as costo_diario,

  -- ---- Ajustado por inflacion (IPC INDEC) ----
  c.indice_ingreso,
  c.indice_hoy,
  c.costo_total_hoy,
  (c.precio_actual - c.costo_total_hoy)                        as ganancia_real_ipc,
  (c.precio_actual - c.costo_total_hoy) / nullif(c.precio_actual, 0) as margen_real_ipc,
  c.tipo_cambio,
  case when c.tipo_cambio > 0
       then (c.precio_actual - c.costo_total_hoy) / c.tipo_cambio
  end                                                          as ganancia_real_usd,

  -- ---- Semaforo de antiguedad en stock ----
  case
    when c.vendido then 'vendido'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_rojo     then 'critico'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_amarillo then 'atencion'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_verde    then 'observar'
    else 'normal'
  end as alerta,

  -- Umbrales vigentes, para que la app pinte sin volver a pedir la config.
  c.dias_verde, c.dias_amarillo, c.dias_rojo,
  c.margen_minimo, c.margen_objetivo, c.umbral_gastos_altos,
  c.tolerancia_caida_margen, c.tolerancia_desvio_precio,

  -- Valor de revista de ArgAutos, si la unidad esta enlazada al catalogo.
  rp.precio_ars   as revista_ars,
  rp.precio_usd   as revista_usd,
  rp.actualizado_at as revista_actualizada_at,
  case when rp.precio_ars > 0
       then c.precio_actual / rp.precio_ars - 1
  end as var_vs_revista
from calc c
left join public.ref_precios rp
       on rp.version_id = c.ref_version_id and rp.anio = c.anio;

comment on view public.v_inventario is
  'Motor de calculo. Port de computeInventory() del HTML original. Fuente unica de verdad de costos, margenes y alertas.';

-- ---------------------------------------------------------------------
-- Diagnostico en texto (el parrafo que arma diagParts en el original).
-- Va en funcion aparte y no en la vista porque es presentacion, no dato:
-- si manana cambia la redaccion o se traduce, no se toca el motor.
-- ---------------------------------------------------------------------
create or replace function public.diagnostico_vehiculo(p_vehiculo uuid)
returns text
language plpgsql
stable
as $fn$
declare
  r     record;
  partes text[] := '{}';
begin
  select * into r from public.v_inventario where id = p_vehiculo;
  if not found then return null; end if;

  if r.vendido then
    partes := partes || format('Vendido en %s dias con margen real de %s%%.',
                               r.dias_en_stock, round(coalesce(r.margen_real, 0) * 100, 1));
  else
    if r.dias_en_stock >= r.dias_rojo then
      partes := partes || format('Lleva %s dias en stock, muy por encima del plazo objetivo.', r.dias_en_stock);
    elsif r.dias_en_stock >= r.dias_amarillo then
      partes := partes || format('Lleva %s dias en stock.', r.dias_en_stock);
    elsif r.dias_en_stock >= r.dias_verde then
      partes := partes || format('Lleva %s dias en stock, dentro de lo esperable.', r.dias_en_stock);
    else
      partes := partes || format('Lleva %s dias en stock, plazo normal.', r.dias_en_stock);
    end if;

    if r.margen_actual < r.margen_minimo then
      partes := partes || format('Margen actual %s%%, por debajo del minimo.', round(r.margen_actual * 100, 1));
    end if;
    if r.margen_actual < r.margen_esperado - r.tolerancia_caida_margen then
      partes := partes || format('El margen cayo de %s%% a %s%%.',
                                 round(r.margen_esperado * 100, 1), round(r.margen_actual * 100, 1));
    end if;
    if r.gastos_acum >= r.umbral_gastos_altos then
      partes := partes || format('Acumula %s de gastos.', to_char(r.gastos_acum, 'FM$999G999G999'));
    end if;
    if r.margen_actual >= r.margen_objetivo then
      partes := partes || 'Margen por encima del objetivo.';
    end if;
    if r.ajuste_necesario > r.tolerancia_desvio_precio then
      -- Precio exacto, no el redondeado: es el umbral real del margen.
      -- El redondeado a publicar esta en v_inventario.precio_sugerido.
      partes := partes || format('Para el margen objetivo habria que publicarlo a %s.',
                                 to_char(r.precio_para_margen_objetivo, 'FM$999G999G999'));
    end if;
  end if;

  return array_to_string(partes, ' ');
end $fn$;

-- ---------------------------------------------------------------------
-- Totales de la agencia para las tarjetas del Dashboard.
-- ---------------------------------------------------------------------
create or replace view public.v_dashboard as
select
  agencia_id,
  count(*) filter (where not vendido)                       as unidades_en_stock,
  count(*) filter (where vendido)                           as unidades_vendidas,
  coalesce(sum(capital_inmovilizado), 0)                    as capital_inmovilizado,
  coalesce(sum(gastos_acum) filter (where not vendido), 0)  as gastos_en_stock,
  coalesce(sum(ganancia_estimada) filter (where not vendido), 0) as ganancia_potencial,
  coalesce(sum(precio_final - costo_total) filter (where vendido), 0) as ganancia_realizada,
  -- Para una unidad YA VENDIDA la ganancia se mide contra el precio final de
  -- venta, no contra el ultimo precio publicado. Usar precio_actual aca
  -- infla la ganancia cada vez que se cerro por debajo de la publicacion,
  -- que es lo habitual al negociar.
  coalesce(sum(precio_final - costo_total_hoy) filter (where vendido), 0)
    as ganancia_realizada_ipc,
  coalesce(sum((precio_final - costo_total_hoy) / nullif(tipo_cambio, 0))
    filter (where vendido), 0) as ganancia_realizada_usd,
  round(avg(dias_en_stock) filter (where not vendido), 1)   as dias_promedio_stock,
  round(avg(dias_en_stock) filter (where vendido), 1)       as dias_promedio_venta,
  round(avg(margen_actual) filter (where not vendido), 4)   as margen_promedio,
  round(avg(margen_real) filter (where vendido), 4)         as margen_real_promedio,
  count(*) filter (where alerta = 'critico')                as criticos,
  count(*) filter (where alerta = 'atencion')               as en_atencion,
  count(*) filter (where alerta = 'observar')               as en_observacion,
  count(*) filter (where not vendido and margen_actual < margen_minimo) as bajo_margen_minimo
from public.v_inventario
group by agencia_id;

-- ---------------------------------------------------------------------
-- Evolucion mensual: capital inmovilizado y ganancia acumulada mes a mes.
-- Port de evolucionMensual(). Alimenta los graficos de linea.
-- ---------------------------------------------------------------------
create or replace function public.evolucion_mensual(p_agencia uuid, p_meses int default 14)
returns table (
  mes date,
  capital_inmovilizado numeric,
  ganancia_nominal_acum numeric,
  ganancia_real_acum numeric,
  unidades_en_stock int,
  unidades_vendidas_acum int
)
language sql
stable
as $fn$
  with meses as (
    select generate_series(
             date_trunc('month', current_date)::date - ((p_meses - 1) || ' months')::interval,
             date_trunc('month', current_date)::date,
             '1 month'::interval)::date as mes
  ),
  cortes as (
    select m.mes, (m.mes + interval '1 month - 1 day')::date as fin_mes
    from meses m
  )
  select
    c.mes,
    coalesce(sum(
      case when v.fecha_ingreso <= c.fin_mes
            and (vt.fecha_venta is null or vt.fecha_venta > c.fin_mes)
      then v.precio_compra + coalesce((
             select sum(g.importe) from public.gastos g
              where g.vehiculo_id = v.id and g.fecha <= c.fin_mes), 0)
      end), 0) as capital_inmovilizado,
    coalesce(sum(
      case when vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes
      then vt.precio_final - (v.precio_compra + coalesce((
             select sum(g.importe) from public.gastos g
              where g.vehiculo_id = v.id), 0) + coalesce(vt.gastos_finales, 0))
      end), 0) as ganancia_nominal_acum,
    coalesce(sum(
      case when vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes
      then vt.precio_final - inv.costo_total_hoy
      end), 0) as ganancia_real_acum,
    count(*) filter (
      where v.fecha_ingreso <= c.fin_mes
        and (vt.fecha_venta is null or vt.fecha_venta > c.fin_mes))::int as unidades_en_stock,
    count(*) filter (
      where vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes)::int as unidades_vendidas_acum
  from cortes c
  cross join public.vehiculos v
  left join public.ventas vt on vt.vehiculo_id = v.id
  left join lateral (
    select (i.costo_total_hoy) from public.v_inventario i where i.id = v.id
  ) inv on true
  where v.agencia_id = p_agencia and v.deleted_at is null
  group by c.mes
  order by c.mes;
$fn$;

-- >>>>>>>>>>>>>>>>>>>>  0009_rls_policies.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0009: Row Level Security
--
-- Regla del proyecto: NINGUNA tabla queda sin RLS. El aislamiento entre
-- agencias se garantiza en la base, no en la app. Si manana alguien se
-- lleva la anon key (que es publica por diseno) igual no puede leer los
-- datos de otra agencia.
-- =====================================================================

-- CRITICO: por defecto una vista corre con los permisos de su DUEÑO, lo
-- que saltearia el RLS de las tablas que consulta. security_invoker hace
-- que corra con los permisos de QUIEN la consulta. Sin esto, v_inventario
-- filtraria el inventario de todas las agencias a cualquier usuario.
alter view public.v_inventario              set (security_invoker = on);
alter view public.v_dashboard               set (security_invoker = on);
alter view public.v_vehiculo_gastos         set (security_invoker = on);
alter view public.v_vehiculo_precio_actual  set (security_invoker = on);
alter view public.v_clientes_semaforo       set (security_invoker = on);
alter view public.ref_catalogo              set (security_invoker = on);

alter table public.agencias             enable row level security;
alter table public.perfiles             enable row level security;
alter table public.membresias           enable row level security;
alter table public.invitaciones         enable row level security;
alter table public.agencia_config       enable row level security;
alter table public.vehiculos            enable row level security;
alter table public.vehiculo_fotos       enable row level security;
alter table public.gastos               enable row level security;
alter table public.cambios_precio       enable row level security;
alter table public.ventas               enable row level security;
alter table public.clientes             enable row level security;
alter table public.oportunidades        enable row level security;
alter table public.interacciones        enable row level security;
alter table public.bcra_consultas       enable row level security;
alter table public.campanas             enable row level security;
alter table public.campana_destinatarios enable row level security;
alter table public.plantillas_email     enable row level security;
alter table public.auditoria            enable row level security;
alter table public.ref_marcas           enable row level security;
alter table public.ref_modelos          enable row level security;
alter table public.ref_versiones        enable row level security;
alter table public.ref_precios          enable row level security;
alter table public.ref_sync_log         enable row level security;
alter table public.ipc_serie            enable row level security;
alter table public.cotizaciones         enable row level security;

-- =====================================================================
-- AGENCIAS
-- =====================================================================
drop policy if exists agencias_select on public.agencias;
create policy agencias_select on public.agencias for select to authenticated
  using (public.puede_ver_agencia(id));

-- Solo nosotros damos de alta agencias. Es el nucleo del modelo de negocio:
-- el cliente no puede autocrearse una agencia desde la app.
drop policy if exists agencias_insert on public.agencias;
create policy agencias_insert on public.agencias for insert to authenticated
  with check (public.es_desarrollador());

-- El owner puede editar los datos de SU agencia (logo, direccion...),
-- pero activa/plan/vigente_hasta solo los toca el desarrollador: eso se
-- refuerza con un trigger, porque RLS no distingue por columna.
drop policy if exists agencias_update on public.agencias;
create policy agencias_update on public.agencias for update to authenticated
  using (public.tiene_rol(id, array['owner']::rol_membresia[]))
  with check (public.tiene_rol(id, array['owner']::rol_membresia[]));

drop policy if exists agencias_delete on public.agencias;
create policy agencias_delete on public.agencias for delete to authenticated
  using (public.es_desarrollador());

-- Blinda los campos comerciales: aunque el owner pase el RLS del update,
-- no puede darse a si mismo un plan mejor ni extender su vencimiento.
create or replace function public.proteger_campos_comerciales()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if not public.es_desarrollador() then
    new.activa        := old.activa;
    new.plan          := old.plan;
    new.vigente_hasta := old.vigente_hasta;
    new.slug          := old.slug;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_proteger_agencia on public.agencias;
create trigger trg_proteger_agencia before update on public.agencias
  for each row execute function public.proteger_campos_comerciales();

-- =====================================================================
-- PERFILES
-- =====================================================================
drop policy if exists perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles for select to authenticated
  using (
    id = auth.uid()
    or public.es_desarrollador()
    -- Tambien veo a mis companeros de agencia (para asignar oportunidades).
    or exists (
      select 1 from public.membresias m
      where m.usuario_id = perfiles.id
        and m.agencia_id in (select public.mis_agencias()))
  );

drop policy if exists perfiles_update on public.perfiles;
create policy perfiles_update on public.perfiles for update to authenticated
  using (id = auth.uid() or public.es_desarrollador())
  with check (id = auth.uid() or public.es_desarrollador());

-- Nadie se autoasciende a desarrollador desde la app.
create or replace function public.proteger_flag_desarrollador()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if not public.es_desarrollador() then
    new.es_desarrollador := old.es_desarrollador;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_proteger_perfil on public.perfiles;
create trigger trg_proteger_perfil before update on public.perfiles
  for each row execute function public.proteger_flag_desarrollador();

-- =====================================================================
-- MEMBRESIAS e INVITACIONES
-- =====================================================================
drop policy if exists membresias_select on public.membresias;
create policy membresias_select on public.membresias for select to authenticated
  using (usuario_id = auth.uid() or public.puede_ver_agencia(agencia_id));

drop policy if exists membresias_escritura on public.membresias;
create policy membresias_escritura on public.membresias for all to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

drop policy if exists invitaciones_todo on public.invitaciones;
create policy invitaciones_todo on public.invitaciones for all to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

-- =====================================================================
-- CONFIGURACION
-- =====================================================================
drop policy if exists config_select on public.agencia_config;
create policy config_select on public.agencia_config for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

drop policy if exists config_update on public.agencia_config;
create policy config_update on public.agencia_config for update to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

-- =====================================================================
-- DATOS DE NEGOCIO
-- Patron comun: leen todos los miembros, escriben los que no son
-- solo_lectura, y borra unicamente owner/admin.
-- =====================================================================
do $$
declare
  t text;
  tablas text[] := array[
    'vehiculos','vehiculo_fotos','gastos','cambios_precio','ventas',
    'clientes','oportunidades','interacciones','bcra_consultas',
    'campanas','plantillas_email'];
begin
  foreach t in array tablas loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format($f$create policy %I on public.%I for select to authenticated
                      using (public.puede_ver_agencia(agencia_id))$f$, t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format($f$create policy %I on public.%I for insert to authenticated
                      with check (public.puede_editar(agencia_id))$f$, t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($f$create policy %I on public.%I for update to authenticated
                      using (public.puede_editar(agencia_id))
                      with check (public.puede_editar(agencia_id))$f$, t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($f$create policy %I on public.%I for delete to authenticated
                      using (public.puede_administrar(agencia_id))$f$, t || '_delete', t);
  end loop;
end $$;

-- Destinatarios de campana: no tienen agencia_id propio, se resuelve por
-- la campana a la que pertenecen.
drop policy if exists destinatarios_select on public.campana_destinatarios;
create policy destinatarios_select on public.campana_destinatarios for select to authenticated
  using (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_ver_agencia(c.agencia_id)));

drop policy if exists destinatarios_escritura on public.campana_destinatarios;
create policy destinatarios_escritura on public.campana_destinatarios for all to authenticated
  using (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_editar(c.agencia_id)))
  with check (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_editar(c.agencia_id)));

-- =====================================================================
-- AUDITORIA — se lee, no se escribe ni se corrige. Solo owner/admin.
-- Los inserts los hace el trigger, que es security definer y no pasa por RLS.
-- =====================================================================
drop policy if exists auditoria_select on public.auditoria;
create policy auditoria_select on public.auditoria for select to authenticated
  using (public.puede_administrar(agencia_id));

-- =====================================================================
-- DATOS DE REFERENCIA — los lee cualquier usuario logueado (son publicos:
-- IPC del INDEC, dolar, catalogo de precios). Los escribe solo el backend
-- con service_role, que no pasa por RLS: por eso no hay policy de insert.
-- =====================================================================
do $$
declare
  t text;
begin
  foreach t in array array['ref_marcas','ref_modelos','ref_versiones','ref_precios',
                           'ref_sync_log','ipc_serie','cotizaciones'] loop
    execute format('drop policy if exists %I on public.%I', t || '_lectura', t);
    execute format($f$create policy %I on public.%I for select to authenticated
                      using (true)$f$, t || '_lectura', t);
  end loop;
end $$;

-- =====================================================================
-- STORAGE — fotos de vehiculos.
-- Convencion de ruta: {agencia_id}/{vehiculo_id}/{archivo}
-- El primer segmento de la ruta es el que decide quien ve que.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vehiculos', 'vehiculos', false, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

drop policy if exists fotos_ver on storage.objects;
create policy fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'vehiculos'
         and public.puede_ver_agencia((storage.foldername(name))[1]::uuid));

drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'vehiculos'
              and public.puede_editar((storage.foldername(name))[1]::uuid));

drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'vehiculos'
         and public.puede_editar((storage.foldername(name))[1]::uuid));

-- =====================================================================
-- GRANTS: el rol anon no toca NADA. Todo exige sesion iniciada.
-- =====================================================================
revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on public.v_inventario, public.v_dashboard, public.v_clientes_semaforo,
                public.ref_catalogo to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- >>>>>>>>>>>>>>>>>>>>  0010_seed_referencia.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0010: carga inicial de datos publicos
--
-- La serie IPC viene tal cual del HTML del cliente, que la tomo de los
-- informes tecnicos del INDEC. Se mantiene la fuente y la URL de cada mes
-- para poder auditar de donde salio cada numero.
--
-- El ultimo mes esta marcado como proyeccion: el INDEC publica agosto a
-- mediados de septiembre. La Edge Function `sync-indices` lo reemplaza por
-- el dato real cuando sale.
-- =====================================================================

insert into public.ipc_serie (mes, variacion, fuente, url, es_proyeccion) values
  ('2025-07-01', null,  'Mes base de la serie (indice 100).', null, false),
  ('2025-08-01', 0.019, 'INDEC, Informe tecnico IPC — nivel general, total nacional.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-09-01', 0.021, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-10-01', 0.023, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-11-01', 0.025, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-12-01', 0.028, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-01-01', 0.029, 'INDEC, Informe tecnico IPC enero 2026 — nivel general 2,9% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_02_261443D4406C.pdf', false),
  ('2026-02-01', 0.029, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-03-01', 0.034, 'INDEC, Informe tecnico IPC marzo 2026 — nivel general 3,4% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_04_26853171E136.pdf', false),
  ('2026-04-01', 0.026, 'INDEC, Informe tecnico IPC abril 2026 — nivel general 2,6% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_05_2680B692D2F5.pdf', false),
  ('2026-05-01', 0.021, 'INDEC, Informe tecnico IPC mayo 2026 — nivel general 2,1% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_06_26C132AEE4E9.pdf', false),
  ('2026-06-01', 0.019, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-07-01', 0.021, 'INDEC, Informe tecnico IPC julio 2026 — nivel general 2,1% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-08-01', 0.021, 'PROYECCION: se repite la variacion de julio hasta que el INDEC publique agosto.', null, true)
on conflict (mes) do nothing;

select public.recalcular_ipc();

-- Cotizaciones iniciales, tomadas de la config del HTML (21/08/2026).
-- A partir de aca las actualiza la Edge Function `sync-indices` contra la
-- API de estadisticas cambiarias del BCRA.
insert into public.cotizaciones (fecha, tipo, compra, venta, fuente) values
  ('2026-08-21', 'oficial',   1495, 1515, 'Config del sistema original del cliente'),
  ('2026-08-21', 'mayorista', 1489, 1499, 'Config del sistema original del cliente'),
  ('2026-08-21', 'blue',      1530, 1550, 'Config del sistema original del cliente')
on conflict (fecha, tipo) do nothing;
