-- =====================================================================
--  MI AGENCIA — 0039: la plata, cuando no hay sesión
--
--  La 0034 tapó el precio de compra, los costos y las ganancias para quien
--  no es dueño ni administrador. La regla era `puede_administrar()`, que
--  mira quién está logueado. Correcto para la app, pero deja afuera un caso
--  que no es un usuario: las conexiones sin sesión.
--
--  Son la clave de servicio, nuestras herramientas y las pruebas del
--  esquema, que corren contra un Postgres pelado donde `auth.uid()` es
--  null. Para todas ellas la vista devolvía null en cada columna de plata, y
--  las pruebas del motor —que verifican justamente los números de la
--  ganancia— empezaron a fallar sin que nadie hubiera tocado el cálculo.
--
--  Que sin sesión se vea la plata no abre nada: la vista es
--  `security_invoker`, así que el RLS de `vehiculos` se aplica igual y una
--  conexión anónima no ve ni una fila. Y un usuario logueado siempre tiene
--  `auth.uid()`, así que para el vendedor no cambia nada: sigue sin ver el
--  precio de compra.
-- =====================================================================

create or replace function public.ve_la_plata(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  --  Sin sesión es acceso directo a la base (clave de servicio, psql, las
  --  pruebas): ahí el permiso ya se resolvió antes de llegar hasta acá.
  select auth.uid() is null or public.puede_administrar(p_agencia);
$$;

comment on function public.ve_la_plata(uuid) is
  'Quién ve el precio de compra, los costos y las ganancias: el dueño, el '
  'administrador, y las conexiones sin sesión (clave de servicio y '
  'herramientas), donde el permiso ya se resolvió antes.';

revoke all on function public.ve_la_plata(uuid) from public;
grant execute on function public.ve_la_plata(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  La vista del inventario, con la regla nueva
-- ---------------------------------------------------------------------
--  Entera otra vez porque `create or replace view` exige volver a listar
--  todas las columnas. Lo único distinto con la 0034 es la línea de
--  `ve_plata`.
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
    public.ve_la_plata(b.agencia_id)                         as ve_plata,
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
