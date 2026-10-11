-- =====================================================================
--  MI AGENCIA — 0033: marca y modelo escritos siempre igual
--
--  La guía de precios encuentra por texto exacto, así que la misma unidad
--  escrita de tres formas da tres resultados distintos: "VW", "Volkswagen"
--  y "volkswagen " (con espacio al final) son el mismo auto para una
--  persona y tres autos para un buscador.
--
--  Esto normaliza lo que se guarda: saca espacios de más, pone cada palabra
--  con mayúscula inicial y traduce las abreviaturas que usa la agencia a la
--  marca como la escribe la guía. No cambia lo que el usuario ve escribir:
--  corrige al guardar, que es cuando importa.
--
--  Se aplica también a lo que ya está cargado.
-- =====================================================================

-- ---------------------------------------------------------------------
--  Las abreviaturas de siempre
-- ---------------------------------------------------------------------
--  Es una tabla y no un `case` adentro de la función para poder agregar la
--  próxima sin tocar código: cada agencia escribe distinto.
create table if not exists public.ref_alias_marcas (
  alias  text primary key,
  marca  text not null
);

insert into public.ref_alias_marcas (alias, marca) values
  ('vw',           'Volkswagen'),
  ('volks',        'Volkswagen'),
  ('chevy',        'Chevrolet'),
  ('chevrolett',   'Chevrolet'),
  ('mercedes',     'Mercedes Benz'),
  ('mercedes-benz','Mercedes Benz'),
  ('mb',           'Mercedes Benz'),
  ('citroen',      'Citroën'),
  ('vocho',        'Volkswagen'),
  ('toyot',        'Toyota'),
  ('peugot',       'Peugeot'),
  ('peugueot',     'Peugeot'),
  ('renoult',      'Renault'),
  ('reno',         'Renault')
on conflict (alias) do update set marca = excluded.marca;

alter table public.ref_alias_marcas enable row level security;

drop policy if exists ref_alias_marcas_select on public.ref_alias_marcas;
create policy ref_alias_marcas_select on public.ref_alias_marcas
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
--  Normalizar un texto suelto
-- ---------------------------------------------------------------------
create or replace function public.normalizar_nombre(p_texto text)
returns text
language sql
immutable
as $$
  select nullif(
    initcap(
      trim(both ' ' from
        regexp_replace(
          -- Espacios de más, tabulaciones y saltos de línea pegados de un
          -- Excel: todo a un solo espacio.
          regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g'),
          '^\s+|\s+$', '', 'g')
      )
    ),
  '');
$$;

comment on function public.normalizar_nombre(text) is
  'Un espacio entre palabras y mayúscula inicial. "  ford  RANGER " queda '
  '"Ford Ranger".';

create or replace function public.normalizar_marca(p_marca text)
returns text
language sql
stable
as $$
  select coalesce(
    (select a.marca
       from public.ref_alias_marcas a
      where a.alias = lower(trim(both ' ' from coalesce(p_marca, '')))),
    public.normalizar_nombre(p_marca)
  );
$$;

-- ---------------------------------------------------------------------
--  Al guardar una unidad
-- ---------------------------------------------------------------------
create or replace function public.normalizar_vehiculo()
returns trigger
language plpgsql
as $$
begin
  new.marca   := public.normalizar_marca(new.marca);
  new.modelo  := public.normalizar_nombre(new.modelo);
  new.version := public.normalizar_nombre(new.version);
  new.color   := public.normalizar_nombre(new.color);

  -- La patente siempre en mayúsculas y sin espacios ni guiones: así dos
  -- cargas de la misma patente son la misma patente.
  if new.patente is not null then
    new.patente := nullif(
      upper(regexp_replace(new.patente, '[^a-zA-Z0-9]', '', 'g')), '');
  end if;

  return new;
end $$;

drop trigger if exists vehiculos_normalizan on public.vehiculos;
--  BEFORE, y antes que el trigger que encola la búsqueda en la guía: lo
--  que se encola tiene que ser el nombre ya corregido.
create trigger vehiculos_normalizan
  before insert or update on public.vehiculos
  for each row execute function public.normalizar_vehiculo();

-- ---------------------------------------------------------------------
--  Lo que ya estaba cargado
-- ---------------------------------------------------------------------
--  Se escribe igual que lo nuevo. El `is distinct from` evita tocar filas
--  que ya estaban bien y disparar encolados al pedo.
update public.vehiculos
   set marca   = public.normalizar_marca(marca),
       modelo  = public.normalizar_nombre(modelo),
       version = public.normalizar_nombre(version),
       color   = public.normalizar_nombre(color),
       patente = nullif(upper(regexp_replace(coalesce(patente, ''),
                                             '[^a-zA-Z0-9]', '', 'g')), '')
 where deleted_at is null
   and (marca   is distinct from public.normalizar_marca(marca)
     or modelo  is distinct from public.normalizar_nombre(modelo)
     or version is distinct from public.normalizar_nombre(version)
     or color   is distinct from public.normalizar_nombre(color)
     or patente is distinct from nullif(
          upper(regexp_replace(coalesce(patente, ''), '[^a-zA-Z0-9]', '', 'g')),
          ''));
