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
