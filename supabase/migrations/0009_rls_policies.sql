-- =====================================================================
-- MI AGENCIA — 0009: Row Level Security
--
-- Regla del proyecto: NINGUNA tabla queda sin RLS. El aislamiento entre
-- agencias se garantiza en la base, no en la app. Si manana alguien se
-- lleva la anon key (que es publica por diseno) igual no puede leer los
-- datos de otra agencia.
-- =====================================================================

-- CRITICO: por defecto una vista corre con los permisos de su DUEÑO, lo
-- que saltearia el RLS de las tablas que consulta. security_invoker hace
-- que corra con los permisos de QUIEN la consulta. Sin esto, v_inventario
-- filtraria el inventario de todas las agencias a cualquier usuario.
alter view public.v_inventario              set (security_invoker = on);
alter view public.v_dashboard               set (security_invoker = on);
alter view public.v_vehiculo_gastos         set (security_invoker = on);
alter view public.v_vehiculo_precio_actual  set (security_invoker = on);
alter view public.v_clientes_semaforo       set (security_invoker = on);
alter view public.ref_catalogo              set (security_invoker = on);

alter table public.agencias             enable row level security;
alter table public.perfiles             enable row level security;
alter table public.membresias           enable row level security;
alter table public.invitaciones         enable row level security;
alter table public.agencia_config       enable row level security;
alter table public.vehiculos            enable row level security;
alter table public.vehiculo_fotos       enable row level security;
alter table public.gastos               enable row level security;
alter table public.cambios_precio       enable row level security;
alter table public.ventas               enable row level security;
alter table public.clientes             enable row level security;
alter table public.oportunidades        enable row level security;
alter table public.interacciones        enable row level security;
alter table public.bcra_consultas       enable row level security;
alter table public.campanas             enable row level security;
alter table public.campana_destinatarios enable row level security;
alter table public.plantillas_email     enable row level security;
alter table public.auditoria            enable row level security;
alter table public.ref_marcas           enable row level security;
alter table public.ref_modelos          enable row level security;
alter table public.ref_versiones        enable row level security;
alter table public.ref_precios          enable row level security;
alter table public.ref_sync_log         enable row level security;
alter table public.ipc_serie            enable row level security;
alter table public.cotizaciones         enable row level security;

-- =====================================================================
-- AGENCIAS
-- =====================================================================
drop policy if exists agencias_select on public.agencias;
create policy agencias_select on public.agencias for select to authenticated
  using (public.puede_ver_agencia(id));

-- Solo nosotros damos de alta agencias. Es el nucleo del modelo de negocio:
-- el cliente no puede autocrearse una agencia desde la app.
drop policy if exists agencias_insert on public.agencias;
create policy agencias_insert on public.agencias for insert to authenticated
  with check (public.es_desarrollador());

-- El owner puede editar los datos de SU agencia (logo, direccion...),
-- pero activa/plan/vigente_hasta solo los toca el desarrollador: eso se
-- refuerza con un trigger, porque RLS no distingue por columna.
drop policy if exists agencias_update on public.agencias;
create policy agencias_update on public.agencias for update to authenticated
  using (public.tiene_rol(id, array['owner']::rol_membresia[]))
  with check (public.tiene_rol(id, array['owner']::rol_membresia[]));

drop policy if exists agencias_delete on public.agencias;
create policy agencias_delete on public.agencias for delete to authenticated
  using (public.es_desarrollador());

-- Blinda los campos comerciales: aunque el owner pase el RLS del update,
-- no puede darse a si mismo un plan mejor ni extender su vencimiento.
create or replace function public.proteger_campos_comerciales()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if not public.es_desarrollador() then
    new.activa        := old.activa;
    new.plan          := old.plan;
    new.vigente_hasta := old.vigente_hasta;
    new.slug          := old.slug;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_proteger_agencia on public.agencias;
create trigger trg_proteger_agencia before update on public.agencias
  for each row execute function public.proteger_campos_comerciales();

-- =====================================================================
-- PERFILES
-- =====================================================================
drop policy if exists perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles for select to authenticated
  using (
    id = auth.uid()
    or public.es_desarrollador()
    -- Tambien veo a mis companeros de agencia (para asignar oportunidades).
    or exists (
      select 1 from public.membresias m
      where m.usuario_id = perfiles.id
        and m.agencia_id in (select public.mis_agencias()))
  );

drop policy if exists perfiles_update on public.perfiles;
create policy perfiles_update on public.perfiles for update to authenticated
  using (id = auth.uid() or public.es_desarrollador())
  with check (id = auth.uid() or public.es_desarrollador());

-- Nadie se autoasciende a desarrollador desde la app.
create or replace function public.proteger_flag_desarrollador()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if not public.es_desarrollador() then
    new.es_desarrollador := old.es_desarrollador;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_proteger_perfil on public.perfiles;
create trigger trg_proteger_perfil before update on public.perfiles
  for each row execute function public.proteger_flag_desarrollador();

-- =====================================================================
-- MEMBRESIAS e INVITACIONES
-- =====================================================================
drop policy if exists membresias_select on public.membresias;
create policy membresias_select on public.membresias for select to authenticated
  using (usuario_id = auth.uid() or public.puede_ver_agencia(agencia_id));

drop policy if exists membresias_escritura on public.membresias;
create policy membresias_escritura on public.membresias for all to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

drop policy if exists invitaciones_todo on public.invitaciones;
create policy invitaciones_todo on public.invitaciones for all to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

-- =====================================================================
-- CONFIGURACION
-- =====================================================================
drop policy if exists config_select on public.agencia_config;
create policy config_select on public.agencia_config for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

drop policy if exists config_update on public.agencia_config;
create policy config_update on public.agencia_config for update to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

-- =====================================================================
-- DATOS DE NEGOCIO
-- Patron comun: leen todos los miembros, escriben los que no son
-- solo_lectura, y borra unicamente owner/admin.
-- =====================================================================
do $$
declare
  t text;
  tablas text[] := array[
    'vehiculos','vehiculo_fotos','gastos','cambios_precio','ventas',
    'clientes','oportunidades','interacciones','bcra_consultas',
    'campanas','plantillas_email'];
begin
  foreach t in array tablas loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format($f$create policy %I on public.%I for select to authenticated
                      using (public.puede_ver_agencia(agencia_id))$f$, t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format($f$create policy %I on public.%I for insert to authenticated
                      with check (public.puede_editar(agencia_id))$f$, t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format($f$create policy %I on public.%I for update to authenticated
                      using (public.puede_editar(agencia_id))
                      with check (public.puede_editar(agencia_id))$f$, t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format($f$create policy %I on public.%I for delete to authenticated
                      using (public.puede_administrar(agencia_id))$f$, t || '_delete', t);
  end loop;
end $$;

-- Destinatarios de campana: no tienen agencia_id propio, se resuelve por
-- la campana a la que pertenecen.
drop policy if exists destinatarios_select on public.campana_destinatarios;
create policy destinatarios_select on public.campana_destinatarios for select to authenticated
  using (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_ver_agencia(c.agencia_id)));

drop policy if exists destinatarios_escritura on public.campana_destinatarios;
create policy destinatarios_escritura on public.campana_destinatarios for all to authenticated
  using (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_editar(c.agencia_id)))
  with check (exists (select 1 from public.campanas c
                  where c.id = campana_id and public.puede_editar(c.agencia_id)));

-- =====================================================================
-- AUDITORIA — se lee, no se escribe ni se corrige. Solo owner/admin.
-- Los inserts los hace el trigger, que es security definer y no pasa por RLS.
-- =====================================================================
drop policy if exists auditoria_select on public.auditoria;
create policy auditoria_select on public.auditoria for select to authenticated
  using (public.puede_administrar(agencia_id));

-- =====================================================================
-- DATOS DE REFERENCIA — los lee cualquier usuario logueado (son publicos:
-- IPC del INDEC, dolar, catalogo de precios). Los escribe solo el backend
-- con service_role, que no pasa por RLS: por eso no hay policy de insert.
-- =====================================================================
do $$
declare
  t text;
begin
  foreach t in array array['ref_marcas','ref_modelos','ref_versiones','ref_precios',
                           'ref_sync_log','ipc_serie','cotizaciones'] loop
    execute format('drop policy if exists %I on public.%I', t || '_lectura', t);
    execute format($f$create policy %I on public.%I for select to authenticated
                      using (true)$f$, t || '_lectura', t);
  end loop;
end $$;

-- =====================================================================
-- STORAGE — fotos de vehiculos.
-- Convencion de ruta: {agencia_id}/{vehiculo_id}/{archivo}
-- El primer segmento de la ruta es el que decide quien ve que.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vehiculos', 'vehiculos', false, 10485760,
        array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;

drop policy if exists fotos_ver on storage.objects;
create policy fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'vehiculos'
         and public.puede_ver_agencia((storage.foldername(name))[1]::uuid));

drop policy if exists fotos_subir on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'vehiculos'
              and public.puede_editar((storage.foldername(name))[1]::uuid));

drop policy if exists fotos_borrar on storage.objects;
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'vehiculos'
         and public.puede_editar((storage.foldername(name))[1]::uuid));

-- =====================================================================
-- GRANTS: el rol anon no toca NADA. Todo exige sesion iniciada.
-- =====================================================================
revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on public.v_inventario, public.v_dashboard, public.v_clientes_semaforo,
                public.ref_catalogo to authenticated;
grant usage, select on all sequences in schema public to authenticated;
