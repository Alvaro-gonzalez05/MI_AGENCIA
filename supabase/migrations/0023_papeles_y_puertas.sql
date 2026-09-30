-- =====================================================================
--  MI AGENCIA — 0023: los papeles de cada unidad, y dos datos del alta
--
--  El diseño nuevo carga un auto en cuatro pasos: el auto, el precio, los
--  papeles y las fotos. Las fotos ya tenían dónde guardarse
--  (`vehiculo_fotos` + el bucket `vehiculos`, migración 0005/0009); los
--  papeles no.
--
--  Un auto usado no se vende si los papeles no están: el título, la cédula,
--  la VTV, el informe de dominio, las patentes y las multas son lo primero
--  que pregunta el comprador y lo que traba la transferencia. Por eso se
--  guardan por unidad, con su vencimiento y su deuda, y no como una nota
--  suelta en observaciones.
--
--  Es una fila por vehículo (no un historial): lo que importa es el estado
--  de hoy. El historial de quién tocó qué ya lo lleva `updated_at`.
-- =====================================================================

create table if not exists public.vehiculo_papeles (
  vehiculo_id     uuid primary key references public.vehiculos(id) on delete cascade,
  agencia_id      uuid not null references public.agencias(id) on delete cascade,

  -- Lo que se marca con un tilde.
  titulo          boolean not null default false,
  cedula          boolean not null default false,
  informe_dominio boolean not null default false,

  -- La VTV vale hasta una fecha: sin ella el dato no dice nada.
  vtv             boolean not null default false,
  vtv_vence       date,

  -- Deuda: cero es un valor (no hay deuda), null es "no lo miré todavía".
  patentes_deuda  numeric(14,2),
  multas_cantidad integer not null default 0,
  multas_monto    numeric(14,2),

  notas           text,
  actualizado_por uuid references auth.users(id) on delete set null,
  updated_at      timestamptz not null default now(),

  constraint papeles_deuda_no_negativa
    check (patentes_deuda is null or patentes_deuda >= 0),
  constraint papeles_multas_no_negativas
    check (multas_cantidad >= 0 and (multas_monto is null or multas_monto >= 0))
);

create index if not exists vehiculo_papeles_agencia_idx
  on public.vehiculo_papeles (agencia_id);

-- Vencimientos a la vista: lo que la agencia consulta es "qué se me vence".
create index if not exists vehiculo_papeles_vtv_idx
  on public.vehiculo_papeles (vtv_vence)
  where vtv_vence is not null;

alter table public.vehiculo_papeles enable row level security;

drop policy if exists vehiculo_papeles_select on public.vehiculo_papeles;
create policy vehiculo_papeles_select on public.vehiculo_papeles
  for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

drop policy if exists vehiculo_papeles_insert on public.vehiculo_papeles;
create policy vehiculo_papeles_insert on public.vehiculo_papeles
  for insert to authenticated
  with check (public.puede_editar(agencia_id));

drop policy if exists vehiculo_papeles_update on public.vehiculo_papeles;
create policy vehiculo_papeles_update on public.vehiculo_papeles
  for update to authenticated
  using (public.puede_editar(agencia_id))
  with check (public.puede_editar(agencia_id));

drop policy if exists vehiculo_papeles_delete on public.vehiculo_papeles;
create policy vehiculo_papeles_delete on public.vehiculo_papeles
  for delete to authenticated
  using (public.puede_editar(agencia_id));

drop trigger if exists vehiculo_papeles_touch on public.vehiculo_papeles;
create trigger vehiculo_papeles_touch
  before update on public.vehiculo_papeles
  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------------
--  Dos datos que el alta del diseño pide y no estaban
-- ---------------------------------------------------------------------
--  `puertas` sale en la ficha técnica de cualquier publicación, y `origen`
--  contesta de dónde salió la unidad (compra directa, parte de pago o
--  consignación), que cambia cómo se mira la ganancia.
alter table public.vehiculos
  add column if not exists puertas smallint,
  add column if not exists origen  text;

alter table public.vehiculos
  drop constraint if exists vehiculos_puertas_validas;
alter table public.vehiculos
  add constraint vehiculos_puertas_validas
  check (puertas is null or puertas between 2 and 5);

alter table public.vehiculos
  drop constraint if exists vehiculos_origen_valido;
alter table public.vehiculos
  add constraint vehiculos_origen_valido
  check (origen is null or origen in ('compra_directa', 'parte_de_pago', 'consignacion'));

comment on column public.vehiculos.origen is
  'Cómo entró la unidad: compra directa al titular, parte de pago de otra venta, o consignación.';

-- ---------------------------------------------------------------------
--  La vista del inventario devuelve lo nuevo
-- ---------------------------------------------------------------------
create or replace view public.v_vehiculo_papeles as
select
  p.*,
  -- Cuántos de los seis puntos están resueltos: es el "3 de 6" de la ficha.
  (p.titulo::int + p.cedula::int + p.informe_dominio::int + p.vtv::int
     + (case when p.patentes_deuda is not null then 1 else 0 end)
     + (case when p.multas_monto is not null then 1 else 0 end)) as completos,
  case
    when p.vtv_vence is null then null
    else (p.vtv_vence - current_date)
  end as dias_para_vtv
from public.vehiculo_papeles p;

alter view public.v_vehiculo_papeles set (security_invoker = on);
