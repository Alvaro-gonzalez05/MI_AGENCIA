-- =====================================================================
--  MI AGENCIA — 0035: las zonas de la agencia y la pizarra de usuarios
--
--  Hasta ahora la gente de una agencia era una lista plana de membresías.
--  En el salón no se trabaja así: hay quien atiende, quien factura, quien
--  maneja las redes y quien arregla los autos. La pizarra del diseño muestra
--  esa foto —el dueño en el medio y las áreas colgando— y para eso hace
--  falta guardar dos cosas: las áreas, y dónde las puso cada agencia en el
--  tablero.
--
--  Lo que NO hace esta migración, a propósito: las zonas no dan ni quitan
--  permisos. Lo que se puede ver y tocar lo sigue definiendo el rol de la
--  membresía (owner, admin, vendedor, solo_lectura). Una zona llamada
--  "Administración" no habilita nada; es para ordenar y para que se entienda
--  de un vistazo quién es quién. Si alguna vez las zonas tuvieran que mandar
--  permisos, eso es un sistema nuevo y se piensa aparte.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Las zonas
-- ---------------------------------------------------------------------
create table if not exists public.zonas (
  id         uuid primary key default gen_random_uuid(),
  agencia_id uuid not null references public.agencias(id) on delete cascade,
  nombre     text not null,
  --  El nombre del icono tal cual lo dibuja la app. Se guarda el nombre y no
  --  el dibujo para poder cambiar la biblioteca de iconos sin migrar datos.
  icono      text not null default 'folder',
  --  Dónde quedó en la pizarra. Es de la agencia y no de cada usuario: es un
  --  tablero de la oficina, no un escritorio personal, así que el dueño lo
  --  acomoda una vez y todos lo ven igual.
  x          integer not null default 0,
  y          integer not null default 0,
  creada_el  timestamptz not null default now()
);

--  Dos zonas con el mismo nombre en la misma agencia son un error de carga,
--  no dos zonas.
create unique index if not exists zonas_nombre_unico
  on public.zonas (agencia_id, lower(nombre));

create index if not exists zonas_por_agencia on public.zonas (agencia_id);

-- ---------------------------------------------------------------------
--  A qué zona pertenece cada persona
-- ---------------------------------------------------------------------
--  `on delete set null`: borrar una zona no puede dejar a nadie sin acceso.
--  La gente cae a "sin zona" y se la vuelve a repartir. Perder la cuenta de
--  un empleado porque se renombró un área sería el peor error posible.
alter table public.membresias
  add column if not exists zona_id uuid
    references public.zonas(id) on delete set null;

create index if not exists membresias_por_zona on public.membresias (zona_id);

-- ---------------------------------------------------------------------
--  Quién puede ver y tocar las zonas
-- ---------------------------------------------------------------------
alter table public.zonas enable row level security;

drop policy if exists zonas_select on public.zonas;
create policy zonas_select on public.zonas
  for select to authenticated
  using (public.puede_ver_agencia(agencia_id));

--  Acomodar la pizarra y crear o borrar áreas es del dueño y del
--  administrador. El vendedor la ve, no la reordena.
drop policy if exists zonas_insert on public.zonas;
create policy zonas_insert on public.zonas
  for insert to authenticated
  with check (public.puede_administrar(agencia_id));

drop policy if exists zonas_update on public.zonas;
create policy zonas_update on public.zonas
  for update to authenticated
  using (public.puede_administrar(agencia_id))
  with check (public.puede_administrar(agencia_id));

drop policy if exists zonas_delete on public.zonas;
create policy zonas_delete on public.zonas
  for delete to authenticated
  using (public.puede_administrar(agencia_id));

-- ---------------------------------------------------------------------
--  La pizarra, servida de una
-- ---------------------------------------------------------------------
--  Una sola consulta devuelve a toda la gente de la agencia con su rol, su
--  zona y si está activa. Sin esto la app pediría membresías, después
--  perfiles y después zonas, y dibujaría la pizarra de a pedazos.
create or replace view public.v_equipo as
select
  m.id              as membresia_id,
  m.agencia_id,
  m.usuario_id,
  m.rol,
  m.activa,
  m.created_at      as desde,
  m.zona_id,
  z.nombre          as zona_nombre,
  z.icono           as zona_icono,
  p.nombre,
  p.apellido,
  p.email,
  p.ultima_sesion,
  --  El dato que la pizarra pinta con la monedita: quién ve el precio de
  --  compra y la ganancia. Se calcula acá para que la app no vuelva a
  --  escribir la misma regla.
  (m.rol in ('owner', 'admin')) as ve_plata
from public.membresias m
join public.perfiles p on p.id = m.usuario_id
left join public.zonas z on z.id = m.zona_id
where public.puede_ver_agencia(m.agencia_id);

alter view public.v_equipo set (security_invoker = on);

comment on view public.v_equipo is
  'La gente de la agencia con su rol, su zona y si sigue entrando. Es lo '
  'que dibuja la pizarra de usuarios.';

-- ---------------------------------------------------------------------
--  Mover gente de zona
-- ---------------------------------------------------------------------
--  Arrastrar una tarjeta en la pizarra es un update sobre `membresias`, y
--  esa tabla no deja que cualquiera la toque. Esta función corre con los
--  permisos del dueño de la base pero chequea primero: sólo un
--  administrador de ESA agencia puede mover a alguien, y sólo dentro de
--  ella. Sin el chequeo, cualquiera con la anon key movería gente de
--  cualquier agencia.
create or replace function public.mover_a_zona(
  p_membresia uuid,
  p_zona      uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agencia uuid;
begin
  select agencia_id into v_agencia
    from public.membresias where id = p_membresia;

  if v_agencia is null then
    raise exception 'Esa persona no existe en el equipo.';
  end if;

  if not public.puede_administrar(v_agencia) then
    raise exception 'Solo el dueño o un administrador pueden mover gente.';
  end if;

  --  La zona tiene que ser de la misma agencia: si no, se podría mandar
  --  gente a la pizarra de otro cliente.
  if p_zona is not null and not exists (
    select 1 from public.zonas z
     where z.id = p_zona and z.agencia_id = v_agencia
  ) then
    raise exception 'Esa zona no es de esta agencia.';
  end if;

  update public.membresias set zona_id = p_zona where id = p_membresia;
end $$;

revoke all on function public.mover_a_zona(uuid, uuid) from public;
grant execute on function public.mover_a_zona(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
--  Las cuatro zonas con las que arranca una agencia
-- ---------------------------------------------------------------------
--  Son una sugerencia, no una regla: se borran y se crean otras. Pero una
--  pizarra vacía no se entiende, y nadie sabe qué va a poner hasta que ve
--  un ejemplo.
create or replace function public.zonas_iniciales()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.zonas (agencia_id, nombre, icono, x, y) values
    (new.id, 'Administración', 'calculator',    20,  20),
    (new.id, 'Ventas',         'car',          684,  20),
    (new.id, 'Marketing',      'speakerphone', 684, 320),
    (new.id, 'Taller',         'tool',          20, 320);
  return new;
end $$;

drop trigger if exists agencias_con_zonas on public.agencias;
create trigger agencias_con_zonas
  after insert on public.agencias
  for each row execute function public.zonas_iniciales();

--  Las agencias que ya existen también arrancan con sus cuatro.
insert into public.zonas (agencia_id, nombre, icono, x, y)
select a.id, z.nombre, z.icono, z.x, z.y
  from public.agencias a
 cross join (values
   ('Administración', 'calculator',    20,  20),
   ('Ventas',         'car',          684,  20),
   ('Marketing',      'speakerphone', 684, 320),
   ('Taller',         'tool',          20, 320)
 ) as z(nombre, icono, x, y)
 where not exists (
   select 1 from public.zonas existente where existente.agencia_id = a.id
 );
