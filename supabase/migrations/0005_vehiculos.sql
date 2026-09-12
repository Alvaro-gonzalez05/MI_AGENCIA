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
