-- =====================================================================
-- MI AGENCIA — verificación post-instalación
--
-- Pegá esto en el SQL Editor de Supabase DESPUÉS de correr
-- migraciones_completas.sql. Devuelve una sola tabla: si todas las filas
-- dicen OK, la base quedó bien.
-- =====================================================================

with esperado as (
  select * from (values
    ('Tablas',            25),
    ('Vistas',             6),
    ('Políticas RLS',     65),
    ('Meses de IPC',      14),
    ('Cotizaciones',       3)
  ) as t(concepto, cantidad)
),
medido as (
  select 'Tablas' as concepto,
         (select count(*)::int from pg_tables where schemaname = 'public') as cantidad
  union all
  select 'Vistas',
         (select count(*)::int from pg_views where schemaname = 'public')
  union all
  select 'Políticas RLS',
         (select count(*)::int from pg_policies where schemaname = 'public')
  union all
  select 'Meses de IPC',
         (select count(*)::int from public.ipc_serie)
  union all
  select 'Cotizaciones',
         (select count(*)::int from public.cotizaciones)
),
conteos as (
  select e.concepto,
         e.cantidad as esperado,
         r.cantidad as encontrado,
         case when r.cantidad = e.cantidad then 'OK' else 'REVISAR' end as estado
  from esperado e join medido r using (concepto)
),
-- Lo más importante de todo: sin security_invoker, las vistas corren con
-- los permisos de su dueño y le mostrarían el inventario de TODAS las
-- agencias a cualquier usuario logueado.
vistas_inseguras as (
  select count(*)::int as n
  from pg_views v
  where v.schemaname = 'public'
    and v.viewname in ('v_inventario','v_dashboard','v_clientes_semaforo',
                       'v_vehiculo_gastos','v_vehiculo_precio_actual','ref_catalogo')
    and not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v.viewname
        and c.reloptions @> array['security_invoker=on']
    )
),
-- Ninguna tabla de negocio puede quedar sin RLS.
tablas_sin_rls as (
  select count(*)::int as n
  from pg_tables t
  join pg_class c on c.relname = t.tablename
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
  where t.schemaname = 'public' and not c.relrowsecurity
),
-- El índice IPC tiene que estar calculado, no en null.
ipc_calculado as (
  select count(*)::int as n from public.ipc_serie where indice is null
)
select * from conteos
union all
select 'Vistas sin security_invoker', 0, n,
       case when n = 0 then 'OK' else 'PELIGRO: fuga entre agencias' end
  from vistas_inseguras
union all
select 'Tablas sin RLS', 0, n,
       case when n = 0 then 'OK' else 'PELIGRO: tabla desprotegida' end
  from tablas_sin_rls
union all
select 'Meses de IPC sin índice', 0, n,
       case when n = 0 then 'OK' else 'REVISAR: correr recalcular_ipc()' end
  from ipc_calculado
order by 1;
