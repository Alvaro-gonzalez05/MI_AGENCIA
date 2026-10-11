-- =====================================================================
--  MI AGENCIA — 0032: buscar por palabras, como busca una persona
--
--  Con similitud sola no alcanzaba: "ranger xlt" contra
--  "FORD RANGER PICK - UP D/C 3,2 Diesel Xlt 4X2 2014" da 0,24, y el
--  umbral de pg_trgm es 0,30. El nombre de la guía es largo y lleno de
--  cosas que nadie escribe ("PICK - UP", "D/C", "4X2").
--
--  Lo que hace una persona es escribir dos o tres palabras y esperar que
--  estén todas: eso es lo que hace ahora la búsqueda. La similitud se
--  sigue usando, pero para ordenar los resultados, no para filtrarlos.
-- =====================================================================

create or replace function public.buscar_revista(
  p_texto text,
  p_anio  integer default null,
  p_tope  integer default 12
)
returns table (
  version_id    integer,
  marca         text,
  modelo        text,
  version       text,
  version_raw   text,
  anio          smallint,
  precio_ars    numeric,
  actualizado   timestamptz,
  parecido      real
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with consulta as (
    select
      lower(trim(both ' ' from coalesce(p_texto, ''))) as q,
      -- Palabras de más de dos letras: "de", "la" o "4" no filtran nada.
      array(
        select palabra
          from unnest(string_to_array(
                 lower(trim(both ' ' from coalesce(p_texto, ''))), ' ')) palabra
         where length(palabra) > 2
      ) as palabras
  ),
  candidatos as (
    select
      v.id,
      v.marca_nombre,
      v.modelo_nombre,
      v.nombre,
      v.nombre_raw,
      p.anio,
      p.precio_ars,
      p.actualizado_at,
      lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw)) as texto
    from public.ref_versiones v
    join public.ref_precios p on p.version_id = v.id
    where p_anio is null or p.anio = p_anio
  )
  select
    c.id,
    c.marca_nombre,
    c.modelo_nombre,
    c.nombre,
    c.nombre_raw,
    c.anio,
    c.precio_ars,
    c.actualizado_at,
    similarity(c.texto, (select q from consulta))
  from candidatos c, consulta
  where cardinality(consulta.palabras) > 0
    -- Todas las palabras tienen que estar. Con "hilux srv" no sirve que
    -- aparezca una sola: el precio de una SR no es el de una SRV.
    and (
      select bool_and(c.texto like '%' || palabra || '%')
        from unnest(consulta.palabras) palabra
    )
  order by similarity(c.texto, (select q from consulta)) desc, c.anio desc
  limit greatest(1, p_tope);
$$;

grant execute on function public.buscar_revista(text, integer, integer)
  to authenticated;

create or replace function public.anios_revista(p_texto text)
returns table (anio smallint, versiones bigint)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with consulta as (
    select array(
      select palabra
        from unnest(string_to_array(
               lower(trim(both ' ' from coalesce(p_texto, ''))), ' ')) palabra
       where length(palabra) > 2
    ) as palabras
  )
  select p.anio, count(*)
    from public.ref_versiones v
    join public.ref_precios p on p.version_id = v.id
    cross join consulta
   where cardinality(consulta.palabras) > 0
     and (
       select bool_and(
         lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw))
         like '%' || palabra || '%')
         from unnest(consulta.palabras) palabra
     )
   group by p.anio
   order by p.anio desc;
$$;

grant execute on function public.anios_revista(text) to authenticated;
