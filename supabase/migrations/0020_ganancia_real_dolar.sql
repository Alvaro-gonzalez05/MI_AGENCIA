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
