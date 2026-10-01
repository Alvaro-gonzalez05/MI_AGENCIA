-- =====================================================================
--  MI AGENCIA — 0026: la agenda de tareas
--
--  Es el "Agendar una tarea" del Inicio y el modal "Nueva tarea" del
--  diseño: llamar, cobrar, llevar al taller, ir al banco, un trámite.
--
--  Por qué existe: lo que hoy llena "Para atender hoy" son cosas que el
--  sistema deduce solo (una unidad parada, una consulta vencida). Lo que la
--  agencia necesita además es anotar lo que le prometió a alguien —"el
--  martes lo llamo", "el jueves paso por la gestoría"— y que eso aparezca el
--  día que corresponde, y no en una hoja suelta arriba del mostrador.
--
--  Las tareas que se repiten (la cuota de cada mes) no se guardan una por
--  una: se guarda la regla y, al marcarla hecha, se crea la siguiente.
-- =====================================================================

do $$
begin
  if not exists (select 1 from pg_type where typname = 'tipo_tarea') then
    create type tipo_tarea as enum
      ('llamar','cobrar','taller','banco','tramite','otro');
  end if;
  if not exists (select 1 from pg_type where typname = 'repeticion_tarea') then
    create type repeticion_tarea as enum ('una_vez','diaria','semanal','mensual');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_tarea') then
    create type estado_tarea as enum ('pendiente','hecha','cancelada');
  end if;
end $$;

create table if not exists public.tareas (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references public.agencias(id) on delete cascade,

  tipo           tipo_tarea not null default 'otro',
  titulo         text not null,
  detalle        text,

  -- Con quién y sobre qué auto. Las dos opcionales: "pasar por el banco" no
  -- tiene cliente ni unidad.
  oportunidad_id uuid references public.oportunidades(id) on delete set null,
  vehiculo_id    uuid references public.vehiculos(id) on delete set null,

  vence_el       date not null default current_date,
  hora           time,
  repeticion     repeticion_tarea not null default 'una_vez',

  estado         estado_tarea not null default 'pendiente',
  hecha_el       timestamptz,

  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint tareas_titulo_no_vacio check (length(trim(titulo)) > 0)
);

create index if not exists tareas_agencia_idx on public.tareas (agencia_id);

-- Lo que se consulta todo el tiempo: qué tengo para hoy.
create index if not exists tareas_pendientes_idx
  on public.tareas (agencia_id, vence_el)
  where estado = 'pendiente';

alter table public.tareas enable row level security;

drop policy if exists tareas_select on public.tareas;
create policy tareas_select on public.tareas
  for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

drop policy if exists tareas_insert on public.tareas;
create policy tareas_insert on public.tareas
  for insert to authenticated
  with check (public.puede_editar(agencia_id));

drop policy if exists tareas_update on public.tareas;
create policy tareas_update on public.tareas
  for update to authenticated
  using (public.puede_editar(agencia_id))
  with check (public.puede_editar(agencia_id));

drop policy if exists tareas_delete on public.tareas;
create policy tareas_delete on public.tareas
  for delete to authenticated
  using (public.puede_editar(agencia_id));

drop trigger if exists tareas_touch on public.tareas;
create trigger tareas_touch
  before update on public.tareas
  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------------
--  Al marcar hecha una tarea que se repite, nace la siguiente
-- ---------------------------------------------------------------------
create or replace function public.repetir_tarea()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  proxima date;
begin
  if new.estado <> 'hecha' or old.estado = 'hecha' then
    return new;
  end if;
  if new.repeticion = 'una_vez' then
    return new;
  end if;

  proxima := case new.repeticion
               when 'diaria'  then new.vence_el + 1
               when 'semanal' then new.vence_el + 7
               when 'mensual' then (new.vence_el + interval '1 month')::date
             end;

  insert into public.tareas (
    agencia_id, tipo, titulo, detalle, oportunidad_id, vehiculo_id,
    vence_el, hora, repeticion, created_by
  ) values (
    new.agencia_id, new.tipo, new.titulo, new.detalle, new.oportunidad_id,
    new.vehiculo_id, proxima, new.hora, new.repeticion, new.created_by
  );

  return new;
end $$;

drop trigger if exists tareas_se_repiten on public.tareas;
create trigger tareas_se_repiten
  after update on public.tareas
  for each row execute function public.repetir_tarea();

-- ---------------------------------------------------------------------
--  Vista con lo que necesita el Inicio
-- ---------------------------------------------------------------------
create or replace view public.v_tareas as
select
  t.*,
  (t.vence_el - current_date) as dias_para_vencer,
  c.nombre || ' ' || coalesce(c.apellido, '') as cliente_nombre,
  c.telefono                                  as cliente_telefono,
  v.marca || ' ' || v.modelo                  as vehiculo_titulo,
  v.patente                                   as vehiculo_patente
from public.tareas t
left join public.oportunidades o on o.id = t.oportunidad_id
left join public.clientes c      on c.id = o.cliente_id
left join public.vehiculos v     on v.id = t.vehiculo_id;

alter view public.v_tareas set (security_invoker = on);
