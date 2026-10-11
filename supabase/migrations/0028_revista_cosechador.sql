-- =====================================================================
--  MI AGENCIA — 0028: el valor de revista, de a poco y solo lo que se usa
--
--  ArgAutos (argautos.com/api/v1) publica los precios de la guía gratis y
--  sin clave, pero con dos límites: 3 consultas por minuto y 30 por día.
--  Con eso, bajar el catálogo entero es imposible —son cientos de miles de
--  combinaciones de versión y año— y tampoco haría falta: a una agencia le
--  importa el precio de SUS autos.
--
--  Entonces el proceso trabaja a pedido: cuando entra una unidad, se encola;
--  el cosechador gasta las consultas del día resolviendo esa cola, y una vez
--  por mes vuelve a encolar el stock vigente para refrescar los precios.
--
--  Dos consultas por unidad nueva:
--    1. `search`      → qué versión de la guía es, y su id.
--    2. `valuations`  → todos los años de esa versión, de una sola vez.
--  Y una sola por mes para refrescar.
-- =====================================================================

-- ---------------------------------------------------------------------
--  1. El catálogo deja de exigir la jerarquía completa
-- ---------------------------------------------------------------------
--  Antes una versión necesitaba su modelo y su marca ya cargados, lo que
--  obligaba a bajar el catálogo de arriba hacia abajo (3 consultas antes de
--  la primera versión). Como ahora se resuelve de a una unidad por
--  búsqueda, la versión guarda los nombres y el modelo queda opcional.
alter table public.ref_versiones
  alter column modelo_id drop not null;

alter table public.ref_versiones
  add column if not exists marca_nombre  text,
  add column if not exists modelo_nombre text;

comment on column public.ref_versiones.marca_nombre is
  'Marca tal como la devuelve la guía. Se guarda acá porque una versión se '
  'puede resolver por búsqueda, sin haber bajado su marca ni su modelo.';

-- ---------------------------------------------------------------------
--  2. La cola de trabajo
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'tarea_revista') then
    create type tarea_revista as enum ('buscar','valuar');
  end if;
  if not exists (select 1 from pg_type where typname = 'estado_tarea_revista') then
    create type estado_tarea_revista as enum
      ('pendiente','hecha','sin_resultado','error');
  end if;
end $$;

create table if not exists public.ref_cola (
  id           bigserial primary key,
  tipo         tarea_revista not null,

  -- Para 'buscar': qué texto mandarle a la guía y de qué año es la unidad.
  consulta     text,
  anio         smallint,

  -- Para 'valuar': qué versión refrescar.
  version_id   integer,

  -- A qué unidad sirve este trabajo. Si la unidad se borra, el trabajo
  -- deja de tener sentido.
  vehiculo_id  uuid references public.vehiculos(id) on delete cascade,

  -- Más bajo, antes. Una unidad recién cargada vale más que un refresco
  -- mensual: el vendedor la está mirando ahora.
  prioridad    smallint not null default 5,
  intentos     smallint not null default 0,
  estado       estado_tarea_revista not null default 'pendiente',
  detalle      text,

  created_at   timestamptz not null default now(),
  procesado_at timestamptz
);

create index if not exists ref_cola_pendientes_idx
  on public.ref_cola (prioridad, created_at)
  where estado = 'pendiente';

-- No encolar dos veces lo mismo mientras siga pendiente.
create unique index if not exists ref_cola_sin_repetidos
  on public.ref_cola (tipo, coalesce(consulta, ''), coalesce(version_id, 0), coalesce(anio, 0))
  where estado = 'pendiente';

--  Cuántas consultas gastamos hoy. La guía corta a 30; se para en 28 para
--  dejar aire a una consulta manual desde la app.
create table if not exists public.ref_api_uso (
  fecha      date primary key default current_date,
  consultas  integer not null default 0,
  limite     integer not null default 28
);

alter table public.ref_cola    enable row level security;
alter table public.ref_api_uso enable row level security;

--  Los datos de referencia son de lectura para cualquiera que entró; solo
--  el backend escribe (las funciones son security definer).
drop policy if exists ref_cola_select on public.ref_cola;
create policy ref_cola_select on public.ref_cola
  for select to authenticated using (true);

drop policy if exists ref_api_uso_select on public.ref_api_uso;
create policy ref_api_uso_select on public.ref_api_uso
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  3. Encolar una unidad
-- ---------------------------------------------------------------------
create or replace function public.encolar_revista(p_vehiculo uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.vehiculos;
begin
  select * into v from public.vehiculos where id = p_vehiculo;
  if not found or v.deleted_at is not null then
    return;
  end if;

  -- Ya sabemos qué versión es: alcanza con pedir sus precios.
  if v.ref_version_id is not null then
    insert into public.ref_cola (tipo, version_id, anio, vehiculo_id)
    values ('valuar', v.ref_version_id, v.anio, v.id)
    on conflict do nothing;
    return;
  end if;

  insert into public.ref_cola (tipo, consulta, anio, vehiculo_id)
  values (
    'buscar',
    trim(both ' ' from concat_ws(' ', v.marca, v.modelo, v.version)),
    v.anio,
    v.id
  )
  on conflict do nothing;
end $$;

grant execute on function public.encolar_revista(uuid) to authenticated;

create or replace function public.encolar_revista_al_guardar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo cuando cambia lo que define el precio.
  if tg_op = 'UPDATE'
     and new.marca is not distinct from old.marca
     and new.modelo is not distinct from old.modelo
     and new.version is not distinct from old.version
     and new.anio is not distinct from old.anio
     and new.ref_version_id is not distinct from old.ref_version_id then
    return null;
  end if;

  perform public.encolar_revista(new.id);
  return null;
end $$;

drop trigger if exists vehiculos_encolan_revista on public.vehiculos;
create trigger vehiculos_encolan_revista
  after insert or update on public.vehiculos
  for each row execute function public.encolar_revista_al_guardar();

-- ---------------------------------------------------------------------
--  4. Guardar lo que contesta la guía
-- ---------------------------------------------------------------------
--  Separado de la llamada HTTP para poder probarlo sin internet.
create or replace function public.guardar_busqueda_revista(
  p_tarea     bigint,
  p_resultado jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  t        public.ref_cola;
  elegido  jsonb;
  mejor    numeric := -1;
  fila     jsonb;
  puntaje  numeric;
begin
  select * into t from public.ref_cola where id = p_tarea;
  if not found then
    return 0;
  end if;

  -- La guía devuelve varias versiones parecidas. Se queda la que más se
  -- parece al texto que se buscó: comparar a ojo es justamente lo que no
  -- se puede hacer cuatro mil veces por mes.
  for fila in select * from jsonb_array_elements(coalesce(p_resultado, '[]'::jsonb))
  loop
    puntaje := similarity(
      lower(coalesce(fila->>'version_raw', fila->>'version', '')),
      lower(coalesce(t.consulta, ''))
    );
    -- Un empate se rompe por el año: la guía trae el año de su precio.
    if t.anio is not null and (fila->>'price_year') is not null
       and (fila->>'price_year')::int = t.anio then
      puntaje := puntaje + 0.15;
    end if;

    if puntaje > mejor then
      mejor := puntaje;
      elegido := fila;
    end if;
  end loop;

  if elegido is null then
    update public.ref_cola
       set estado = 'sin_resultado',
           procesado_at = now(),
           detalle = 'La guía no devolvió ninguna versión parecida.'
     where id = p_tarea;
    return 0;
  end if;

  insert into public.ref_versiones (id, nombre, nombre_raw, marca_nombre, modelo_nombre)
  values (
    (elegido->>'version_id')::int,
    coalesce(elegido->>'version', ''),
    elegido->>'version_raw',
    elegido->>'brand',
    elegido->>'model'
  )
  on conflict (id) do update
    set nombre        = excluded.nombre,
        nombre_raw    = excluded.nombre_raw,
        marca_nombre  = excluded.marca_nombre,
        modelo_nombre = excluded.modelo_nombre;

  -- Se le pega la versión a la unidad que disparó la búsqueda.
  if t.vehiculo_id is not null then
    update public.vehiculos
       set ref_version_id = (elegido->>'version_id')::int
     where id = t.vehiculo_id
       and ref_version_id is null;
  end if;

  update public.ref_cola
     set estado = 'hecha',
         procesado_at = now(),
         detalle = format('%s (parecido %s)',
                          elegido->>'version_raw',
                          round(mejor, 2))
   where id = p_tarea;

  -- Y ahora sí, a pedir sus precios.
  insert into public.ref_cola (tipo, version_id, anio, vehiculo_id, prioridad)
  values ('valuar', (elegido->>'version_id')::int, t.anio, t.vehiculo_id, 3)
  on conflict do nothing;

  return (elegido->>'version_id')::int;
end $$;

create or replace function public.guardar_valuaciones_revista(
  p_tarea     bigint,
  p_resultado jsonb,
  p_tc        numeric default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  t      public.ref_cola;
  fila   jsonb;
  cuenta integer := 0;
begin
  select * into t from public.ref_cola where id = p_tarea;
  if not found then
    return 0;
  end if;

  for fila in select * from jsonb_array_elements(coalesce(p_resultado, '[]'::jsonb))
  loop
    insert into public.ref_precios (version_id, anio, precio_ars, precio_usd, tc_usado, actualizado_at)
    values (
      coalesce((fila->>'version_id')::int, t.version_id),
      (fila->>'year')::smallint,
      (fila->>'price')::numeric,
      case when p_tc > 0 then (fila->>'price')::numeric / p_tc end,
      p_tc,
      now()
    )
    on conflict (version_id, anio) do update
      set precio_ars     = excluded.precio_ars,
          precio_usd     = excluded.precio_usd,
          tc_usado       = excluded.tc_usado,
          actualizado_at = now();
    cuenta := cuenta + 1;
  end loop;

  update public.ref_cola
     set estado = case when cuenta = 0 then 'sin_resultado' else 'hecha' end,
         procesado_at = now(),
         detalle = format('%s año(s) guardado(s)', cuenta)
   where id = p_tarea;

  return cuenta;
end $$;

revoke all on function public.guardar_busqueda_revista(bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.guardar_valuaciones_revista(bigint, jsonb, numeric)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  5. El cosechador
-- ---------------------------------------------------------------------
--  Igual que el IPC y el dólar: la llamada sale de Postgres con la
--  extensión `http`. En el Postgres de los tests (PGlite) esa extensión no
--  existe, así que todo lo que la necesita va adentro del bloque.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'http') then
    create extension if not exists http with schema extensions;

    create or replace function public.sincronizar_revista(p_maximo integer default 3)
    returns jsonb
    language plpgsql
    security definer
    set search_path = public, extensions
    as $fn$
    declare
      uso        public.ref_api_uso;
      t          public.ref_cola;
      r          extensions.http_response;
      cuerpo     jsonb;
      url        text;
      hechas     integer := 0;
      fallidas   integer := 0;
      disponible integer;
    begin
      -- Cuánto nos queda hoy. La guía corta a 30 por día: se para en 28.
      insert into public.ref_api_uso (fecha) values (current_date)
      on conflict (fecha) do nothing;
      select * into uso from public.ref_api_uso where fecha = current_date;

      disponible := least(p_maximo, uso.limite - uso.consultas);
      if disponible <= 0 then
        return jsonb_build_object(
          'consultas', 0,
          'motivo', 'Se acabó el cupo diario de la guía');
      end if;

      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');

      for t in
        select * from public.ref_cola
         where estado = 'pendiente'
         order by prioridad, created_at
         limit disponible
      loop
        url := case t.tipo
                 when 'buscar' then
                   'https://argautos.com/api/v1/search?q='
                   || extensions.urlencode(t.consulta)
                 else
                   'https://argautos.com/api/v1/versions/'
                   || t.version_id || '/valuations?currency=ars'
               end;

        begin
          select * into r from extensions.http_get(url);

          update public.ref_api_uso
             set consultas = consultas + 1
           where fecha = current_date;

          if r.status = 429 then
            -- Nos pasamos del límite: se deja la tarea para la próxima
            -- corrida y se corta acá, sin gastar las que quedan.
            return jsonb_build_object(
              'consultas', hechas,
              'motivo', 'La guía contestó 429 (demasiadas consultas)');
          end if;

          if r.status <> 200 then
            raise exception 'La guía respondió %', r.status;
          end if;

          cuerpo := r.content::jsonb;

          if t.tipo = 'buscar' then
            perform public.guardar_busqueda_revista(t.id, cuerpo->'data');
          else
            perform public.guardar_valuaciones_revista(
              t.id,
              cuerpo->'data',
              nullif(cuerpo #>> '{meta,exchange_rate,ars_per_usd}', '')::numeric
            );
          end if;

          hechas := hechas + 1;

        exception when others then
          fallidas := fallidas + 1;
          update public.ref_cola
             set intentos = intentos + 1,
                 -- Tres intentos y se deja: una versión que la guía no
                 -- tiene no la va a tener mañana tampoco.
                 estado = case when intentos + 1 >= 3 then 'error'::estado_tarea_revista
                               else 'pendiente'::estado_tarea_revista end,
                 detalle = left(sqlerrm, 300),
                 procesado_at = now()
           where id = t.id;
        end;
      end loop;

      return jsonb_build_object(
        'consultas', hechas,
        'fallidas', fallidas,
        'pendientes', (select count(*) from public.ref_cola where estado = 'pendiente'),
        'cupo_restante', (select limite - consultas from public.ref_api_uso
                           where fecha = current_date)
      );
    end $fn$;

    revoke all on function public.sincronizar_revista(integer)
      from public, anon, authenticated;
  end if;
end $$;

-- ---------------------------------------------------------------------
--  6. Refresco mensual del stock vigente
-- ---------------------------------------------------------------------
--  La guía actualiza sus valores a principio de mes. Se re-encola solo lo
--  que está en el salón: por un auto vendido en marzo no se gasta una
--  consulta.
create or replace function public.encolar_revista_mensual()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cuantas integer;
begin
  insert into public.ref_cola (tipo, version_id, anio, prioridad)
  select distinct 'valuar'::tarea_revista, v.ref_version_id, v.anio, 8
    from public.vehiculos v
   where v.deleted_at is null
     and v.ref_version_id is not null
     and v.estado <> 'vendido'
  on conflict do nothing;

  get diagnostics cuantas = row_count;

  -- Las que nunca se pudieron resolver vuelven a intentarse una vez por mes:
  -- la guía agrega versiones nuevas todo el tiempo.
  insert into public.ref_cola (tipo, consulta, anio, vehiculo_id, prioridad)
  select distinct
         'buscar'::tarea_revista,
         trim(both ' ' from concat_ws(' ', v.marca, v.modelo, v.version)),
         v.anio,
         v.id,
         9
    from public.vehiculos v
   where v.deleted_at is null
     and v.ref_version_id is null
     and v.estado <> 'vendido'
  on conflict do nothing;

  return cuantas;
end $$;

revoke all on function public.encolar_revista_mensual() from public, anon, authenticated;

-- ---------------------------------------------------------------------
--  7. Que corra solo
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_proc where proname = 'sincronizar_revista') then
    create extension if not exists pg_cron;

    -- Cada cinco minutos, hasta tres consultas. El cupo diario lo corta
    -- solo: en la práctica son unas diez corridas con trabajo y el resto
    -- no hace nada.
    perform cron.unschedule(jobid) from cron.job where jobname = 'sincronizar-revista';
    perform cron.schedule('sincronizar-revista', '*/5 * * * *',
                          'select public.sincronizar_revista(3)');

    -- El día 2 de cada mes se re-encola el stock: ArgAutos actualiza el 1.
    perform cron.unschedule(jobid) from cron.job where jobname = 'encolar-revista-mensual';
    perform cron.schedule('encolar-revista-mensual', '0 9 2 * *',
                          'select public.encolar_revista_mensual()');
  end if;
end $$;
