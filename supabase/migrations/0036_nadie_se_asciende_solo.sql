-- =====================================================================
--  MI AGENCIA — 0036: nadie se asciende solo
--
--  Con la pizarra, el dueño deja de ser el único que toca las membresías:
--  también las toca el administrador. Y la política que lo permite es una
--  sola regla ("puede_administrar"), que no distingue a quién se le cambia
--  el rol. Así, un administrador podía ascenderse a dueño, o degradar al
--  dueño, con un update desde la API.
--
--  Nunca pasó, pero es la clase de agujero que se descubre cuando ya pasó.
--  Esto lo cierra con dos reglas que se leen solas:
--
--    1. Para poner a alguien de dueño hay que ser dueño (o nosotros).
--    2. Nadie se cambia el rol a sí mismo ni se desactiva solo.
--
--  La segunda también evita el accidente: el dueño que se saca el acceso a
--  sí mismo y deja la agencia sin nadie que pueda volver a entrar.
-- =====================================================================

create or replace function public.proteger_membresias()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_yo       uuid := auth.uid();
  v_soy_dev  boolean := public.es_desarrollador();
  v_soy_dueno boolean;
begin
  --  Sin sesión es la clave de servicio (las Edge Functions, los triggers,
  --  nosotros por la consola): ahí ya se chequeó quién llamaba.
  if v_yo is null or v_soy_dev then
    return new;
  end if;

  select exists (
    select 1 from public.membresias m
     where m.agencia_id = new.agencia_id
       and m.usuario_id = v_yo
       and m.rol = 'owner'
       and m.activa
  ) into v_soy_dueno;

  if new.rol = 'owner' and not v_soy_dueno then
    raise exception 'Solo el dueño puede nombrar a otro dueño.';
  end if;

  if tg_op = 'UPDATE' and old.rol = 'owner' and new.rol <> 'owner'
     and not v_soy_dueno then
    raise exception 'Solo el dueño puede dejar de serlo.';
  end if;

  if tg_op = 'UPDATE' and new.usuario_id = v_yo then
    if new.rol <> old.rol then
      raise exception 'No podés cambiarte el rol a vos mismo.';
    end if;
    if old.activa and not new.activa then
      raise exception 'No podés sacarte el acceso a vos mismo.';
    end if;
  end if;

  return new;
end $$;

comment on function public.proteger_membresias() is
  'Para nombrar a un dueño hay que ser dueño, y nadie se cambia el rol ni '
  'se desactiva a sí mismo.';

drop trigger if exists membresias_protegidas on public.membresias;
create trigger membresias_protegidas
  before insert or update on public.membresias
  for each row execute function public.proteger_membresias();
