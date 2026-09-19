-- =====================================================================
--  MI AGENCIA — 0017: el semáforo mira los últimos 24 meses, no solo hoy
--
--  Checklist del cliente, punto 3.1 (crítico): una persona que en la web
--  del BCRA figura con deudas salía en la app como "sin deudas informadas".
--
--  La causa: el BCRA tiene tres consultas y la app usaba dos.
--
--    /Deudas/{cuit}              solo el último período informado
--    /Deudas/Historicas/{cuit}   los últimos 24 meses          <- faltaba
--    /Deudas/ChequesRechazados   cheques
--
--  La persona del reclamo estuvo en situación 5 (irrecuperable) de agosto a
--  diciembre de 2024 y en situación 4 hasta marzo de 2025. Desde abril de
--  2025 figura sin deuda, así que /Deudas contesta "no se encontraron
--  datos" y la app lo leía como limpio. La web oficial muestra los 24 meses,
--  y ahí se ve todo.
--
--  Para decidir si financiar, eso importa tanto como el presente: alguien
--  que fue irrecuperable hace año y medio no es alguien sin historial.
--
--  Criterio nuevo, aplicado sobre el criterio anterior (0015), que no cambia:
--
--    ROJO      situación 4 o peor en los últimos 12 meses, aunque hoy esté
--              al día.
--    AMARILLO  situación 3 o peor en los últimos 24 meses.
--    VERDE     también si hoy no tiene deuda pero tiene historial y en los
--              24 meses nunca pasó de situación 2: pagó y cerró.
--
--  Las ventanas se cuentan desde el último período que informó el BCRA, no
--  desde hoy: el BCRA publica con unos dos meses de atraso, y contar desde
--  hoy acortaría la ventana sin que nadie lo note.
--
--  Esta lógica está replicada en Dart (ConsultaBcra.semaforo) y las dos
--  corren los mismos casos desde tests/casos_semaforo.json.
-- =====================================================================

alter table public.bcra_consultas
  add column if not exists situacion_max_12m smallint,
  add column if not exists situacion_max_24m smallint,
  -- Último mes con situación 2 o peor. Es lo que permite decir "al día
  -- desde abril de 2025" en vez de solo "tuvo problemas".
  add column if not exists ultimo_periodo_irregular text,
  -- Un renglón por mes: [{periodo: "202607", situacion: 0}, ...], del más
  -- nuevo al más viejo. 0 es "sin deuda ese mes". Alcanza para dibujar la
  -- línea de tiempo sin volver a abrir el payload crudo.
  add column if not exists historico jsonb,
  add column if not exists payload_historico jsonb;

comment on column public.bcra_consultas.situacion_max_24m is
  'Peor situación (1-6) en los 24 meses de /Deudas/Historicas. Null si no hubo deuda en ese lapso.';

-- ---------------------------------------------------------------------
-- El semáforo con historial.
--
-- Nombre nuevo en vez de sumarle parámetros a semaforo_de_situacion: con
-- parámetros opcionales, Postgres vería dos funciones que aceptan la misma
-- llamada de cinco argumentos y tiraría "function is not unique".
-- ---------------------------------------------------------------------
create or replace function public.semaforo_con_historial(
  p_situacion         smallint,
  p_cheques_sin_pagar smallint default 0,
  p_tiene_cheques     boolean  default false,
  p_proceso_judicial  boolean  default false,
  p_dias_atraso       smallint default 0,
  p_max_12m           smallint default null,
  p_max_24m           smallint default null)
returns semaforo_crediticio
language sql immutable
set search_path = public
as $$
  select case
    when coalesce(p_situacion, 0) >= 4
      or coalesce(p_cheques_sin_pagar, 0) > 0
      or coalesce(p_proceso_judicial, false)
      or coalesce(p_max_12m, 0) >= 4                  then 'rojo'::semaforo_crediticio
    when p_situacion in (2, 3)
      or coalesce(p_tiene_cheques, false)
      or coalesce(p_dias_atraso, 0) > 30
      or coalesce(p_max_24m, 0) >= 3                  then 'amarillo'::semaforo_crediticio
    when p_situacion = 1
      or (p_situacion is null and p_max_24m in (1, 2)) then 'verde'::semaforo_crediticio
    else 'sin_datos'::semaforo_crediticio
  end;
$$;

revoke all on function public.semaforo_con_historial(
  smallint, smallint, boolean, boolean, smallint, smallint, smallint) from public, anon;
grant execute on function public.semaforo_con_historial(
  smallint, smallint, boolean, boolean, smallint, smallint, smallint) to authenticated;

-- ---------------------------------------------------------------------
-- La vista, ahora con el historial.
-- ---------------------------------------------------------------------
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
       b.situacion_max_12m,
       b.situacion_max_24m,
       b.ultimo_periodo_irregular,
       b.historico,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                         as consulta_vencida,
       -- Sin deudas de verdad: nada hoy Y nada en 24 meses. Antes bastaba
       -- con que hoy no hubiera nada, y eso es justo lo que falló.
       (b.consultado_at is not null
        and coalesce(b.cantidad_entidades, 0) = 0
        and coalesce(jsonb_array_length(b.historico), 0) = 0) as sin_deudas_informadas,
       case when b.consultado_at is null or b.expira_at < now()
         then 'sin_datos'::semaforo_crediticio
         else public.semaforo_con_historial(
           b.situacion_maxima, b.cheques_sin_pagar, b.tiene_cheques_rechazados,
           b.tiene_proceso_judicial, b.dias_atraso_max,
           b.situacion_max_12m, b.situacion_max_24m)
       end                                           as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.cuit = c.cuit and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;

alter view public.v_clientes_semaforo set (security_invoker = on);
revoke all on public.v_clientes_semaforo from anon;
grant select on public.v_clientes_semaforo to authenticated;

-- ---------------------------------------------------------------------
-- Las consultas hechas antes de este cambio no traen historial, y alguna
-- puede estar diciendo "sin deudas" de alguien que tuvo. Se dan por
-- vencidas: la app las muestra como "sin consultar" y la próxima consulta
-- trae los 24 meses. Mejor pedir una consulta de más que dejar en pie un
-- resultado que ya sabemos que puede estar mal.
-- ---------------------------------------------------------------------
update public.bcra_consultas
   set expira_at = now()
 where historico is null
   and expira_at > now();
