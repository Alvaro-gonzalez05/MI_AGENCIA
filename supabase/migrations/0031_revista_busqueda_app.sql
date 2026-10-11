-- =====================================================================
--  MI AGENCIA — 0031: buscar el precio de revista desde la app
--
--  El buscador del Inicio ("Buscá el precio de revista de cualquier auto")
--  consulta NUESTRA copia, no la guía: es instantáneo, no gasta cupo y
--  funciona aunque la guía esté caída. Si lo buscado todavía no está, se
--  encola con prioridad y aparece en la próxima corrida del cosechador.
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
  with limpio as (
    select lower(trim(both ' ' from coalesce(p_texto, ''))) as q
  )
  select
    v.id,
    v.marca_nombre,
    v.modelo_nombre,
    v.nombre,
    v.nombre_raw,
    p.anio,
    p.precio_ars,
    p.actualizado_at,
    similarity(
      lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw)),
      (select q from limpio)
    )
  from public.ref_versiones v
  join public.ref_precios p on p.version_id = v.id
  cross join limpio
  where limpio.q <> ''
    and (p_anio is null or p.anio = p_anio)
    and (
      -- Por palabras sueltas: quien escribe "hilux srv" no escribe el
      -- nombre completo de la guía.
      lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw))
        % limpio.q
      or lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw))
        like '%' || limpio.q || '%'
    )
  order by similarity(
             lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw)),
             (select q from limpio)) desc,
           p.anio desc
  limit greatest(1, p_tope);
$$;

grant execute on function public.buscar_revista(text, integer, integer)
  to authenticated;

--  Qué años tiene la guía para lo que se buscó: el selector del modal.
create or replace function public.anios_revista(p_texto text)
returns table (anio smallint, versiones bigint)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select p.anio, count(*)
    from public.ref_versiones v
    join public.ref_precios p on p.version_id = v.id
   where lower(concat_ws(' ', v.marca_nombre, v.modelo_nombre, v.nombre_raw))
         % lower(coalesce(p_texto, ''))
   group by p.anio
   order by p.anio desc;
$$;

grant execute on function public.anios_revista(text) to authenticated;

-- ---------------------------------------------------------------------
--  Pedirle a la guía algo que todavía no tenemos
-- ---------------------------------------------------------------------
--  Prioridad 1: alguien lo está esperando con la pantalla abierta, va
--  antes que el refresco mensual.
create or replace function public.pedir_revista(
  p_texto text,
  p_anio  integer default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  limpia text;
  id_tarea bigint;
begin
  limpia := public.consulta_para_revista(p_texto, null, null);
  if limpia is null then
    return null;
  end if;

  insert into public.ref_cola (tipo, consulta, texto, anio, prioridad)
  values ('buscar', limpia, p_texto, p_anio::smallint, 1)
  on conflict do nothing
  returning id into id_tarea;

  return id_tarea;
end $$;

grant execute on function public.pedir_revista(text, integer) to authenticated;
