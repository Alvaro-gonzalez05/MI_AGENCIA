-- =====================================================================
--  MI AGENCIA — 0013: el semáforo distingue "sin deudas" de "sin consultar"
--
--  El BCRA devuelve 404 para dos casos muy distintos: la persona no existe,
--  o la persona existe y ninguna entidad informó deuda a su nombre. En los
--  dos, `situacion_maxima` queda en null.
--
--  Como estaba, `v_clientes_semaforo` mostraba 'sin_datos' en ambos, o sea
--  lo mismo que si nunca se hubiera consultado. Para el vendedor eso es un
--  error caro: a alguien limpio le aparecía el cartel "Sin consultar" y
--  volvía a consultar el BCRA para llegar de nuevo a la nada.
--
--  Ahora:
--    nunca consultado ....................... sin_datos
--    consultado, cero entidades ............. verde
--    consultado con deuda ................... lo que diga semaforo_de_situacion
--
--  `semaforo_de_situacion` NO cambia: sigue respondiendo solo "qué significa
--  esta situación". Quién fue consultado y quién no es cosa de la vista, que
--  es la única que sabe si hay una consulta detrás.
--
--  Cuidado: esta lógica está replicada en Dart (ConsultaBcra.semaforo, en
--  app/lib/dominio/bcra.dart) porque la app muestra el resultado de una
--  consulta recién hecha antes de releer la vista. Hay un test que ata las
--  dos: tests/semaforo_bcra.mjs. Si se toca una, se toca la otra.
-- =====================================================================

-- Se borra y se rehace en vez de `create or replace`: Postgres no deja
-- agregar columnas en el medio de una vista existente, y las columnas nuevas
-- van al lado de las que acompañan para que el select se lea como los datos
-- de una persona y no como un apilado histórico de parches.
drop view if exists public.v_clientes_semaforo;

create view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       c.dni,
       c.email,
       c.telefono,
       c.localidad,
       c.provincia,
       b.denominacion,
       b.situacion_maxima,
       b.total_deuda_miles,
       b.cantidad_entidades,
       b.cheques_sin_pagar,
       b.tiene_cheques_rechazados,
       b.dias_atraso_max,
       b.tiene_proceso_judicial,
       b.tiene_refinanciaciones,
       b.tiene_situacion_juridica,
       b.en_revision,
       b.periodo,
       b.entidades,
       b.cheques,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                        as consulta_vencida,
       -- Consultado y sin una sola entidad informando: no hay nada en contra.
       (b.consultado_at is not null
        and coalesce(b.cantidad_entidades, 0) = 0)  as sin_deudas_informadas,
       case
         -- Nunca se consultó: no se sabe nada, y decir "apto" sería mentir.
         when b.consultado_at is null
           then 'sin_datos'::semaforo_crediticio
         -- Se consultó y nadie informó deuda.
         when coalesce(b.cantidad_entidades, 0) = 0
           then 'verde'::semaforo_crediticio
         else coalesce(
                public.semaforo_de_situacion(
                  b.situacion_maxima, b.cheques_sin_pagar,
                  b.tiene_cheques_rechazados, b.tiene_proceso_judicial,
                  b.dias_atraso_max),
                'sin_datos'::semaforo_crediticio)
       end                                          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;

-- `create or replace view` conserva los permisos, pero no el security_invoker
-- de una vista recreada con columnas nuevas en algunas versiones. Se vuelve a
-- declarar: sin esto la vista correría con los permisos del dueño y cualquier
-- usuario vería los clientes de todas las agencias.
alter view public.v_clientes_semaforo set (security_invoker = on);

-- Recrear la vista la deja con los permisos de una tabla nueva, y ahi PUBLIC
-- (o sea tambien anon) puede leerla. El RLS de clientes la frenaria igual,
-- pero una vista legible sin sesion no deberia existir en primer lugar.
revoke all on public.v_clientes_semaforo from anon;
grant select on public.v_clientes_semaforo to authenticated;
