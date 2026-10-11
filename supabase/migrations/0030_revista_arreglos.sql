-- =====================================================================
--  MI AGENCIA — 0030: dos arreglos del cosechador, encontrados probándolo
--
--  1. Guardar las valuaciones fallaba: el `case` que decide el estado
--     devuelve texto y la columna es un enum. Postgres no convierte solo
--     adentro de un `case`.
--  2. La consulta gastada no se contaba cuando el guardado fallaba. El
--     contador vivía adentro del bloque con `exception`, y ese bloque se
--     deshace entero al fallar: la consulta ya se le hizo a la guía, pero
--     para nosotros no había pasado. Ahora se cuenta antes de salir.
-- =====================================================================

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
    insert into public.ref_precios (
      version_id, anio, precio_ars, precio_usd, tc_usado, actualizado_at
    )
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
     set estado = case
                    when cuenta = 0 then 'sin_resultado'::estado_tarea_revista
                    else 'hecha'::estado_tarea_revista
                  end,
         procesado_at = now(),
         detalle = format('%s año(s) guardado(s)', cuenta)
   where id = p_tarea;

  return cuenta;
end $$;

revoke all on function public.guardar_valuaciones_revista(bigint, jsonb, numeric)
  from public, anon, authenticated;

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

        -- La consulta se cuenta ANTES de usarla: si lo que sigue falla, la
        -- guía igual la recibió y el cupo del día se gastó.
        update public.ref_api_uso
           set consultas = consultas + 1
         where fecha = current_date;

        begin
          select * into r from extensions.http_get(url);

          if r.status = 429 then
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
                 estado = case
                            when intentos + 1 >= 3
                              then 'error'::estado_tarea_revista
                            else 'pendiente'::estado_tarea_revista
                          end,
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
