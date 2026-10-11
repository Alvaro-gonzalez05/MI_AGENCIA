-- =====================================================================
--  MI AGENCIA — 0027: planes de pago, cuotas y cobranzas
--
--  El diseño muestra esto en tres lugares: "3 clientes atrasados en cuotas"
--  en el Inicio, "Debe la cuota 4 de su plan: $ 350.000 · 12 días de atraso"
--  en lo que hay para atender hoy, y la deuda del cliente en su ficha.
--
--  La agencia financia de su bolsillo: el auto sale del salón y la plata
--  entra en cuotas durante un año. Hasta ahora eso vivía en un cuaderno, y
--  el cuaderno no avisa quién se atrasó. Por eso el plan se guarda con sus
--  cuotas una por una: sin las cuotas no hay vencimiento, y sin vencimiento
--  no hay aviso.
--
--  Los pagos son su propia tabla y no un campo "pagado" en la cuota: pasa
--  todo el tiempo que alguien pague la mitad de una cuota, o dos cuotas
--  juntas, y hay que poder decir cuándo entró cada peso.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'estado_plan') then
    create type estado_plan as enum ('activo','terminado','cancelado');
  end if;
  if not exists (select 1 from pg_type where typname = 'medio_pago') then
    create type medio_pago as enum
      ('efectivo','transferencia','debito','credito','cheque','otro');
  end if;
end $$;

create table if not exists public.planes_pago (
  id               uuid primary key default gen_random_uuid(),
  agencia_id       uuid not null references public.agencias(id) on delete cascade,

  -- A quién se le financió. La oportunidad es opcional porque muchas veces
  -- el plan se arma con alguien que todavía no está cargado como cliente.
  oportunidad_id   uuid references public.oportunidades(id) on delete set null,
  cliente_nombre   text not null,
  cliente_telefono text,

  -- Sobre qué operación. También opcional: hay planes de una venta vieja
  -- que nunca se cargó en el sistema.
  venta_id         uuid references public.ventas(id) on delete set null,
  vehiculo_id      uuid references public.vehiculos(id) on delete set null,

  monto_financiado numeric(14,2) not null,
  cantidad_cuotas  smallint not null,
  sistema          text not null default 'frances',
  tna              numeric(6,4) not null default 0,

  estado           estado_plan not null default 'activo',
  notas            text,

  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint planes_monto_positivo check (monto_financiado > 0),
  constraint planes_cuotas_validas check (cantidad_cuotas between 1 and 120),
  constraint planes_sistema_valido
    check (sistema in ('frances','aleman','directo','global'))
);

create index if not exists planes_agencia_idx on public.planes_pago (agencia_id);
create index if not exists planes_cliente_idx on public.planes_pago (oportunidad_id);

create table if not exists public.cuotas (
  id          uuid primary key default gen_random_uuid(),
  plan_id     uuid not null references public.planes_pago(id) on delete cascade,
  agencia_id  uuid not null references public.agencias(id) on delete cascade,

  numero      smallint not null,
  vence_el    date not null,
  importe     numeric(14,2) not null,

  created_at  timestamptz not null default now(),

  unique (plan_id, numero),
  constraint cuotas_importe_positivo check (importe > 0)
);

create index if not exists cuotas_vencimiento_idx
  on public.cuotas (agencia_id, vence_el);

create table if not exists public.pagos (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  cuota_id    uuid not null references public.cuotas(id) on delete cascade,

  fecha       date not null default current_date,
  importe     numeric(14,2) not null,
  medio       medio_pago not null default 'efectivo',
  notas       text,

  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),

  constraint pagos_importe_positivo check (importe > 0)
);

create index if not exists pagos_cuota_idx on public.pagos (cuota_id);
create index if not exists pagos_fecha_idx on public.pagos (agencia_id, fecha);

-- ---------------------------------------------------------------------
--  Permisos
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['planes_pago','cuotas','pagos'] loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format($f$create policy %I on public.%I for select to authenticated
                      using (public.puede_ver_agencia(agencia_id))$f$,
                   t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format($f$create policy %I on public.%I for insert to authenticated
                      with check (public.puede_editar(agencia_id))$f$,
                   t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($f$create policy %I on public.%I for update to authenticated
                      using (public.puede_editar(agencia_id))
                      with check (public.puede_editar(agencia_id))$f$,
                   t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($f$create policy %I on public.%I for delete to authenticated
                      using (public.puede_editar(agencia_id))$f$,
                   t || '_delete', t);
  end loop;
end $$;

drop trigger if exists planes_pago_touch on public.planes_pago;
create trigger planes_pago_touch
  before update on public.planes_pago
  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------------
--  Armar el plan: las cuotas se calculan una sola vez, al crearlo
-- ---------------------------------------------------------------------
--  El cálculo está en la base y no en la app para que el día que se cargue
--  un plan desde otro lado (una importación, un script) las cuotas salgan
--  iguales. Es el mismo criterio que usa el simulador.
create or replace function public.generar_cuotas(p_plan uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  pl        public.planes_pago;
  i         integer;
  tasa      numeric;
  cuota     numeric;
  capital   numeric;
  saldo     numeric;
  interes   numeric;
  primera   date;
  creadas   integer := 0;
begin
  select * into pl from public.planes_pago where id = p_plan;
  if not found then
    raise exception 'El plan % no existe', p_plan;
  end if;

  delete from public.cuotas where plan_id = p_plan;

  tasa    := pl.tna / 12;
  saldo   := pl.monto_financiado;
  -- La primera vence al mes de armado: es lo que se acuerda de palabra.
  primera := (pl.created_at::date + interval '1 month')::date;

  for i in 1..pl.cantidad_cuotas loop
    case pl.sistema
      when 'frances' then
        cuota := case
                   when tasa = 0 then pl.monto_financiado / pl.cantidad_cuotas
                   else pl.monto_financiado * tasa
                        * power(1 + tasa, pl.cantidad_cuotas)
                        / (power(1 + tasa, pl.cantidad_cuotas) - 1)
                 end;
      when 'aleman' then
        capital := pl.monto_financiado / pl.cantidad_cuotas;
        interes := saldo * tasa;
        cuota   := capital + interes;
        saldo   := saldo - capital;
      when 'directo' then
        cuota := (pl.monto_financiado
                  + pl.monto_financiado * tasa * pl.cantidad_cuotas)
                 / pl.cantidad_cuotas;
      when 'global' then
        -- Todo al final: las cuotas intermedias no existen.
        cuota := case
                   when i = pl.cantidad_cuotas
                   then pl.monto_financiado
                        * power(1 + tasa, pl.cantidad_cuotas)
                   else 0
                 end;
      else
        cuota := pl.monto_financiado / pl.cantidad_cuotas;
    end case;

    if cuota > 0 then
      insert into public.cuotas (plan_id, agencia_id, numero, vence_el, importe)
      values (
        pl.id,
        pl.agencia_id,
        i,
        (primera + make_interval(months => i - 1))::date,
        round(cuota, 2)
      );
      creadas := creadas + 1;
    end if;
  end loop;

  return creadas;
end $$;

grant execute on function public.generar_cuotas(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  La cuenta corriente, lista para leer
-- ---------------------------------------------------------------------
create or replace view public.v_cuotas as
select
  c.*,
  pl.cliente_nombre,
  pl.cliente_telefono,
  pl.oportunidad_id,
  pl.vehiculo_id,
  pl.estado           as estado_plan,
  coalesce(p.pagado, 0)                       as pagado,
  c.importe - coalesce(p.pagado, 0)           as saldo,
  p.ultimo_pago,
  (c.importe - coalesce(p.pagado, 0)) <= 0.01 as saldada,
  case
    when (c.importe - coalesce(p.pagado, 0)) <= 0.01 then 0
    else greatest(0, current_date - c.vence_el)
  end as dias_de_atraso
from public.cuotas c
join public.planes_pago pl on pl.id = c.plan_id
left join lateral (
  select sum(importe) as pagado, max(fecha) as ultimo_pago
    from public.pagos g
   where g.cuota_id = c.id
) p on true;

alter view public.v_cuotas set (security_invoker = on);

--  Una fila por plan: lo que debe, lo que ya pagó y cuánto hace que se
--  atrasó. Es lo que mira el Inicio y la ficha del cliente.
create or replace view public.v_planes as
select
  pl.*,
  count(c.*)                                        as cuotas_totales,
  count(*) filter (where c.saldada)                 as cuotas_pagas,
  count(*) filter (where not c.saldada
                     and c.dias_de_atraso > 0)      as cuotas_vencidas,
  coalesce(sum(c.importe), 0)                       as total_plan,
  coalesce(sum(c.pagado), 0)                        as total_pagado,
  coalesce(sum(c.saldo), 0)                         as deuda,
  coalesce(sum(c.saldo) filter (where c.dias_de_atraso > 0), 0) as deuda_vencida,
  max(c.dias_de_atraso)                             as peor_atraso,
  min(c.vence_el) filter (where not c.saldada)      as proximo_vencimiento
from public.planes_pago pl
left join public.v_cuotas c on c.plan_id = pl.id
group by pl.id;

alter view public.v_planes set (security_invoker = on);

-- ---------------------------------------------------------------------
--  Un plan sin cuotas pendientes se da por terminado solo
-- ---------------------------------------------------------------------
create or replace function public.cerrar_plan_si_termino()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan uuid;
  falta  numeric;
begin
  select c.plan_id into v_plan
    from public.cuotas c
   where c.id = coalesce(new.cuota_id, old.cuota_id);

  select coalesce(sum(saldo), 0) into falta
    from public.v_cuotas where plan_id = v_plan;

  update public.planes_pago
     set estado = case when falta <= 0.01 then 'terminado'::estado_plan
                       else 'activo'::estado_plan end
   where id = v_plan
     and estado <> 'cancelado';

  return null;
end $$;

drop trigger if exists pagos_cierran_plan on public.pagos;
create trigger pagos_cierran_plan
  after insert or update or delete on public.pagos
  for each row execute function public.cerrar_plan_si_termino();
