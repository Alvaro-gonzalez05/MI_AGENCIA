-- =====================================================================
--  MI AGENCIA — 0024: reservas de unidades
--
--  En el diseño la reserva aparece en tres lugares: el inventario ("Reservado
--  hasta el 25/09"), la ficha ("Reservar unidad") y el Inicio ("Vence mañana ·
--  seña de $ 500.000 depositada"). Es una operación de todos los días: alguien
--  deja una seña, el auto se guarda unos días y, si no vuelve, sale de nuevo a
--  la venta.
--
--  Se guarda como tabla aparte y no como un campo del vehículo porque tiene
--  datos propios (quién, cuánto dejó, hasta cuándo) y porque interesa el
--  historial: una unidad que se reservó tres veces y se cayó tres veces es
--  una señal, no un dato para pisar.
--
--  El estado del vehículo lo sincroniza un trigger: mientras haya una reserva
--  activa, la unidad queda 'reservado'; al cancelarla o vencerse, vuelve a
--  'en_stock' (salvo que ya esté vendida).
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'estado_reserva') then
    create type estado_reserva as enum ('activa','cancelada','concretada','vencida');
  end if;
end $$;

create table if not exists public.reservas (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references public.agencias(id) on delete cascade,
  vehiculo_id     uuid not null references public.vehiculos(id) on delete cascade,

  -- A quién se le reservó. La oportunidad es opcional: muchas veces la seña
  -- la deja alguien que todavía no está cargado como interesado.
  oportunidad_id  uuid references public.oportunidades(id) on delete set null,
  cliente_nombre  text not null,
  cliente_telefono text,

  senia           numeric(14,2) not null default 0,
  fecha_reserva   date not null default current_date,
  vence_el        date not null,
  estado          estado_reserva not null default 'activa',
  notas           text,

  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint reservas_senia_no_negativa check (senia >= 0),
  constraint reservas_vence_despues check (vence_el >= fecha_reserva)
);

create index if not exists reservas_vehiculo_idx on public.reservas (vehiculo_id);
create index if not exists reservas_agencia_idx  on public.reservas (agencia_id);

-- Una sola reserva activa por unidad: dos señas sobre el mismo auto es
-- exactamente el lío que este sistema viene a evitar.
create unique index if not exists reservas_una_activa
  on public.reservas (vehiculo_id)
  where estado = 'activa';

alter table public.reservas enable row level security;

drop policy if exists reservas_select on public.reservas;
create policy reservas_select on public.reservas
  for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

drop policy if exists reservas_insert on public.reservas;
create policy reservas_insert on public.reservas
  for insert to authenticated
  with check (public.puede_editar(agencia_id));

drop policy if exists reservas_update on public.reservas;
create policy reservas_update on public.reservas
  for update to authenticated
  using (public.puede_editar(agencia_id))
  with check (public.puede_editar(agencia_id));

drop policy if exists reservas_delete on public.reservas;
create policy reservas_delete on public.reservas
  for delete to authenticated
  using (public.puede_editar(agencia_id));

drop trigger if exists reservas_touch on public.reservas;
create trigger reservas_touch
  before update on public.reservas
  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------------
--  El estado del vehículo sigue a la reserva
-- ---------------------------------------------------------------------
create or replace function public.sincronizar_estado_por_reserva()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := coalesce(new.vehiculo_id, old.vehiculo_id);
  hay_activa boolean;
begin
  select exists (
    select 1 from public.reservas r
    where r.vehiculo_id = v_id and r.estado = 'activa'
  ) into hay_activa;

  update public.vehiculos v
     set estado = case
                    -- Una unidad vendida no vuelve a stock por una reserva
                    -- que se cancela: la venta manda.
                    when v.estado = 'vendido' then v.estado
                    when hay_activa then 'reservado'::estado_vehiculo
                    when v.estado = 'reservado' then 'en_stock'::estado_vehiculo
                    else v.estado
                  end
   where v.id = v_id;

  return null;
end $$;

drop trigger if exists reservas_sincronizan_estado on public.reservas;
create trigger reservas_sincronizan_estado
  after insert or update or delete on public.reservas
  for each row execute function public.sincronizar_estado_por_reserva();

-- ---------------------------------------------------------------------
--  Las reservas vencidas se marcan solas
-- ---------------------------------------------------------------------
--  No hay cron para esto: se ejecuta al leer, que es cuando importa. Una
--  reserva vencida ayer tiene que aparecer vencida hoy aunque nadie haya
--  abierto la app en el medio.
create or replace function public.vencer_reservas()
returns integer
language sql
security definer
set search_path = public
as $$
  with vencidas as (
    update public.reservas
       set estado = 'vencida'
     where estado = 'activa'
       and vence_el < current_date
    returning 1
  )
  select count(*)::int from vencidas;
$$;

grant execute on function public.vencer_reservas() to authenticated;

create or replace view public.v_reservas as
select
  r.*,
  v.codigo   as vehiculo_codigo,
  v.marca || ' ' || v.modelo as vehiculo_titulo,
  v.patente  as vehiculo_patente,
  (r.vence_el - current_date) as dias_para_vencer
from public.reservas r
join public.vehiculos v on v.id = r.vehiculo_id;

alter view public.v_reservas set (security_invoker = on);
