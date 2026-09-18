-- Borra una ficha de interés sin dejar datos personales aislados.
-- Un vendedor con permiso de edición puede hacerlo; si el cliente aparece en
-- otra oportunidad, su ficha y su historial BCRA se conservan.
create or replace function public.eliminar_interesado(p_oportunidad uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agencia uuid;
  v_cliente uuid;
  v_cliente_eliminado boolean := false;
begin
  select agencia_id, cliente_id
    into v_agencia, v_cliente
    from public.oportunidades
   where id = p_oportunidad
   for update;

  if v_agencia is null then
    raise exception 'El interesado ya no existe.';
  end if;
  if auth.uid() is null or not public.puede_editar(v_agencia) then
    raise exception 'No tenés permiso para borrar interesados en esta agencia.';
  end if;

  -- Bloquea la ficha para que dos borrados simultáneos no tomen decisiones
  -- distintas sobre el último interés de la misma persona.
  perform 1 from public.clientes where id = v_cliente for update;
  delete from public.oportunidades where id = p_oportunidad;

  if not exists (
    select 1 from public.oportunidades where cliente_id = v_cliente
  ) then
    delete from public.clientes where id = v_cliente and agencia_id = v_agencia;
    v_cliente_eliminado := found;
  end if;

  return v_cliente_eliminado;
end;
$$;

revoke all on function public.eliminar_interesado(uuid) from public, anon;
grant execute on function public.eliminar_interesado(uuid) to authenticated;

-- Ruta: {agencia}/{cliente}/{oportunidad}/{archivo}.pdf. Se borra antes que
-- la fila porque puede_acceder_informe comprueba que la oportunidad exista.
drop policy if exists informes_borrar on storage.objects;
create policy informes_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'informes' and public.puede_acceder_informe(name, true));
