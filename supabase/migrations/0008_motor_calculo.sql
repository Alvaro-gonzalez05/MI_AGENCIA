-- =====================================================================
-- MI AGENCIA — 0008: MOTOR DE CALCULO
--
-- Port 1:1 de computeInventory() del HTML original (rotacion_1.html,
-- lineas 677-747), que a su vez replicaba las formulas de la hoja
-- "Inventario" del Excel del cliente.
--
-- Por que en SQL y no en Dart: estas formulas definen cuanta plata gana
-- la agencia. Si viven en la app, hay que reimplementarlas en cada
-- plataforma y cualquier divergencia se paga en pesos. Aca hay UNA sola
-- definicion; la app solo la lee. Los simuladores interactivos (precio
-- sugerido, cuotas) si viven en Dart, porque son "que pasaria si" que no
-- se persisten.
--
-- Las diferencias intencionales respecto del original estan comentadas
-- con [CAMBIO].
-- =====================================================================

-- Gastos de cada vehiculo, en nominal y ajustados por IPC a valor de hoy.
create or replace view public.v_vehiculo_gastos as
select g.vehiculo_id,
       count(*)::int                                    as cantidad_gastos,
       coalesce(sum(g.importe), 0)                      as gastos_nominal,
       -- Cada gasto se trae a moneda de hoy con el IPC del mes en que se hizo:
       --   importe * indice_hoy / indice_del_mes_del_gasto
       coalesce(sum(g.importe * public.ipc_indice_hoy()
                    / nullif(public.ipc_indice_en(g.fecha), 0)), 0) as gastos_ajustados
from public.gastos g
group by g.vehiculo_id;

-- Ultimo precio publicado de cada vehiculo.
create or replace view public.v_vehiculo_precio_actual as
select distinct on (cp.vehiculo_id)
       cp.vehiculo_id,
       cp.precio_nuevo as precio_publicado,
       cp.fecha        as fecha_precio,
       cp.motivo       as motivo_precio
from public.cambios_precio cp
order by cp.vehiculo_id, cp.fecha desc, cp.created_at desc;

-- ---------------------------------------------------------------------
-- VISTA PRINCIPAL: una fila por vehiculo con todo ya calculado.
-- Es la que alimenta el Dashboard, el Inventario y la Ficha.
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
    coalesce(vg.gastos_ajustados, 0) as gastos_vehiculo_ajustados,
    coalesce(vg.cantidad_gastos, 0)  as cantidad_gastos,

    -- Si nunca se cambio el precio, rige el precio objetivo de alta.
    coalesce(vpa.precio_publicado, v.precio_objetivo) as precio_actual,
    vpa.fecha_precio,

    public.ipc_indice_hoy()                as indice_hoy,
    public.ipc_indice_en(v.fecha_ingreso)  as indice_ingreso,
    coalesce(public.cotizacion_vigente(cfg.tipo_cambio_preferido), 0) as tipo_cambio
  from public.vehiculos v
  join public.agencia_config cfg           on cfg.agencia_id = v.agencia_id
  left join public.ventas vt               on vt.vehiculo_id = v.id
  left join public.v_vehiculo_gastos vg    on vg.vehiculo_id = v.id
  left join public.v_vehiculo_precio_actual vpa on vpa.vehiculo_id = v.id
  where v.deleted_at is null
),
calc as (
  select
    b.*,
    (b.venta_id is not null) as vendido,
    -- gastos_acum = gastos del vehiculo + gastos de cierre de la venta
    (b.gastos_vehiculo + b.gastos_finales) as gastos_acum,
    (b.precio_compra + b.gastos_vehiculo + b.gastos_finales) as costo_total,
    -- El reloj para: si se vendio cuenta hasta la venta, si no hasta hoy.
    (coalesce(b.fecha_venta, current_date) - b.fecha_ingreso) as dias_en_stock,
    -- Costo a valor de hoy. Nota: gastos_finales NO se ajusta por IPC,
    -- igual que en el original, porque la venta es reciente por definicion.
    (b.precio_compra * b.indice_hoy / nullif(b.indice_ingreso, 0)
       + b.gastos_vehiculo_ajustados
       + b.gastos_finales) as costo_total_hoy
  from base b
)
select
  c.id,
  c.agencia_id,
  c.codigo,
  c.marca,
  c.modelo,
  c.anio,
  c.version,
  c.km,
  c.patente,
  c.fecha_compra,
  c.fecha_ingreso,
  c.precio_compra,
  c.precio_objetivo,
  c.observaciones,
  c.ref_version_id,
  c.created_at,

  -- La venta manda sobre el estado guardado, igual que en el original.
  case when c.vendido then 'vendido'::estado_vehiculo else c.estado end as estado,
  c.vendido,
  c.venta_id,
  c.fecha_venta,
  c.precio_final,

  c.cantidad_gastos,
  c.gastos_acum,
  c.gastos_finales,
  c.costo_total,
  c.dias_en_stock,
  c.precio_actual,
  c.fecha_precio,

  -- Capital parado en el predio. Lo vendido ya no inmoviliza plata.
  case when c.vendido then 0 else c.costo_total end            as capital_inmovilizado,
  (c.precio_actual - c.costo_total)                            as ganancia_estimada,

  -- Margen sobre PRECIO DE VENTA (no sobre costo): (precio - costo) / precio.
  (c.precio_objetivo - c.costo_total) / nullif(c.precio_objetivo, 0) as margen_esperado,
  (c.precio_actual   - c.costo_total) / nullif(c.precio_actual, 0)   as margen_actual,
  case when c.vendido
       then (c.precio_final - c.costo_total) / nullif(c.precio_final, 0)
  end                                                                as margen_real,

  -- Precio al que habria que publicarlo para alcanzar cada margen.
  c.costo_total / nullif(1 - c.margen_objetivo, 0)             as precio_para_margen_objetivo,
  c.costo_total / nullif(1 - c.margen_minimo, 0)               as precio_para_margen_minimo,
  c.costo_total                                                as precio_equilibrio,
  -- Redondeado hacia arriba al multiplo que use la agencia: el precio que
  -- se publica de verdad (el original usaba roundUp con step = redondeo).
  ceil((c.costo_total / nullif(1 - c.margen_objetivo, 0)) / nullif(c.redondeo, 0))
    * c.redondeo                                               as precio_sugerido,

  (c.costo_total / nullif(1 - c.margen_objetivo, 0)) / nullif(c.precio_actual, 0) - 1
                                                               as ajuste_necesario,
  c.precio_actual / nullif(c.precio_objetivo, 0) - 1            as var_vs_objetivo,
  c.gastos_acum / nullif(c.precio_compra, 0)                   as gastos_ratio,
  case when c.dias_en_stock > 0 then c.costo_total / c.dias_en_stock else c.costo_total end
                                                               as costo_diario,

  -- ---- Ajustado por inflacion (IPC INDEC) ----
  c.indice_ingreso,
  c.indice_hoy,
  c.costo_total_hoy,
  (c.precio_actual - c.costo_total_hoy)                        as ganancia_real_ipc,
  (c.precio_actual - c.costo_total_hoy) / nullif(c.precio_actual, 0) as margen_real_ipc,
  c.tipo_cambio,
  case when c.tipo_cambio > 0
       then (c.precio_actual - c.costo_total_hoy) / c.tipo_cambio
  end                                                          as ganancia_real_usd,

  -- ---- Semaforo de antiguedad en stock ----
  case
    when c.vendido then 'vendido'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_rojo     then 'critico'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_amarillo then 'atencion'
    when (coalesce(c.fecha_venta, current_date) - c.fecha_ingreso) >= c.dias_verde    then 'observar'
    else 'normal'
  end as alerta,

  -- Umbrales vigentes, para que la app pinte sin volver a pedir la config.
  c.dias_verde, c.dias_amarillo, c.dias_rojo,
  c.margen_minimo, c.margen_objetivo, c.umbral_gastos_altos,
  c.tolerancia_caida_margen, c.tolerancia_desvio_precio,

  -- Valor de revista de ArgAutos, si la unidad esta enlazada al catalogo.
  rp.precio_ars   as revista_ars,
  rp.precio_usd   as revista_usd,
  rp.actualizado_at as revista_actualizada_at,
  case when rp.precio_ars > 0
       then c.precio_actual / rp.precio_ars - 1
  end as var_vs_revista
from calc c
left join public.ref_precios rp
       on rp.version_id = c.ref_version_id and rp.anio = c.anio;

comment on view public.v_inventario is
  'Motor de calculo. Port de computeInventory() del HTML original. Fuente unica de verdad de costos, margenes y alertas.';

-- ---------------------------------------------------------------------
-- Diagnostico en texto (el parrafo que arma diagParts en el original).
-- Va en funcion aparte y no en la vista porque es presentacion, no dato:
-- si manana cambia la redaccion o se traduce, no se toca el motor.
-- ---------------------------------------------------------------------
create or replace function public.diagnostico_vehiculo(p_vehiculo uuid)
returns text
language plpgsql
stable
as $fn$
declare
  r     record;
  partes text[] := '{}';
begin
  select * into r from public.v_inventario where id = p_vehiculo;
  if not found then return null; end if;

  if r.vendido then
    partes := partes || format('Vendido en %s dias con margen real de %s%%.',
                               r.dias_en_stock, round(coalesce(r.margen_real, 0) * 100, 1));
  else
    if r.dias_en_stock >= r.dias_rojo then
      partes := partes || format('Lleva %s dias en stock, muy por encima del plazo objetivo.', r.dias_en_stock);
    elsif r.dias_en_stock >= r.dias_amarillo then
      partes := partes || format('Lleva %s dias en stock.', r.dias_en_stock);
    elsif r.dias_en_stock >= r.dias_verde then
      partes := partes || format('Lleva %s dias en stock, dentro de lo esperable.', r.dias_en_stock);
    else
      partes := partes || format('Lleva %s dias en stock, plazo normal.', r.dias_en_stock);
    end if;

    if r.margen_actual < r.margen_minimo then
      partes := partes || format('Margen actual %s%%, por debajo del minimo.', round(r.margen_actual * 100, 1));
    end if;
    if r.margen_actual < r.margen_esperado - r.tolerancia_caida_margen then
      partes := partes || format('El margen cayo de %s%% a %s%%.',
                                 round(r.margen_esperado * 100, 1), round(r.margen_actual * 100, 1));
    end if;
    if r.gastos_acum >= r.umbral_gastos_altos then
      partes := partes || format('Acumula %s de gastos.', to_char(r.gastos_acum, 'FM$999G999G999'));
    end if;
    if r.margen_actual >= r.margen_objetivo then
      partes := partes || 'Margen por encima del objetivo.';
    end if;
    if r.ajuste_necesario > r.tolerancia_desvio_precio then
      -- Precio exacto, no el redondeado: es el umbral real del margen.
      -- El redondeado a publicar esta en v_inventario.precio_sugerido.
      partes := partes || format('Para el margen objetivo habria que publicarlo a %s.',
                                 to_char(r.precio_para_margen_objetivo, 'FM$999G999G999'));
    end if;
  end if;

  return array_to_string(partes, ' ');
end $fn$;

-- ---------------------------------------------------------------------
-- Totales de la agencia para las tarjetas del Dashboard.
-- ---------------------------------------------------------------------
create or replace view public.v_dashboard as
select
  agencia_id,
  count(*) filter (where not vendido)                       as unidades_en_stock,
  count(*) filter (where vendido)                           as unidades_vendidas,
  coalesce(sum(capital_inmovilizado), 0)                    as capital_inmovilizado,
  coalesce(sum(gastos_acum) filter (where not vendido), 0)  as gastos_en_stock,
  coalesce(sum(ganancia_estimada) filter (where not vendido), 0) as ganancia_potencial,
  coalesce(sum(precio_final - costo_total) filter (where vendido), 0) as ganancia_realizada,
  coalesce(sum(ganancia_real_ipc) filter (where vendido), 0) as ganancia_realizada_ipc,
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

-- ---------------------------------------------------------------------
-- Evolucion mensual: capital inmovilizado y ganancia acumulada mes a mes.
-- Port de evolucionMensual(). Alimenta los graficos de linea.
-- ---------------------------------------------------------------------
create or replace function public.evolucion_mensual(p_agencia uuid, p_meses int default 14)
returns table (
  mes date,
  capital_inmovilizado numeric,
  ganancia_nominal_acum numeric,
  ganancia_real_acum numeric,
  unidades_en_stock int,
  unidades_vendidas_acum int
)
language sql
stable
as $fn$
  with meses as (
    select generate_series(
             date_trunc('month', current_date)::date - ((p_meses - 1) || ' months')::interval,
             date_trunc('month', current_date)::date,
             '1 month'::interval)::date as mes
  ),
  cortes as (
    select m.mes, (m.mes + interval '1 month - 1 day')::date as fin_mes
    from meses m
  )
  select
    c.mes,
    coalesce(sum(
      case when v.fecha_ingreso <= c.fin_mes
            and (vt.fecha_venta is null or vt.fecha_venta > c.fin_mes)
      then v.precio_compra + coalesce((
             select sum(g.importe) from public.gastos g
              where g.vehiculo_id = v.id and g.fecha <= c.fin_mes), 0)
      end), 0) as capital_inmovilizado,
    coalesce(sum(
      case when vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes
      then vt.precio_final - (v.precio_compra + coalesce((
             select sum(g.importe) from public.gastos g
              where g.vehiculo_id = v.id), 0) + coalesce(vt.gastos_finales, 0))
      end), 0) as ganancia_nominal_acum,
    coalesce(sum(
      case when vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes
      then vt.precio_final - inv.costo_total_hoy
      end), 0) as ganancia_real_acum,
    count(*) filter (
      where v.fecha_ingreso <= c.fin_mes
        and (vt.fecha_venta is null or vt.fecha_venta > c.fin_mes))::int as unidades_en_stock,
    count(*) filter (
      where vt.fecha_venta is not null and vt.fecha_venta <= c.fin_mes)::int as unidades_vendidas_acum
  from cortes c
  cross join public.vehiculos v
  left join public.ventas vt on vt.vehiculo_id = v.id
  left join lateral (
    select (i.costo_total_hoy) from public.v_inventario i where i.id = v.id
  ) inv on true
  where v.agencia_id = p_agencia and v.deleted_at is null
  group by c.mes
  order by c.mes;
$fn$;
