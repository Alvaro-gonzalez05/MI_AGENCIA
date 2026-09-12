-- =====================================================================
-- MI AGENCIA — 0003: funciones auxiliares para RLS
--
-- Todas son SECURITY DEFINER a proposito: si una policy de `vehiculos`
-- consultara `membresias` directamente y `membresias` tambien tiene RLS,
-- Postgres entra en recursion infinita. Estas funciones leen con los
-- permisos del owner y cortan esa cadena.
-- =====================================================================

-- ¿El usuario actual es de nuestro equipo (plataforma)?
create or replace function public.es_desarrollador()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.es_desarrollador from public.perfiles p where p.id = auth.uid()),
    false);
$$;

-- Agencias a las que pertenece el usuario actual.
create or replace function public.mis_agencias()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.agencia_id
  from public.membresias m
  where m.usuario_id = auth.uid()
    and m.activa
$$;

-- ¿Tiene el usuario acceso de lectura a esta agencia?
create or replace function public.puede_ver_agencia(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.es_desarrollador()
      or exists (
        select 1 from public.membresias m
        where m.agencia_id = p_agencia
          and m.usuario_id = auth.uid()
          and m.activa);
$$;

-- ¿Tiene alguno de estos roles en la agencia? (el desarrollador siempre si)
create or replace function public.tiene_rol(p_agencia uuid, p_roles rol_membresia[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.es_desarrollador()
      or exists (
        select 1 from public.membresias m
        where m.agencia_id = p_agencia
          and m.usuario_id = auth.uid()
          and m.activa
          and m.rol = any(p_roles));
$$;

-- Atajo: puede escribir datos de negocio (todos menos solo_lectura).
create or replace function public.puede_editar(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.tiene_rol(p_agencia, array['owner','admin','vendedor']::rol_membresia[]);
$$;

-- Atajo: puede tocar configuracion, usuarios y borrar (owner/admin).
create or replace function public.puede_administrar(p_agencia uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.tiene_rol(p_agencia, array['owner','admin']::rol_membresia[]);
$$;

revoke all on function public.es_desarrollador()            from public;
revoke all on function public.mis_agencias()                from public;
revoke all on function public.puede_ver_agencia(uuid)       from public;
revoke all on function public.tiene_rol(uuid, rol_membresia[]) from public;
revoke all on function public.puede_editar(uuid)            from public;
revoke all on function public.puede_administrar(uuid)       from public;

grant execute on function public.es_desarrollador()            to authenticated;
grant execute on function public.mis_agencias()                to authenticated;
grant execute on function public.puede_ver_agencia(uuid)       to authenticated;
grant execute on function public.tiene_rol(uuid, rol_membresia[]) to authenticated;
grant execute on function public.puede_editar(uuid)            to authenticated;
grant execute on function public.puede_administrar(uuid)       to authenticated;
