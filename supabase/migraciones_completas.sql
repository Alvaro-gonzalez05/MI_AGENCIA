-- =====================================================================
-- MI AGENCIA — esquema completo
-- Las migraciones de supabase/migrations/ concatenadas en orden.
-- Generado automaticamente: no editar a mano, editar las migraciones.
--
-- Para usarlo: pegar entero en el SQL Editor de Supabase y ejecutar.
-- Es idempotente, se puede volver a correr sin romper nada.
--
-- Regenerar con: node tests/generar_sql_completo.mjs
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
--
-- La guarda `auth.uid() is not null` deja pasar al administrador. Sin ella, ni
-- el SQL Editor ni service_role pueden tocar estos campos, porque
-- es_desarrollador() depende de auth.uid() y sin JWT devuelve false. Es seguro
-- porque el RLS ya filtro quien llega hasta aca: con uid nulo ninguna policy
-- da true, asi que el unico que pasa es service_role.
create or replace function public.proteger_campos_comerciales()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not public.es_desarrollador() then
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
--
-- Misma guarda que arriba: sin ella quedaba imposible dar de alta al PRIMER
-- desarrollador, porque el trigger revertia el UPDATE en silencio incluso
-- corriendolo desde el SQL Editor.
create or replace function public.proteger_flag_desarrollador()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if auth.uid() is not null and not public.es_desarrollador() then
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


-- >>>>>>>>>>>>>>>>>>>>  0011_endurecer_funciones.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0011: endurecimiento de funciones
--
-- Sale de correr el linter de seguridad de Supabase contra la base real.
-- Todos los bucles excluyen lo que pertenece a una extension (citext,
-- pg_trgm, unaccent, pgcrypto): esas funciones son de la extension, no
-- nuestras, y no somos duenos para alterarlas.
-- =====================================================================

create or replace function pg_temp.funciones_propias()
returns setof regprocedure language sql as $fn$
  select p.oid::regprocedure
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (
      select 1 from pg_depend d
      where d.objid = p.oid and d.deptype = 'e')
$fn$;

-- 1. search_path fijo en toda funcion propia.
--
-- Sin esto, una funcion resuelve los nombres de tabla con el search_path de
-- quien la llama. En una SECURITY DEFINER eso permite que alguien cree un
-- objeto homonimo en un esquema propio y logre que la funcion, corriendo con
-- permisos elevados, opere sobre SU objeto.
do $$
declare f regprocedure;
begin
  for f in
    select x from pg_temp.funciones_propias() x
    join pg_proc p on p.oid = x
    where p.prokind = 'f'
      and (p.proconfig is null
           or not exists (select 1 from unnest(p.proconfig) c
                           where c like 'search\_path=%'))
  loop
    execute format('alter function %s set search_path = public', f);
  end loop;
end $$;

-- 2. Nadie sin sesion ejecuta funciones nuestras.
--
-- Supabase da EXECUTE por defecto a anon y authenticated sobre todo lo creado
-- en public, asi que quedaban publicadas como RPC en /rest/v1/rpc/...
-- Ninguna filtraba datos (con anon, es_desarrollador() da false y
-- mis_agencias() viene vacia), pero no hay razon para exponerlas.
do $$
declare f regprocedure;
begin
  for f in select x from pg_temp.funciones_propias() x loop
    execute format('revoke all on function %s from anon, public', f);
  end loop;
end $$;

-- 3. Las funciones de trigger no las llama nadie a mano.
--
-- Las invoca Postgres al disparar el trigger. registrar_auditoria() o
-- handle_nuevo_usuario() no tienen por que ser alcanzables desde la API.
do $$
declare f regprocedure;
begin
  for f in
    select x from pg_temp.funciones_propias() x
    join pg_proc p on p.oid = x
    where p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from anon, authenticated, public', f);
  end loop;
end $$;

-- 4. Devolver el permiso a lo que SI tiene que poder llamar la app.
--
-- Las funciones de RLS son imprescindibles: las policies las evaluan con el
-- rol que consulta, asi que sin EXECUTE el usuario no podria leer ni sus
-- propios datos. El linter las sigue marcando como "ejecutables por usuarios
-- logueados", y es correcto que lo esten: ninguna devuelve datos ajenos
-- (es_desarrollador() responde por el que llama, mis_agencias() lista las
-- suyas, puede_ver_agencia() responde sobre su propio acceso).
grant execute on function public.es_desarrollador()               to authenticated;
grant execute on function public.mis_agencias()                   to authenticated;
grant execute on function public.puede_ver_agencia(uuid)          to authenticated;
grant execute on function public.tiene_rol(uuid, rol_membresia[]) to authenticated;
grant execute on function public.puede_editar(uuid)               to authenticated;
grant execute on function public.puede_administrar(uuid)          to authenticated;

-- Lectura que la app consume o va a consumir.
grant execute on function public.ipc_indice_en(date)                 to authenticated;
grant execute on function public.ipc_indice_hoy()                    to authenticated;
grant execute on function public.cotizacion_vigente(tipo_cotizacion) to authenticated;
grant execute on function public.siguiente_codigo_vehiculo(uuid)     to authenticated;
grant execute on function public.diagnostico_vehiculo(uuid)          to authenticated;
grant execute on function public.evolucion_mensual(uuid, int)        to authenticated;
grant execute on function
  public.semaforo_de_situacion(smallint, smallint, boolean, boolean, smallint)
  to authenticated;


-- >>>>>>>>>>>>>>>>>>>>  0012_instaladores.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
-- MI AGENCIA — 0012: instaladores para las actualizaciones automaticas
-- =====================================================================
-- Bucket PUBLICO con los instaladores de cada version y `ultima.json`, la
-- ficha que la app consulta para saber si hay una version nueva.
--
-- Publico a proposito: la app lo lee antes de iniciar sesion, y los
-- instaladores no contienen datos de ninguna agencia.
--
-- Nadie sube archivos desde la app: los sube el workflow de publicacion con
-- la clave de servicio, que no pasa por el RLS. Por eso no hace falta ninguna
-- politica de escritura.
--
-- El workflow tambien crea el bucket si no existe, asi que esta migracion es
-- para que el esquema quede documentado y reproducible, no un paso manual.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instaladores', 'instaladores', true, 52428800, null)
on conflict (id) do update set public = true;


-- >>>>>>>>>>>>>>>>>>>>  0013_bcra_semaforo.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0013: el semáforo distingue "sin deudas" de "sin consultar"
--
--  El BCRA devuelve 404 para dos casos muy distintos: la persona no existe,
--  o la persona existe y ninguna entidad informó deuda a su nombre. En los
--  dos, `situacion_maxima` queda en null.
--
--  Como estaba, `v_clientes_semaforo` mostraba 'sin_datos' en ambos, o sea
--  lo mismo que si nunca se hubiera consultado. Para el vendedor eso es un
--  error caro: a alguien limpio le aparecía el cartel "Sin consultar" y
--  volvía a consultar el BCRA para llegar de nuevo a la nada.
--
--  Ahora:
--    nunca consultado ....................... sin_datos
--    consultado, cero entidades ............. verde
--    consultado con deuda ................... lo que diga semaforo_de_situacion
--
--  `semaforo_de_situacion` NO cambia: sigue respondiendo solo "qué significa
--  esta situación". Quién fue consultado y quién no es cosa de la vista, que
--  es la única que sabe si hay una consulta detrás.
--
--  Cuidado: esta lógica está replicada en Dart (ConsultaBcra.semaforo, en
--  app/lib/dominio/bcra.dart) porque la app muestra el resultado de una
--  consulta recién hecha antes de releer la vista. Hay un test que ata las
--  dos: tests/semaforo_bcra.mjs. Si se toca una, se toca la otra.
-- =====================================================================

-- Se borra y se rehace en vez de `create or replace`: Postgres no deja
-- agregar columnas en el medio de una vista existente, y las columnas nuevas
-- van al lado de las que acompañan para que el select se lea como los datos
-- de una persona y no como un apilado histórico de parches.
drop view if exists public.v_clientes_semaforo;

create view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       c.dni,
       c.email,
       c.telefono,
       c.localidad,
       c.provincia,
       b.denominacion,
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
       b.cheques,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                        as consulta_vencida,
       -- Consultado y sin una sola entidad informando: no hay nada en contra.
       (b.consultado_at is not null
        and coalesce(b.cantidad_entidades, 0) = 0)  as sin_deudas_informadas,
       case
         -- Nunca se consultó: no se sabe nada, y decir "apto" sería mentir.
         when b.consultado_at is null
           then 'sin_datos'::semaforo_crediticio
         -- Se consultó y nadie informó deuda.
         when coalesce(b.cantidad_entidades, 0) = 0
           then 'verde'::semaforo_crediticio
         else coalesce(
                public.semaforo_de_situacion(
                  b.situacion_maxima, b.cheques_sin_pagar,
                  b.tiene_cheques_rechazados, b.tiene_proceso_judicial,
                  b.dias_atraso_max),
                'sin_datos'::semaforo_crediticio)
       end                                          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;

-- `create or replace view` conserva los permisos, pero no el security_invoker
-- de una vista recreada con columnas nuevas en algunas versiones. Se vuelve a
-- declarar: sin esto la vista correría con los permisos del dueño y cualquier
-- usuario vería los clientes de todas las agencias.
alter view public.v_clientes_semaforo set (security_invoker = on);

-- Recrear la vista la deja con los permisos de una tabla nueva, y ahi PUBLIC
-- (o sea tambien anon) puede leerla. El RLS de clientes la frenaria igual,
-- pero una vista legible sin sesion no deberia existir en primer lugar.
revoke all on public.v_clientes_semaforo from anon;
grant select on public.v_clientes_semaforo to authenticated;


-- >>>>>>>>>>>>>>>>>>>>  0014_alta_interesados_informes.sql  <<<<<<<<<<<<<<<<<<<<

-- Alta atómica e idempotente. La persona existente se conserva sin sobrescribirla.
alter table public.oportunidades add column if not exists solicitud_alta text;
create unique index if not exists idx_oportunidad_solicitud
  on public.oportunidades(agencia_id, solicitud_alta) where solicitud_alta is not null;

create or replace function public.crear_interesado(p_agencia uuid, p_solicitud text, p_datos jsonb)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_cliente uuid;
  v_oportunidad uuid;
  v_vehiculo uuid := nullif(p_datos->>'vehiculo_id', '')::uuid;
  v_cuit text := p_datos->>'cuit';
  v_suma integer := 0;
  v_pesos integer[] := array[5,4,3,2,7,6,5,4,3,2];
  v_verificador integer;
begin
  if auth.uid() is null or not public.puede_editar(p_agencia) then
    raise exception 'No tenés permiso para cargar interesados en esta agencia.';
  end if;
  for n in 1..10 loop
    v_suma := v_suma + substring(v_cuit,n,1)::integer * v_pesos[n];
  end loop;
  v_verificador := case v_suma % 11 when 0 then 0 when 1 then 9 else 11 - v_suma % 11 end;
  if v_verificador <> substring(v_cuit,11,1)::integer then
    raise exception 'El CUIT/CUIL no tiene un dígito verificador válido.';
  end if;
  if length(trim(coalesce(p_datos->>'nombre',''))) < 2
     or v_cuit is null or v_cuit !~ '^[0-9]{11}$'
     or length(coalesce(p_solicitud,'')) not between 10 and 120 then
    raise exception 'Revisá el nombre, el CUIT/CUIL y la solicitud.';
  end if;
  if (p_datos->>'presupuesto_max')::numeric <= 0 then
    raise exception 'El presupuesto debe ser mayor a cero.';
  end if;
  -- Serializa reintentos y dos vendedores cargando el mismo CUIT.
  perform pg_advisory_xact_lock(hashtextextended(p_agencia::text || v_cuit, 0));
  select id, cliente_id into v_oportunidad, v_cliente from public.oportunidades
    where agencia_id = p_agencia and solicitud_alta = p_solicitud;
  if found then return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente); end if;
  if v_vehiculo is not null and not exists (
    select 1 from public.vehiculos where id = v_vehiculo and agencia_id = p_agencia
      and deleted_at is null and estado <> 'vendido'
  ) then raise exception 'La unidad no está disponible en esta agencia.'; end if;
  select id into v_cliente from public.clientes
    where agencia_id = p_agencia and cuit = v_cuit and deleted_at is null;
  if v_cliente is null then
    insert into public.clientes(agencia_id, nombre, cuit, telefono, email, localidad, acepta_marketing, created_by)
    values (p_agencia, trim(p_datos->>'nombre'), v_cuit, nullif(p_datos->>'telefono',''),
      nullif(p_datos->>'email',''), nullif(p_datos->>'localidad',''), false, auth.uid())
    returning id into v_cliente;
  end if;
  insert into public.oportunidades(agencia_id, cliente_id, vehiculo_id, presupuesto_max,
    necesita_financiacion, notas, created_by, solicitud_alta)
  values (p_agencia, v_cliente, v_vehiculo, (p_datos->>'presupuesto_max')::numeric,
    coalesce((p_datos->>'necesita_financiacion')::boolean,false), nullif(p_datos->>'notas',''),
    auth.uid(), p_solicitud) returning id into v_oportunidad;
  return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente);
end $$;
revoke all on function public.crear_interesado(uuid,text,jsonb) from public, anon;
grant execute on function public.crear_interesado(uuid,text,jsonb) to authenticated;

-- Informes privados: {agencia}/{cliente}/{oportunidad}/{consulta}.pdf.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('informes','informes',false,10485760,array['application/pdf'])
on conflict (id) do nothing;

create or replace function public.puede_acceder_informe(p_ruta text, p_editar boolean default false)
returns boolean language sql stable security invoker set search_path = public
as $$
  select exists (
    select 1 from public.oportunidades o join public.clientes c on c.id = o.cliente_id
    where o.agencia_id::text = split_part(p_ruta,'/',1)
      and c.id::text = split_part(p_ruta,'/',2)
      and o.id::text = split_part(p_ruta,'/',3)
      and c.agencia_id = o.agencia_id and c.deleted_at is null
      and case when p_editar then public.puede_editar(o.agencia_id)
        else public.puede_ver_agencia(o.agencia_id) end
  );
$$;
revoke all on function public.puede_acceder_informe(text,boolean) from public, anon;
grant execute on function public.puede_acceder_informe(text,boolean) to authenticated;
drop policy if exists informes_ver on storage.objects;
create policy informes_ver on storage.objects for select to authenticated
  using (bucket_id = 'informes' and public.puede_acceder_informe(name));
drop policy if exists informes_subir on storage.objects;
create policy informes_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'informes' and public.puede_acceder_informe(name,true));
drop policy if exists informes_actualizar on storage.objects;
create policy informes_actualizar on storage.objects for update to authenticated
  using (bucket_id = 'informes' and public.puede_acceder_informe(name,true))
  with check (bucket_id = 'informes' and public.puede_acceder_informe(name,true));


-- >>>>>>>>>>>>>>>>>>>>  0015_bcra_evaluacion_responsable.sql  <<<<<<<<<<<<<<<<<<<<

-- La ausencia de información no acredita solvencia. Las alertas tienen prioridad.
create or replace function public.semaforo_de_situacion(
 p_situacion smallint, p_cheques_sin_pagar smallint default 0,
 p_tiene_cheques boolean default false, p_proceso_judicial boolean default false,
 p_dias_atraso smallint default 0)
returns semaforo_crediticio language sql immutable set search_path = public as $$
 select case
   when p_situacion >= 4 or coalesce(p_cheques_sin_pagar,0) > 0
     or coalesce(p_proceso_judicial,false) then 'rojo'::semaforo_crediticio
   when p_situacion in (2,3) or coalesce(p_tiene_cheques,false)
     or coalesce(p_dias_atraso,0) > 30 then 'amarillo'::semaforo_crediticio
   when p_situacion = 1 then 'verde'::semaforo_crediticio
   else 'sin_datos'::semaforo_crediticio end;
$$;
create or replace view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       c.dni,
       c.email,
       c.telefono,
       c.localidad,
       c.provincia,
       b.denominacion,
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
       b.cheques,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                        as consulta_vencida,
       -- Consultado y sin una sola entidad informando: no hay nada en contra.
       (b.consultado_at is not null
        and coalesce(b.cantidad_entidades, 0) = 0)  as sin_deudas_informadas,
       case when b.consultado_at is null or b.expira_at < now()
         then 'sin_datos'::semaforo_crediticio
         else public.semaforo_de_situacion(b.situacion_maxima, b.cheques_sin_pagar,
           b.tiene_cheques_rechazados, b.tiene_proceso_judicial, b.dias_atraso_max)
       end                                          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.cuit = c.cuit and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;


-- >>>>>>>>>>>>>>>>>>>>  0016_eliminar_interesado.sql  <<<<<<<<<<<<<<<<<<<<

-- Borra una ficha de interés sin dejar datos personales aislados.
-- Un vendedor con permiso de edición puede hacerlo; si el cliente aparece en
-- otra oportunidad, su ficha y su historial BCRA se conservan.
create or replace function public.eliminar_interesado(p_oportunidad uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agencia uuid;
  v_cliente uuid;
  v_cliente_eliminado boolean := false;
begin
  select agencia_id, cliente_id
    into v_agencia, v_cliente
    from public.oportunidades
   where id = p_oportunidad
   for update;

  if v_agencia is null then
    raise exception 'El interesado ya no existe.';
  end if;
  if auth.uid() is null or not public.puede_editar(v_agencia) then
    raise exception 'No tenés permiso para borrar interesados en esta agencia.';
  end if;

  -- Bloquea la ficha para que dos borrados simultáneos no tomen decisiones
  -- distintas sobre el último interés de la misma persona.
  perform 1 from public.clientes where id = v_cliente for update;
  delete from public.oportunidades where id = p_oportunidad;

  if not exists (
    select 1 from public.oportunidades where cliente_id = v_cliente
  ) then
    delete from public.clientes where id = v_cliente and agencia_id = v_agencia;
    v_cliente_eliminado := found;
  end if;

  return v_cliente_eliminado;
end;
$$;

revoke all on function public.eliminar_interesado(uuid) from public, anon;
grant execute on function public.eliminar_interesado(uuid) to authenticated;

-- Ruta: {agencia}/{cliente}/{oportunidad}/{archivo}.pdf. Se borra antes que
-- la fila porque puede_acceder_informe comprueba que la oportunidad exista.
drop policy if exists informes_borrar on storage.objects;
create policy informes_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'informes' and public.puede_acceder_informe(name, true));


-- >>>>>>>>>>>>>>>>>>>>  0017_bcra_historial.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0017: el semáforo mira los últimos 24 meses, no solo hoy
--
--  Checklist del cliente, punto 3.1 (crítico): una persona que en la web
--  del BCRA figura con deudas salía en la app como "sin deudas informadas".
--
--  La causa: el BCRA tiene tres consultas y la app usaba dos.
--
--    /Deudas/{cuit}              solo el último período informado
--    /Deudas/Historicas/{cuit}   los últimos 24 meses          <- faltaba
--    /Deudas/ChequesRechazados   cheques
--
--  La persona del reclamo estuvo en situación 5 (irrecuperable) de agosto a
--  diciembre de 2024 y en situación 4 hasta marzo de 2025. Desde abril de
--  2025 figura sin deuda, así que /Deudas contesta "no se encontraron
--  datos" y la app lo leía como limpio. La web oficial muestra los 24 meses,
--  y ahí se ve todo.
--
--  Para decidir si financiar, eso importa tanto como el presente: alguien
--  que fue irrecuperable hace año y medio no es alguien sin historial.
--
--  Criterio nuevo, aplicado sobre el criterio anterior (0015), que no cambia:
--
--    ROJO      situación 4 o peor en los últimos 12 meses, aunque hoy esté
--              al día.
--    AMARILLO  situación 3 o peor en los últimos 24 meses.
--    VERDE     también si hoy no tiene deuda pero tiene historial y en los
--              24 meses nunca pasó de situación 2: pagó y cerró.
--
--  Las ventanas se cuentan desde el último período que informó el BCRA, no
--  desde hoy: el BCRA publica con unos dos meses de atraso, y contar desde
--  hoy acortaría la ventana sin que nadie lo note.
--
--  Esta lógica está replicada en Dart (ConsultaBcra.semaforo) y las dos
--  corren los mismos casos desde tests/casos_semaforo.json.
-- =====================================================================

alter table public.bcra_consultas
  add column if not exists situacion_max_12m smallint,
  add column if not exists situacion_max_24m smallint,
  -- Último mes con situación 2 o peor. Es lo que permite decir "al día
  -- desde abril de 2025" en vez de solo "tuvo problemas".
  add column if not exists ultimo_periodo_irregular text,
  -- Un renglón por mes: [{periodo: "202607", situacion: 0}, ...], del más
  -- nuevo al más viejo. 0 es "sin deuda ese mes". Alcanza para dibujar la
  -- línea de tiempo sin volver a abrir el payload crudo.
  add column if not exists historico jsonb,
  add column if not exists payload_historico jsonb;

comment on column public.bcra_consultas.situacion_max_24m is
  'Peor situación (1-6) en los 24 meses de /Deudas/Historicas. Null si no hubo deuda en ese lapso.';

-- ---------------------------------------------------------------------
-- El semáforo con historial.
--
-- Nombre nuevo en vez de sumarle parámetros a semaforo_de_situacion: con
-- parámetros opcionales, Postgres vería dos funciones que aceptan la misma
-- llamada de cinco argumentos y tiraría "function is not unique".
-- ---------------------------------------------------------------------
create or replace function public.semaforo_con_historial(
  p_situacion         smallint,
  p_cheques_sin_pagar smallint default 0,
  p_tiene_cheques     boolean  default false,
  p_proceso_judicial  boolean  default false,
  p_dias_atraso       smallint default 0,
  p_max_12m           smallint default null,
  p_max_24m           smallint default null)
returns semaforo_crediticio
language sql immutable
set search_path = public
as $$
  select case
    when coalesce(p_situacion, 0) >= 4
      or coalesce(p_cheques_sin_pagar, 0) > 0
      or coalesce(p_proceso_judicial, false)
      or coalesce(p_max_12m, 0) >= 4                  then 'rojo'::semaforo_crediticio
    when p_situacion in (2, 3)
      or coalesce(p_tiene_cheques, false)
      or coalesce(p_dias_atraso, 0) > 30
      or coalesce(p_max_24m, 0) >= 3                  then 'amarillo'::semaforo_crediticio
    when p_situacion = 1
      or (p_situacion is null and p_max_24m in (1, 2)) then 'verde'::semaforo_crediticio
    else 'sin_datos'::semaforo_crediticio
  end;
$$;

revoke all on function public.semaforo_con_historial(
  smallint, smallint, boolean, boolean, smallint, smallint, smallint) from public, anon;
grant execute on function public.semaforo_con_historial(
  smallint, smallint, boolean, boolean, smallint, smallint, smallint) to authenticated;

-- ---------------------------------------------------------------------
-- La vista, ahora con el historial.
-- ---------------------------------------------------------------------
drop view if exists public.v_clientes_semaforo;

create view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       c.dni,
       c.email,
       c.telefono,
       c.localidad,
       c.provincia,
       b.denominacion,
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
       b.cheques,
       b.situacion_max_12m,
       b.situacion_max_24m,
       b.ultimo_periodo_irregular,
       b.historico,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                         as consulta_vencida,
       -- Sin deudas de verdad: nada hoy Y nada en 24 meses. Antes bastaba
       -- con que hoy no hubiera nada, y eso es justo lo que falló.
       (b.consultado_at is not null
        and coalesce(b.cantidad_entidades, 0) = 0
        and coalesce(jsonb_array_length(b.historico), 0) = 0) as sin_deudas_informadas,
       case when b.consultado_at is null or b.expira_at < now()
         then 'sin_datos'::semaforo_crediticio
         else public.semaforo_con_historial(
           b.situacion_maxima, b.cheques_sin_pagar, b.tiene_cheques_rechazados,
           b.tiene_proceso_judicial, b.dias_atraso_max,
           b.situacion_max_12m, b.situacion_max_24m)
       end                                           as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.cuit = c.cuit and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;

alter view public.v_clientes_semaforo set (security_invoker = on);
revoke all on public.v_clientes_semaforo from anon;
grant select on public.v_clientes_semaforo to authenticated;

-- ---------------------------------------------------------------------
-- Las consultas hechas antes de este cambio no traen historial, y alguna
-- puede estar diciendo "sin deudas" de alguien que tuvo. Se dan por
-- vencidas: la app las muestra como "sin consultar" y la próxima consulta
-- trae los 24 meses. Mejor pedir una consulta de más que dejar en pie un
-- resultado que ya sabemos que puede estar mal.
-- ---------------------------------------------------------------------
update public.bcra_consultas
   set expira_at = now()
 where historico is null
   and expira_at > now();


-- >>>>>>>>>>>>>>>>>>>>  0018_ipc_automatico.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0018: la serie del IPC se actualiza sola contra el INDEC
--
--  Checklist del cliente, punto 1.1 (crítico): "Ganancia real (IPC)" salía
--  idéntica a la nominal.
--
--  En la prueba del cliente eso tenía una explicación puntual: los autos
--  estaban cargados con fecha de INGRESO de hoy, y el ajuste se cuenta desde
--  el ingreso (así lo hacía el sistema original, y así lo pide el propio
--  checklist: "desde la fecha en que el auto entró al stock"). De hoy a hoy
--  la inflación es cero.
--
--  Pero atrás de eso había un problema de verdad, que iba a aparecer igual:
--
--    - La serie arrancaba en julio de 2025. Un auto que entró antes recibía
--      el índice de julio 2025, o sea que se le perdía toda la inflación
--      anterior.
--    - Terminaba en agosto de 2026 y nadie la actualizaba. Cualquier auto que
--      entrara de ahí en adelante iba a mostrar inflación cero para siempre.
--
--  Esta migración conecta la base a la serie oficial del INDEC (IPC nivel
--  general nacional, base diciembre 2016 = 100, publicada gratis en
--  datos.gob.ar) y la actualiza todos los días. El INDEC publica una vez por
--  mes, cerca del día 13; el resto de los días la sincronización no cambia
--  nada.
--
--  EL MES EN CURSO SE ESTIMA. El INDEC publica con un mes y medio de atraso:
--  el 19 de septiembre, lo último publicado es agosto. Sin estimar, un auto
--  que entró en agosto mostraría inflación cero hasta mediados de octubre.
--  Los meses que faltan hasta hoy se completan con la última variación
--  publicada y quedan marcados es_proyeccion = true; cuando el INDEC publica
--  el dato real, la sincronización lo pisa.
--
--  No va como datos dentro de la migración, a propósito: la serie cambia
--  todos los meses, y además el test de paridad con el sistema original usa
--  la serie que tenía ese sistema. Esto es el mecanismo; los datos los trae
--  la sincronización.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Más decimales para la variación.
--
-- Con numeric(8,5) cada mes se redondeaba a 5 decimales. Parece poco, pero
-- si alguien vuelve a correr recalcular_ipc() (que encadena variaciones) el
-- error se acumula mes a mes durante diez años de serie.
-- ---------------------------------------------------------------------
alter table public.ipc_serie alter column variacion type numeric(14,10);

-- ---------------------------------------------------------------------
-- 2. Cargar la serie a partir de los datos del INDEC.
--
-- Separada de la descarga para poder probarla sin red (tests/ipc.mjs) y
-- para poder cargarla a mano si datos.gob.ar alguna vez se cae.
--
-- p_datos: [["2016-12-01", 100.0], ["2017-01-01", 101.5859], ...]
--          tal cual el campo "data" de la API de series de datos.gob.ar.
-- p_hoy:   hasta qué mes estimar. Es parámetro solo para poder probarlo.
--
-- REEMPLAZA LA SERIE ENTERA, y guarda el nivel oficial del índice tal cual,
-- sin reconstruirlo encadenando variaciones. Las dos cosas vienen de un
-- error real que agarró el test: pisando solo los meses que venían, las
-- filas viejas de la semilla (con base 100 en julio de 2025) quedaban
-- encadenadas en el medio de la serie oficial (base 100 en diciembre de
-- 2016), mezclando dos bases. El índice de agosto de 2026 daba 13.768
-- contra 12.277 del INDEC: un 12% de error en todo ajuste por inflación.
--
-- Es una sola transacción: si algo falla a mitad de camino, la serie queda
-- como estaba.
-- ---------------------------------------------------------------------
create or replace function public.cargar_ipc(p_datos jsonb, p_hoy date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_real     int;
  v_ultimo   date;
  v_nivel    numeric;
  v_var      numeric;
  v_mes      date;
  v_hasta    date := date_trunc('month', p_hoy)::date;
  v_proyect  int := 0;
begin
  -- Primero se valida, después se borra: una respuesta rota de datos.gob.ar
  -- no puede dejar la base sin serie.
  if p_datos is null or jsonb_typeof(p_datos) <> 'array' or jsonb_array_length(p_datos) < 2 then
    raise exception 'La serie del IPC vino vacía o con otro formato.';
  end if;

  delete from public.ipc_serie;

  -- Los meses publicados, con el nivel oficial como índice.
  with filas as (
    select (e->>0)::date as mes, (e->>1)::numeric as nivel
      from jsonb_array_elements(p_datos) e
     where e->>1 is not null
  )
  insert into public.ipc_serie (mes, indice, variacion, fuente, url, es_proyeccion, updated_at)
  select mes, nivel,
         nivel / nullif(lag(nivel) over (order by mes), 0) - 1,
         'INDEC, IPC nivel general nacional (base dic 2016), vía datos.gob.ar',
         'https://datos.gob.ar/series/api/series/?ids=148.3_INIVELNAL_DICI_M_26',
         false, now()
    from filas;

  get diagnostics v_real = row_count;

  select mes, indice, variacion into v_ultimo, v_nivel, v_var
    from public.ipc_serie order by mes desc limit 1;

  -- Los meses que el INDEC todavía no publicó, hasta el mes de hoy, con la
  -- última variación publicada.
  v_mes := (v_ultimo + interval '1 month')::date;
  while v_mes <= v_hasta loop
    v_nivel := v_nivel * (1 + v_var);
    insert into public.ipc_serie (mes, indice, variacion, fuente, url, es_proyeccion)
    values (v_mes, v_nivel, v_var,
            'Estimado con la última variación publicada por el INDEC ('
              || to_char(v_ultimo, 'MM/YYYY') || '). Se reemplaza al publicarse el dato real.',
            null, true);
    v_proyect := v_proyect + 1;
    v_mes := (v_mes + interval '1 month')::date;
  end loop;

  return jsonb_build_object(
    'meses_publicados', v_real,
    'ultimo_publicado', to_char(v_ultimo, 'YYYY-MM'),
    'meses_estimados',  v_proyect,
    'hasta',            to_char(v_hasta, 'YYYY-MM')
  );
end $$;

revoke all on function public.cargar_ipc(jsonb, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Bajar la serie del INDEC y cargarla.
--
-- Usa la extensión http, que Supabase tiene disponible. En el Postgres de
-- los tests (PGlite) no existe: por eso todo lo que la necesita va adentro
-- de un bloque que se saltea si la extensión no está.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'http') then
    create extension if not exists http with schema extensions;

    create or replace function public.sincronizar_ipc()
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, extensions
    as $fn$
    declare
      r      extensions.http_response;
      cuerpo jsonb;
    begin
      -- datos.gob.ar a veces tarda: 20 segundos antes de rendirse.
      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
      select * into r from extensions.http_get(
        'https://apis.datos.gob.ar/series/api/series/'
        || '?ids=148.3_INIVELNAL_DICI_M_26&format=json&limit=5000');

      if r.status <> 200 then
        raise exception 'datos.gob.ar respondió %', r.status;
      end if;

      cuerpo := r.content::jsonb;
      return public.cargar_ipc(cuerpo->'data');
    end $fn$;

    revoke all on function public.sincronizar_ipc() from public, anon, authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Que corra sola, todos los días a las 11:00 UTC (8 de la mañana en
--    Argentina). El INDEC publica una vez por mes; los demás días no cambia
--    nada, pero así nadie tiene que acordarse de nada.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_proc where proname = 'sincronizar_ipc') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'sincronizar-ipc';
    perform cron.schedule('sincronizar-ipc', '0 11 * * *', 'select public.sincronizar_ipc()');
  end if;
end $$;


-- >>>>>>>>>>>>>>>>>>>>  0019_consentimiento_marketing.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0019: el alta de interesados respeta el consentimiento
--
--  Checklist del cliente, punto 4.1: al armar una campaña decía "lo van a
--  recibir 0 personas" aunque había un interesado con email.
--
--  La causa: crear_interesado (0014) guardaba acepta_marketing = false
--  SIEMPRE, y ninguna pantalla dejaba cambiarlo. Todo interesado cargado
--  desde la app quedaba afuera de las campañas para siempre.
--
--  No se arregla poniendo true por defecto. Mandarle mails a alguien que no
--  lo aceptó es spam, quema la reputación del dominio y en Argentina choca
--  con la ley de datos personales. Lo correcto es preguntarlo: el formulario
--  ahora tiene el interruptor, y esta función guarda lo que se marcó. Si no
--  hay email, no hay consentimiento que valga: queda en false.
--
--  Única diferencia con la 0014: la línea del acepta_marketing del insert.
-- =====================================================================

create or replace function public.crear_interesado(p_agencia uuid, p_solicitud text, p_datos jsonb)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_cliente uuid;
  v_oportunidad uuid;
  v_vehiculo uuid := nullif(p_datos->>'vehiculo_id', '')::uuid;
  v_cuit text := p_datos->>'cuit';
  v_suma integer := 0;
  v_pesos integer[] := array[5,4,3,2,7,6,5,4,3,2];
  v_verificador integer;
begin
  if auth.uid() is null or not public.puede_editar(p_agencia) then
    raise exception 'No tenés permiso para cargar interesados en esta agencia.';
  end if;
  for n in 1..10 loop
    v_suma := v_suma + substring(v_cuit,n,1)::integer * v_pesos[n];
  end loop;
  v_verificador := case v_suma % 11 when 0 then 0 when 1 then 9 else 11 - v_suma % 11 end;
  if v_verificador <> substring(v_cuit,11,1)::integer then
    raise exception 'El CUIT/CUIL no tiene un dígito verificador válido.';
  end if;
  if length(trim(coalesce(p_datos->>'nombre',''))) < 2
     or v_cuit is null or v_cuit !~ '^[0-9]{11}$'
     or length(coalesce(p_solicitud,'')) not between 10 and 120 then
    raise exception 'Revisá el nombre, el CUIT/CUIL y la solicitud.';
  end if;
  if (p_datos->>'presupuesto_max')::numeric <= 0 then
    raise exception 'El presupuesto debe ser mayor a cero.';
  end if;
  -- Serializa reintentos y dos vendedores cargando el mismo CUIT.
  perform pg_advisory_xact_lock(hashtextextended(p_agencia::text || v_cuit, 0));
  select id, cliente_id into v_oportunidad, v_cliente from public.oportunidades
    where agencia_id = p_agencia and solicitud_alta = p_solicitud;
  if found then return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente); end if;
  if v_vehiculo is not null and not exists (
    select 1 from public.vehiculos where id = v_vehiculo and agencia_id = p_agencia
      and deleted_at is null and estado <> 'vendido'
  ) then raise exception 'La unidad no está disponible en esta agencia.'; end if;
  select id into v_cliente from public.clientes
    where agencia_id = p_agencia and cuit = v_cuit and deleted_at is null;
  if v_cliente is null then
    insert into public.clientes(agencia_id, nombre, cuit, telefono, email, localidad, acepta_marketing, created_by)
    values (p_agencia, trim(p_datos->>'nombre'), v_cuit, nullif(p_datos->>'telefono',''),
      nullif(p_datos->>'email',''), nullif(p_datos->>'localidad',''),
      -- Consentimiento para mails: solo si lo marcaron Y hay a donde mandar.
      coalesce((p_datos->>'acepta_marketing')::boolean, false)
        and nullif(p_datos->>'email','') is not null,
      auth.uid())
    returning id into v_cliente;
  end if;
  insert into public.oportunidades(agencia_id, cliente_id, vehiculo_id, presupuesto_max,
    necesita_financiacion, notas, created_by, solicitud_alta)
  values (p_agencia, v_cliente, v_vehiculo, (p_datos->>'presupuesto_max')::numeric,
    coalesce((p_datos->>'necesita_financiacion')::boolean,false), nullif(p_datos->>'notas',''),
    auth.uid(), p_solicitud) returning id into v_oportunidad;
  return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente);
end $$;
revoke all on function public.crear_interesado(uuid,text,jsonb) from public, anon;
grant execute on function public.crear_interesado(uuid,text,jsonb) to authenticated;


-- >>>>>>>>>>>>>>>>>>>>  0020_ganancia_real_dolar.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0020: la ganancia real se ajusta por DÓLAR, no por IPC,
--                     y se ancla en la FECHA DE COMPRA
--
--  Checklist del cliente, tanda 2, punto 2.1 (crítico).
--
--  Lo que pide el cliente, con sus palabras de fondo: la plata que puso en
--  un auto hay que medirla en dólares del día en que la puso, y compararla
--  con lo que vale hoy (o el día que lo vendió). Es como razona un
--  concesionario: el auto es un activo dolarizado.
--
--    compra_usd   = precio_compra / dólar(fecha_compra)
--    gasto_usd[i] = importe_i     / dólar(fecha del gasto i)
--    costo_usd    = compra_usd + Σ gasto_usd
--    costo_hoy    = costo_usd × dólar(referencia)
--    ganancia     = precio − costo_hoy
--
--  Dólar = oficial, valor VENTA, cotización diaria (argentinadatos.com, que
--  publica la serie del BCRA/BNA desde 2011).
--
--  Dos cambios respecto de la 0008, a propósito:
--
--  1. FECHA DE COMPRA, no de ingreso. La compra es cuándo salió la plata.
--     La fecha de ingreso sigue mandando para los días en stock y las
--     alertas de rotación: eso no cambia.
--
--  2. Para una unidad VENDIDA la referencia es el dólar del día de la
--     venta, y el precio es el precio final de venta. Si no, la ganancia de
--     un auto vendido hace un año seguiría moviéndose con el dólar de hoy,
--     y la ganancia se calcularía contra un precio publicado que no fue el
--     que se cobró. Los gastos de cierre se hacen el día de la venta: a
--     dólar de ese día valen lo mismo, así que entran nominales.
--
--  Ejemplo del cliente (Corolla), que reproduce tests/dolar.mjs:
--    compra $8.500.000 el 10/05/2024 (dólar 901,5)  → USD 9.428,73
--    gastos $600.000   el 20/01/2025 (dólar 1.066)  → USD   562,85
--    vendido $14.500.000 el 18/09/2026 (dólar 1.535)
--    costo a valor de hoy = 9.991,58 × 1.535 = $15.337.078
--    ganancia real = −$837.078 · margen real −5,8 %
--
--  Los nombres de las columnas de la vista NO cambian (costo_total_hoy,
--  ganancia_real_ipc, margen_real_ipc): las versiones de la app que ya
--  están instaladas las leen por nombre, y cambiarles el nombre las
--  rompería hasta que se actualicen. Cambia lo que calculan; la app nueva
--  las muestra como "(USD)".
--
--  Si falta la cotización de alguna fecha (base recién creada, fechas
--  anteriores a 2011), esa parte del costo se toma nominal: mejor no
--  ajustar que inventar un ajuste.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Dólar oficial vigente en una fecha: el último día hábil anterior o
--    igual. Los fines de semana y feriados no hay cotización.
-- ---------------------------------------------------------------------
create or replace function public.dolar_oficial_en(p_fecha date)
returns numeric
language sql
stable
as $$
  select venta from public.cotizaciones
   where tipo = 'oficial' and venta > 0 and fecha <= p_fecha
   order by fecha desc
   limit 1;
$$;

grant execute on function public.dolar_oficial_en(date) to authenticated;

create index if not exists idx_cotizaciones_tipo_fecha
  on public.cotizaciones (tipo, fecha desc);

-- ---------------------------------------------------------------------
-- 2. Cargar cotizaciones a partir de la respuesta de argentinadatos.
--
-- p_datos: [{"casa":"oficial","compra":..,"venta":..,"fecha":"2024-05-10"}, ...]
--          tal cual lo devuelve /v1/cotizaciones/dolares/{casa}.
--
-- Separada de la descarga para poder probarla sin red. A diferencia del
-- IPC, acá no se reemplaza la serie: una cotización de un día pasado no
-- cambia, así que se hace upsert y listo.
-- ---------------------------------------------------------------------
create or replace function public.cargar_cotizaciones(
  p_datos jsonb,
  p_tipo  tipo_cotizacion default 'oficial'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_filas int;
begin
  if p_datos is null or jsonb_typeof(p_datos) <> 'array' or jsonb_array_length(p_datos) = 0 then
    raise exception 'La serie del dólar vino vacía o con otro formato.';
  end if;

  insert into public.cotizaciones (fecha, tipo, compra, venta, fuente)
  select (e->>'fecha')::date, p_tipo,
         nullif(e->>'compra', '')::numeric, nullif(e->>'venta', '')::numeric,
         'argentinadatos.com'
    from jsonb_array_elements(p_datos) e
   where e->>'fecha' is not null and nullif(e->>'venta', '')::numeric > 0
  on conflict (fecha, tipo) do update
     set compra = excluded.compra, venta = excluded.venta, fuente = excluded.fuente
   where cotizaciones.venta is distinct from excluded.venta
      or cotizaciones.compra is distinct from excluded.compra;

  get diagnostics v_filas = row_count;

  return jsonb_build_object(
    'tipo', p_tipo,
    'recibidas', jsonb_array_length(p_datos),
    'nuevas_o_cambiadas', v_filas,
    'ultima', (select max(fecha) from public.cotizaciones where tipo = p_tipo)
  );
end $$;

revoke all on function public.cargar_cotizaciones(jsonb, tipo_cotizacion) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Bajar las series y cargarlas. Una sola llamada trae la serie entera
--    de cada tipo de dólar, así que no hace falta llevar la cuenta de qué
--    días faltan. Solo en Supabase (PGlite no tiene la extensión http).
--
--    Si un tipo falla, los demás se cargan igual: el que importa para la
--    ganancia es el oficial, y un problema con el blue no lo puede frenar.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'http') then
    create extension if not exists http with schema extensions;

    create or replace function public.sincronizar_dolar()
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, extensions
    as $fn$
    declare
      -- tipo en la base → nombre de la "casa" en argentinadatos
      casas     constant text[][] := array[
        ['oficial','oficial'], ['blue','blue'], ['mayorista','mayorista'],
        ['mep','bolsa'], ['ccl','contadoconliqui'], ['tarjeta','tarjeta']];
      i         int;
      r         extensions.http_response;
      resultado jsonb := '[]'::jsonb;
    begin
      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '30');
      for i in 1 .. array_length(casas, 1) loop
        begin
          select * into r from extensions.http_get(
            'https://api.argentinadatos.com/v1/cotizaciones/dolares/' || casas[i][2]);
          if r.status <> 200 then
            raise exception 'argentinadatos respondió %', r.status;
          end if;
          resultado := resultado || public.cargar_cotizaciones(
            r.content::jsonb, casas[i][1]::tipo_cotizacion);
        exception when others then
          resultado := resultado || jsonb_build_object('tipo', casas[i][1], 'error', sqlerrm);
        end;
      end loop;
      return resultado;
    end $fn$;

    revoke all on function public.sincronizar_dolar() from public, anon, authenticated;
  end if;
end $$;

-- Una vez por día, a las 18:30 de Argentina (21:30 UTC), cuando el BNA ya
-- cerró la cotización del día.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_proc where proname = 'sincronizar_dolar') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'sincronizar-dolar';
    perform cron.schedule('sincronizar-dolar', '30 21 * * *', 'select public.sincronizar_dolar()');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. El motor. Mismas columnas y en el mismo orden que antes (Postgres lo
--    exige para reemplazar una vista con otras que dependen de ella); las
--    nuevas van al final.
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
    coalesce(vg.cantidad_gastos, 0)  as cantidad_gastos,

    coalesce(vpa.precio_publicado, v.precio_objetivo) as precio_actual,
    vpa.fecha_precio,

    -- El IPC queda como dato informativo; ya no entra en la ganancia real.
    public.ipc_indice_hoy()               as indice_hoy,
    public.ipc_indice_en(v.fecha_ingreso) as indice_ingreso,
    coalesce(public.cotizacion_vigente(cfg.tipo_cambio_preferido), 0) as tipo_cambio,

    dc.dolar as dolar_compra,
    dr.dolar as dolar_referencia,
    -- Cada gasto llevado a dólares de SU fecha y traído al dólar de la
    -- referencia. Sin cotización para esa fecha, entra nominal.
    coalesce(ga.gastos_referencia, 0) as gastos_vehiculo_ajustados
  from public.vehiculos v
  join public.agencia_config cfg          on cfg.agencia_id = v.agencia_id
  left join public.ventas vt              on vt.vehiculo_id = v.id
  left join public.v_vehiculo_gastos vg   on vg.vehiculo_id = v.id
  left join public.v_vehiculo_precio_actual vpa on vpa.vehiculo_id = v.id
  cross join lateral (select public.dolar_oficial_en(v.fecha_compra) as dolar) dc
  cross join lateral (select public.dolar_oficial_en(coalesce(vt.fecha_venta, current_date)) as dolar) dr
  left join lateral (
    select sum(g.importe * coalesce(dr.dolar / nullif(public.dolar_oficial_en(g.fecha), 0), 1))
             as gastos_referencia
      from public.gastos g
     where g.vehiculo_id = v.id
  ) ga on true
  where v.deleted_at is null
),
calc as (
  select
    b.*,
    (b.venta_id is not null)                                 as vendido,
    (b.gastos_vehiculo + b.gastos_finales)                   as gastos_acum,
    (b.precio_compra + b.gastos_vehiculo + b.gastos_finales) as costo_total,
    (coalesce(b.fecha_venta, current_date) - b.fecha_ingreso) as dias_en_stock,
    (b.precio_compra * coalesce(b.dolar_referencia / nullif(b.dolar_compra, 0), 1)
       + b.gastos_vehiculo_ajustados
       + b.gastos_finales)                                   as costo_total_hoy,
    -- Vendido: lo que se cobró. En stock: lo que se pide hoy.
    case when b.venta_id is not null then b.precio_final else
      coalesce(b.precio_actual, 0) end                       as precio_referencia
  from base b
)
select
  c.id, c.agencia_id, c.codigo, c.marca, c.modelo, c.anio, c.version, c.km, c.patente,
  c.fecha_compra, c.fecha_ingreso, c.precio_compra, c.precio_objetivo,
  c.observaciones, c.ref_version_id, c.created_at,
  case when c.vendido then 'vendido'::estado_vehiculo else c.estado end as estado,
  c.vendido,
  c.venta_id, c.fecha_venta, c.precio_final,
  c.cantidad_gastos, c.gastos_acum, c.gastos_finales,
  c.costo_total,
  c.dias_en_stock,
  c.precio_actual,
  c.fecha_precio,
  case when c.vendido then 0::numeric else c.costo_total end as capital_inmovilizado,
  c.precio_actual - c.costo_total as ganancia_estimada,
  (c.precio_objetivo - c.costo_total) / nullif(c.precio_objetivo, 0) as margen_esperado,
  (c.precio_actual - c.costo_total) / nullif(c.precio_actual, 0) as margen_actual,
  case when c.vendido then (c.precio_final - c.costo_total) / nullif(c.precio_final, 0)
       else null::numeric end as margen_real,
  c.costo_total / nullif(1 - c.margen_objetivo, 0) as precio_para_margen_objetivo,
  c.costo_total / nullif(1 - c.margen_minimo, 0)   as precio_para_margen_minimo,
  c.costo_total as precio_equilibrio,
  ceil(c.costo_total / nullif(1 - c.margen_objetivo, 0) / nullif(c.redondeo, 0)) * c.redondeo
    as precio_sugerido,
  c.costo_total / nullif(1 - c.margen_objetivo, 0) / nullif(c.precio_actual, 0) - 1
    as ajuste_necesario,
  c.precio_actual / nullif(c.precio_objetivo, 0) - 1 as var_vs_objetivo,
  c.gastos_acum / nullif(c.precio_compra, 0) as gastos_ratio,
  case when c.dias_en_stock > 0 then c.costo_total / c.dias_en_stock::numeric
       else c.costo_total end as costo_diario,
  c.indice_ingreso,
  c.indice_hoy,
  c.costo_total_hoy,
  -- Nombres históricos: hoy son la ganancia y el margen ajustados por dólar.
  c.precio_referencia - c.costo_total_hoy as ganancia_real_ipc,
  (c.precio_referencia - c.costo_total_hoy) / nullif(c.precio_referencia, 0) as margen_real_ipc,
  c.tipo_cambio,
  -- La ganancia real expresada en dólares, al dólar de la referencia.
  case when coalesce(c.dolar_referencia, c.tipo_cambio) > 0
       then (c.precio_referencia - c.costo_total_hoy) / coalesce(c.dolar_referencia, c.tipo_cambio)
  end as ganancia_real_usd,
  case
    when c.vendido then 'vendido'
    when c.dias_en_stock >= c.dias_rojo     then 'critico'
    when c.dias_en_stock >= c.dias_amarillo then 'atencion'
    when c.dias_en_stock >= c.dias_verde    then 'observar'
    else 'normal'
  end as alerta,
  c.dias_verde, c.dias_amarillo, c.dias_rojo,
  c.margen_minimo, c.margen_objetivo, c.umbral_gastos_altos,
  c.tolerancia_caida_margen, c.tolerancia_desvio_precio,
  rp.precio_ars      as revista_ars,
  rp.precio_usd      as revista_usd,
  rp.actualizado_at  as revista_actualizada_at,
  case when rp.precio_ars > 0 then c.precio_actual / rp.precio_ars - 1 end as var_vs_revista,
  -- Nuevas (0020)
  c.dolar_compra,
  c.dolar_referencia,
  case when c.dolar_referencia > 0 then c.costo_total_hoy / c.dolar_referencia end
    as costo_total_usd,
  c.precio_referencia
from calc c
left join public.ref_precios rp on rp.version_id = c.ref_version_id and rp.anio = c.anio;

alter view public.v_inventario set (security_invoker = on);

-- El dashboard: la ganancia en dólares de cada venta, al dólar de SU día.
create or replace view public.v_dashboard as
select
  agencia_id,
  count(*) filter (where not vendido)                       as unidades_en_stock,
  count(*) filter (where vendido)                           as unidades_vendidas,
  coalesce(sum(capital_inmovilizado), 0)                    as capital_inmovilizado,
  coalesce(sum(gastos_acum) filter (where not vendido), 0)  as gastos_en_stock,
  coalesce(sum(ganancia_estimada) filter (where not vendido), 0) as ganancia_potencial,
  coalesce(sum(precio_final - costo_total) filter (where vendido), 0) as ganancia_realizada,
  coalesce(sum(precio_final - costo_total_hoy) filter (where vendido), 0)
    as ganancia_realizada_ipc,
  coalesce(sum(ganancia_real_usd) filter (where vendido), 0) as ganancia_realizada_usd,
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

alter view public.v_dashboard set (security_invoker = on);


-- >>>>>>>>>>>>>>>>>>>>  0021_bcra_detalle_por_entidad.sql  <<<<<<<<<<<<<<<<<<<<

-- =====================================================================
--  MI AGENCIA — 0021: detalle del BCRA por entidad y por mes
--
--  Checklist del cliente, tanda 2, punto 2.4: el informe tiene que mostrar,
--  para cada banco, financiera o tarjeta y para cada mes de los últimos 24,
--  la situación (1 a 6), el monto adeudado y si hay gestión judicial.
--
--  Desde esta versión la Edge Function bcra-consulta guarda ese detalle en
--  `historico` (cada mes lleva sus `entidades`). Las consultas hechas antes
--  ya tienen la respuesta cruda del BCRA en `payload_historico`: acá se
--  rearma `historico` a partir de ella, con la misma forma que arma
--  historial.ts, para que el informe de esas personas también lo muestre
--  sin volver a consultar.
-- =====================================================================

update public.bcra_consultas c
   set historico = coalesce((
     select jsonb_agg(
              jsonb_build_object(
                'periodo',    p->>'periodo',
                'situacion',  coalesce((
                    select max(coalesce((e->>'situacion')::int, 0))
                      from jsonb_array_elements(coalesce(p->'entidades', '[]'::jsonb)) e), 0),
                'entidades',  coalesce((
                    select jsonb_agg(
                             jsonb_build_object(
                               'entidad',    trim(coalesce(e->>'entidad', 'Sin identificar')),
                               'situacion',  coalesce((e->>'situacion')::int, 0),
                               'monto',      coalesce((e->>'monto')::numeric, 0),
                               'procesoJud', coalesce((e->>'procesoJud')::boolean, false),
                               'enRevision', coalesce((e->>'enRevision')::boolean, false))
                             order by coalesce((e->>'situacion')::int, 0) desc,
                                      coalesce((e->>'monto')::numeric, 0) desc)
                      from jsonb_array_elements(coalesce(p->'entidades', '[]'::jsonb)) e),
                    '[]'::jsonb))
              order by p->>'periodo' desc)
       from jsonb_array_elements(c.payload_historico->'results'->'periodos') p
      where p->>'periodo' ~ '^\d{6}$'
   ), '[]'::jsonb)
 where c.payload_historico is not null
   and jsonb_typeof(c.payload_historico->'results'->'periodos') = 'array';
