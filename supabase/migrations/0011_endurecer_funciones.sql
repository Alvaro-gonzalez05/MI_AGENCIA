-- =====================================================================
-- MI AGENCIA — 0011: endurecimiento de funciones
--
-- Sale de correr el linter de seguridad de Supabase contra la base real.
-- Todos los bucles excluyen lo que pertenece a una extension (citext,
-- pg_trgm, unaccent, pgcrypto): esas funciones son de la extension, no
-- nuestras, y no somos duenos para alterarlas.
-- =====================================================================

create or replace function pg_temp.funciones_propias()
returns setof regprocedure language sql as $fn$
  select p.oid::regprocedure
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (
      select 1 from pg_depend d
      where d.objid = p.oid and d.deptype = 'e')
$fn$;

-- 1. search_path fijo en toda funcion propia.
--
-- Sin esto, una funcion resuelve los nombres de tabla con el search_path de
-- quien la llama. En una SECURITY DEFINER eso permite que alguien cree un
-- objeto homonimo en un esquema propio y logre que la funcion, corriendo con
-- permisos elevados, opere sobre SU objeto.
do $$
declare f regprocedure;
begin
  for f in
    select x from pg_temp.funciones_propias() x
    join pg_proc p on p.oid = x
    where p.prokind = 'f'
      and (p.proconfig is null
           or not exists (select 1 from unnest(p.proconfig) c
                           where c like 'search\_path=%'))
  loop
    execute format('alter function %s set search_path = public', f);
  end loop;
end $$;

-- 2. Nadie sin sesion ejecuta funciones nuestras.
--
-- Supabase da EXECUTE por defecto a anon y authenticated sobre todo lo creado
-- en public, asi que quedaban publicadas como RPC en /rest/v1/rpc/...
-- Ninguna filtraba datos (con anon, es_desarrollador() da false y
-- mis_agencias() viene vacia), pero no hay razon para exponerlas.
do $$
declare f regprocedure;
begin
  for f in select x from pg_temp.funciones_propias() x loop
    execute format('revoke all on function %s from anon, public', f);
  end loop;
end $$;

-- 3. Las funciones de trigger no las llama nadie a mano.
--
-- Las invoca Postgres al disparar el trigger. registrar_auditoria() o
-- handle_nuevo_usuario() no tienen por que ser alcanzables desde la API.
do $$
declare f regprocedure;
begin
  for f in
    select x from pg_temp.funciones_propias() x
    join pg_proc p on p.oid = x
    where p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke all on function %s from anon, authenticated, public', f);
  end loop;
end $$;

-- 4. Devolver el permiso a lo que SI tiene que poder llamar la app.
--
-- Las funciones de RLS son imprescindibles: las policies las evaluan con el
-- rol que consulta, asi que sin EXECUTE el usuario no podria leer ni sus
-- propios datos. El linter las sigue marcando como "ejecutables por usuarios
-- logueados", y es correcto que lo esten: ninguna devuelve datos ajenos
-- (es_desarrollador() responde por el que llama, mis_agencias() lista las
-- suyas, puede_ver_agencia() responde sobre su propio acceso).
grant execute on function public.es_desarrollador()               to authenticated;
grant execute on function public.mis_agencias()                   to authenticated;
grant execute on function public.puede_ver_agencia(uuid)          to authenticated;
grant execute on function public.tiene_rol(uuid, rol_membresia[]) to authenticated;
grant execute on function public.puede_editar(uuid)               to authenticated;
grant execute on function public.puede_administrar(uuid)          to authenticated;

-- Lectura que la app consume o va a consumir.
grant execute on function public.ipc_indice_en(date)                 to authenticated;
grant execute on function public.ipc_indice_hoy()                    to authenticated;
grant execute on function public.cotizacion_vigente(tipo_cotizacion) to authenticated;
grant execute on function public.siguiente_codigo_vehiculo(uuid)     to authenticated;
grant execute on function public.diagnostico_vehiculo(uuid)          to authenticated;
grant execute on function public.evolucion_mensual(uuid, int)        to authenticated;
grant execute on function
  public.semaforo_de_situacion(smallint, smallint, boolean, boolean, smallint)
  to authenticated;
