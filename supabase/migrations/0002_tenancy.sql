-- =====================================================================
-- MI AGENCIA — 0002: multi-tenant (agencias, perfiles, membresias)
-- =====================================================================

-- Cada agencia es un inquilino aislado. Todo dato de negocio cuelga de aca.
create table if not exists public.agencias (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  slug            citext not null unique,
  cuit            text,
  email_contacto  citext,
  telefono        text,
  direccion       text,
  localidad       text,
  provincia       text,
  logo_url        text,
  -- La cuenta de desarrollador da de alta agencias y puede suspenderlas.
  activa          boolean not null default true,
  plan            text not null default 'basico',
  -- Hasta cuando esta paga. null = sin vencimiento.
  vigente_hasta   date,
  creada_por      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.agencias is 'Inquilinos (tenants). Una fila por agencia de autos cliente.';

-- Espejo de auth.users con los datos que la app necesita mostrar.
create table if not exists public.perfiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  nombre           text,
  apellido         text,
  email            citext not null,
  telefono         text,
  avatar_url       text,
  -- Rol de PLATAFORMA: nosotros. Permite crear agencias y ver todo.
  -- No se puede setear desde el cliente (ver policies en 0009).
  es_desarrollador boolean not null default false,
  ultima_sesion    timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on column public.perfiles.es_desarrollador is
  'Superusuario de plataforma. Solo se cambia con service_role o SQL directo, nunca desde la app.';

-- Un usuario puede pertenecer a varias agencias (gestor con varias sucursales).
create table if not exists public.membresias (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  usuario_id  uuid not null references auth.users(id) on delete cascade,
  rol         rol_membresia not null default 'vendedor',
  activa      boolean not null default true,
  invitado_por uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (agencia_id, usuario_id)
);
create index if not exists idx_membresias_usuario on public.membresias(usuario_id) where activa;
create index if not exists idx_membresias_agencia on public.membresias(agencia_id) where activa;

-- Invitaciones pendientes: el owner invita por email antes de que exista el usuario.
create table if not exists public.invitaciones (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  email       citext not null,
  rol         rol_membresia not null default 'vendedor',
  token       text not null unique default encode(gen_random_bytes(24),'hex'),
  expira_at   timestamptz not null default now() + interval '7 days',
  aceptada_at timestamptz,
  invitado_por uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_invitaciones_email on public.invitaciones(email) where aceptada_at is null;

-- Al registrarse un usuario en auth, se crea su perfil automaticamente.
create or replace function public.handle_nuevo_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.perfiles (id, email, nombre, apellido)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'apellido'
  )
  on conflict (id) do nothing;

  -- Si fue invitado, se convierte la invitacion vigente en membresia.
  insert into public.membresias (agencia_id, usuario_id, rol, invitado_por)
  select i.agencia_id, new.id, i.rol, i.invitado_por
  from public.invitaciones i
  where i.email = new.email
    and i.aceptada_at is null
    and i.expira_at > now()
  on conflict (agencia_id, usuario_id) do nothing;

  update public.invitaciones
     set aceptada_at = now()
   where email = new.email and aceptada_at is null and expira_at > now();

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_nuevo_usuario();

-- updated_at automatico, reutilizado por todas las tablas.
create or replace function public.tocar_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_agencias_updated on public.agencias;
create trigger trg_agencias_updated before update on public.agencias
  for each row execute function public.tocar_updated_at();

drop trigger if exists trg_perfiles_updated on public.perfiles;
create trigger trg_perfiles_updated before update on public.perfiles
  for each row execute function public.tocar_updated_at();
