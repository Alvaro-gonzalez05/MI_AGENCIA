-- La ausencia de información no acredita solvencia. Las alertas tienen prioridad.
create or replace function public.semaforo_de_situacion(
 p_situacion smallint, p_cheques_sin_pagar smallint default 0,
 p_tiene_cheques boolean default false, p_proceso_judicial boolean default false,
 p_dias_atraso smallint default 0)
returns semaforo_crediticio language sql immutable set search_path = public as $$
 select case
   when p_situacion >= 4 or coalesce(p_cheques_sin_pagar,0) > 0
     or coalesce(p_proceso_judicial,false) then 'rojo'::semaforo_crediticio
   when p_situacion in (2,3) or coalesce(p_tiene_cheques,false)
     or coalesce(p_dias_atraso,0) > 30 then 'amarillo'::semaforo_crediticio
   when p_situacion = 1 then 'verde'::semaforo_crediticio
   else 'sin_datos'::semaforo_crediticio end;
$$;
create or replace view public.v_clientes_semaforo as
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
       case when b.consultado_at is null or b.expira_at < now()
         then 'sin_datos'::semaforo_crediticio
         else public.semaforo_de_situacion(b.situacion_maxima, b.cheques_sin_pagar,
           b.tiene_cheques_rechazados, b.tiene_proceso_judicial, b.dias_atraso_max)
       end                                          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.cuit = c.cuit and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;
