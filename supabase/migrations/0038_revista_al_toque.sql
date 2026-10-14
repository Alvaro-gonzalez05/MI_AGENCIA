-- =====================================================================
--  MI AGENCIA — 0038: el precio de revista, al toque
--
--  Hasta ahora la app sólo leía nuestra copia, que el cosechador llenaba de
--  a poco. Para una unidad del inventario está bien —el precio llega en el
--  día— pero no sirve para lo que la agencia hace todo el tiempo: tener al
--  cliente enfrente, preguntar cuánto vale un auto que no tiene, y
--  necesitar el número en ese momento.
--
--  Resulta que la guía tiene un endpoint que contesta justo eso: `/search`
--  devuelve hasta 25 versiones **con su precio** en una sola llamada. O
--  sea: el dato al toque ya era posible; lo que faltaba era pedirlo.
--
--  Esta función guarda esas 25 versiones de una. El efecto de costado es el
--  que importa a la larga: cada búsqueda que hace un usuario deja 25
--  precios guardados, así que la base se va llenando sola con lo que la
--  gente pregunta de verdad, que es justo lo que después va a volver a
--  preguntar.
--
--  Ojo con las unidades: `/search` devuelve el precio en DÓLARES y
--  `/versions/{id}/valuations?currency=ars` en pesos. Acá entra el de
--  búsqueda, así que se pasa a pesos con el dólar oficial del día.
-- =====================================================================

create or replace function public.guardar_busqueda_en_vivo(
  p_resultado jsonb,
  p_tc        numeric default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  fila   jsonb;
  tc     numeric := coalesce(
            nullif(p_tc, 0),
            public.cotizacion_vigente('oficial'),
            0);
  cuenta integer := 0;
begin
  if tc <= 0 then
    raise exception 'Sin cotización del dólar no se puede pasar el precio a pesos.';
  end if;

  for fila in
    select * from jsonb_array_elements(coalesce(p_resultado, '[]'::jsonb))
  loop
    continue when (fila->>'version_id') is null
              or (fila->>'price') is null
              or (fila->>'price_year') is null;

    insert into public.ref_versiones (
      id, nombre, nombre_raw, marca_nombre, modelo_nombre
    )
    values (
      (fila->>'version_id')::int,
      coalesce(fila->>'version', ''),
      fila->>'version_raw',
      fila->>'brand',
      fila->>'model'
    )
    on conflict (id) do update
      set nombre        = excluded.nombre,
          nombre_raw    = excluded.nombre_raw,
          marca_nombre  = excluded.marca_nombre,
          modelo_nombre = excluded.modelo_nombre;

    insert into public.ref_precios (
      version_id, anio, precio_ars, precio_usd, tc_usado, actualizado_at
    )
    values (
      (fila->>'version_id')::int,
      (fila->>'price_year')::smallint,
      (fila->>'price')::numeric * tc,
      (fila->>'price')::numeric,
      tc,
      now()
    )
    on conflict (version_id, anio) do update
      set precio_ars     = excluded.precio_ars,
          precio_usd     = excluded.precio_usd,
          tc_usado       = excluded.tc_usado,
          actualizado_at = now();

    cuenta := cuenta + 1;
  end loop;

  return cuenta;
end $$;

comment on function public.guardar_busqueda_en_vivo(jsonb, numeric) is
  'Guarda las versiones y los precios que devolvió /search de la guía. El '
  'precio viene en dólares y se pasa a pesos con el oficial del día.';

revoke all on function public.guardar_busqueda_en_vivo(jsonb, numeric) from public;

-- ---------------------------------------------------------------------
--  Cuánto cupo queda hoy
-- ---------------------------------------------------------------------
--  La guía deja 30 consultas por día y el cupo es de la IP, así que lo
--  gastan entre todos: el cosechador de la noche y las búsquedas a mano.
--  La app necesita saberlo para avisar antes y no después.
create or replace function public.cupo_revista()
returns table (usadas integer, limite integer, quedan integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(u.consultas, 0)::integer,
    coalesce(u.limite, 28)::integer,
    greatest(coalesce(u.limite, 28) - coalesce(u.consultas, 0), 0)::integer
  from (select 1) _
  left join public.ref_api_uso u on u.fecha = current_date;
$$;

revoke all on function public.cupo_revista() from public;
grant execute on function public.cupo_revista() to authenticated;
