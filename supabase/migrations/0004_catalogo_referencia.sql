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
