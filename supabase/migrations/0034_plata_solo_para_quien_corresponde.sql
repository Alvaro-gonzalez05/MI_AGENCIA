-- =====================================================================
--  MI AGENCIA — 0034: la plata, solo para quien corresponde
--
--  La app ya no le muestra al vendedor el precio de compra, el costo ni la
--  ganancia. Eso es la mitad que se ve: cualquiera con el token de su
--  sesión puede pedirle las mismas columnas a la API y leerlas igual.
--
--  Acá se cierra del lado de la base. `v_inventario` devuelve null en esas
--  columnas cuando el que pregunta no es dueño ni administrador, que es
--  exactamente lo que ya responde `puede_administrar()`.
--
--  Queda afuera a propósito:
--    · los gastos, que el vendedor carga y por lo tanto conoce;
--    · el precio de venta, el de lista y el valor de revista, que son lo
--      que necesita para vender.
--
--  Y una consecuencia que hay que atajar: si el vendedor abre una unidad y
--  la guarda, su app manda precio_compra en null (es lo que leyó). Sin el
--  trigger de abajo, editar el color borraría lo que costó el auto.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Guardar una unidad no puede borrar lo que no se ve
-- ---------------------------------------------------------------------
create or replace function public.proteger_precio_compra()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.puede_administrar(new.agencia_id) then
    new.precio_compra := old.precio_compra;
  end if;
  return new;
end $$;

comment on function public.proteger_precio_compra() is
  'El que no ve el precio de compra tampoco lo pisa: al actualizar, se '
  'conserva el que ya estaba.';

drop trigger if exists vehiculos_protegen_precio_compra on public.vehiculos;
create trigger vehiculos_protegen_precio_compra
  before update on public.vehiculos
  for each row execute function public.proteger_precio_compra();

-- ---------------------------------------------------------------------
--  La vista del inventario, con la plata tapada según quién mira
-- ---------------------------------------------------------------------
--  Se repite entera porque `create or replace view` exige volver a listar
--  todas las columnas en el mismo orden. La única diferencia con 0025 es
--  `ve_plata` y los `case` que la usan.
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

    public.ipc_indice_hoy()               as indice_hoy,
    public.ipc_indice_en(v.fecha_ingreso) as indice_ingreso,
    coalesce(public.cotizacion_vigente(cfg.tipo_cambio_preferido), 0) as tipo_cambio,

    dc.dolar as dolar_compra,
    dr.dolar as dolar_referencia,
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
    -- Una sola vez por fila, y no una por cada columna de plata.
    public.puede_administrar(b.agencia_id)                   as ve_plata,
    (b.venta_id is not null)                                 as vendido,
    (b.gastos_vehiculo + b.gastos_finales)                   as gastos_acum,
    (b.precio_compra + b.gastos_vehiculo + b.gastos_finales) as costo_total,
    (coalesce(b.fecha_venta, current_date) - b.fecha_ingreso) as dias_en_stock,
    (b.precio_compra * coalesce(b.dolar_referencia / nullif(b.dolar_compra, 0), 1)
       + b.gastos_vehiculo_ajustados
       + b.gastos_finales)                                   as costo_total_hoy,
    case when b.venta_id is not null then b.precio_final else
      coalesce(b.precio_actual, 0) end                       as precio_referencia
  from base b
)
select
  c.id, c.agencia_id, c.codigo, c.marca, c.modelo, c.anio, c.version, c.km, c.patente,
  c.fecha_compra, c.fecha_ingreso,
  case when c.ve_plata then c.precio_compra end::numeric(16,2) as precio_compra,
  c.precio_objetivo,
  c.observaciones, c.ref_version_id, c.created_at,
  case when c.vendido then 'vendido'::estado_vehiculo else c.estado end as estado,
  c.vendido,
  c.venta_id, c.fecha_venta, c.precio_final,
  c.cantidad_gastos, c.gastos_acum, c.gastos_finales,
  case when c.ve_plata then c.costo_total end as costo_total,
  c.dias_en_stock,
  c.precio_actual,
  c.fecha_precio,
  case when c.ve_plata then
    case when c.vendido then 0::numeric else c.costo_total end
  end as capital_inmovilizado,
  case when c.ve_plata then c.precio_actual - c.costo_total end as ganancia_estimada,
  case when c.ve_plata then
    (c.precio_objetivo - c.costo_total) / nullif(c.precio_objetivo, 0)
  end as margen_esperado,
  case when c.ve_plata then
    (c.precio_actual - c.costo_total) / nullif(c.precio_actual, 0)
  end as margen_actual,
  case when c.ve_plata and c.vendido
       then (c.precio_final - c.costo_total) / nullif(c.precio_final, 0)
       else null::numeric end as margen_real,
  case when c.ve_plata then
    c.costo_total / nullif(1 - c.margen_objetivo, 0)
  end as precio_para_margen_objetivo,
  case when c.ve_plata then
    c.costo_total / nullif(1 - c.margen_minimo, 0)
  end as precio_para_margen_minimo,
  case when c.ve_plata then c.costo_total end as precio_equilibrio,
  case when c.ve_plata then
    ceil(c.costo_total / nullif(1 - c.margen_objetivo, 0) / nullif(c.redondeo, 0)) * c.redondeo
  end as precio_sugerido,
  case when c.ve_plata then
    c.costo_total / nullif(1 - c.margen_objetivo, 0) / nullif(c.precio_actual, 0) - 1
  end as ajuste_necesario,
  c.precio_actual / nullif(c.precio_objetivo, 0) - 1 as var_vs_objetivo,
  case when c.ve_plata then
    c.gastos_acum / nullif(c.precio_compra, 0)
  end as gastos_ratio,
  case when c.ve_plata then
    case when c.dias_en_stock > 0 then c.costo_total / c.dias_en_stock::numeric
         else c.costo_total end
  end as costo_diario,
  c.indice_ingreso,
  c.indice_hoy,
  case when c.ve_plata then c.costo_total_hoy end as costo_total_hoy,
  case when c.ve_plata then
    c.precio_referencia - c.costo_total_hoy
  end as ganancia_real_ipc,
  case when c.ve_plata then
    (c.precio_referencia - c.costo_total_hoy) / nullif(c.precio_referencia, 0)
  end as margen_real_ipc,
  c.tipo_cambio,
  case when c.ve_plata and coalesce(c.dolar_referencia, c.tipo_cambio) > 0
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
  c.dolar_compra,
  c.dolar_referencia,
  case when c.ve_plata and c.dolar_referencia > 0
       then c.costo_total_hoy / c.dolar_referencia end as costo_total_usd,
  c.precio_referencia,
  c.color,
  c.combustible,
  c.transmision,
  c.nro_motor,
  c.nro_chasis,
  c.estado_general
from calc c
left join public.ref_precios rp on rp.version_id = c.ref_version_id and rp.anio = c.anio;

alter view public.v_inventario set (security_invoker = on);

comment on view public.v_inventario is
  'El inventario con todo lo calculado. Las columnas de plata (precio de '
  'compra, costos, márgenes y ganancias) vienen en null para quien no es '
  'dueño ni administrador de esa agencia.';
