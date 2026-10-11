-- =====================================================================
--  MI AGENCIA — 0029: buscar en la guía con el texto que la guía entiende
--
--  Probando contra ArgAutos con el stock real apareció esto: buscar
--  "FORD RANGER XLT 3.2" devuelve CERO resultados, y "ford ranger xlt"
--  devuelve veinticinco. Su buscador exige que las palabras aparezcan tal
--  cual, y en su catálogo los decimales van con coma ("3,2") y los modelos
--  tienen nombres propios ("RANGER PICK - UP").
--
--  Entonces se manda una consulta limpia —marca, modelo y las palabras de
--  la versión que son solo letras— y el parecido se mide contra el texto
--  completo de la unidad, que es el que tiene los números. Mandar poco y
--  comparar con todo: al revés no encuentra nada.
-- =====================================================================

--  El texto original queda guardado para poder puntuar los candidatos.
alter table public.ref_cola
  add column if not exists texto text;

comment on column public.ref_cola.texto is
  'Marca, modelo y versión tal como los escribió la agencia. Se usa para '
  'elegir cuál de los candidatos de la guía es el bueno.';

-- ---------------------------------------------------------------------
--  Limpiar el texto que se le manda a la guía
-- ---------------------------------------------------------------------
create or replace function public.consulta_para_revista(
  p_marca   text,
  p_modelo  text,
  p_version text
)
returns text
language sql
immutable
as $$
  select nullif(
    trim(both ' ' from
      regexp_replace(
        lower(
          -- Fuera lo que no sea letra: "3.2", "4x4", comas y barras hacen
          -- que su buscador no encuentre nada.
          regexp_replace(
            concat_ws(' ', p_marca, p_modelo, p_version),
            '[^a-zA-ZáéíóúüñÁÉÍÓÚÜÑ ]', ' ', 'g')
        ),
        '\s+', ' ', 'g')
    ),
  '');
$$;

-- ---------------------------------------------------------------------
--  Encolar con la consulta limpia
-- ---------------------------------------------------------------------
create or replace function public.encolar_revista(p_vehiculo uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v        public.vehiculos;
  limpia   text;
  completo text;
begin
  select * into v from public.vehiculos where id = p_vehiculo;
  if not found or v.deleted_at is not null then
    return;
  end if;

  if v.ref_version_id is not null then
    insert into public.ref_cola (tipo, version_id, anio, vehiculo_id)
    values ('valuar', v.ref_version_id, v.anio, v.id)
    on conflict do nothing;
    return;
  end if;

  limpia   := public.consulta_para_revista(v.marca, v.modelo, v.version);
  completo := trim(both ' ' from concat_ws(' ', v.marca, v.modelo, v.version));

  if limpia is null then
    return;  -- Sin marca ni modelo no hay nada que preguntar.
  end if;

  insert into public.ref_cola (tipo, consulta, texto, anio, vehiculo_id)
  values ('buscar', limpia, completo, v.anio, v.id)
  on conflict do nothing;
end $$;

grant execute on function public.encolar_revista(uuid) to authenticated;

-- ---------------------------------------------------------------------
--  Elegir el candidato comparando contra el texto completo
-- ---------------------------------------------------------------------
create or replace function public.guardar_busqueda_revista(
  p_tarea     bigint,
  p_resultado jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  t        public.ref_cola;
  elegido  jsonb;
  mejor    numeric := -1;
  fila     jsonb;
  puntaje  numeric;
  buscado  text;
begin
  select * into t from public.ref_cola where id = p_tarea;
  if not found then
    return 0;
  end if;

  buscado := lower(coalesce(t.texto, t.consulta, ''));

  for fila in select * from jsonb_array_elements(coalesce(p_resultado, '[]'::jsonb))
  loop
    -- Se compara contra marca + modelo + versión de la guía: su "version"
    -- sola no trae la marca, y dos marcas distintas tienen versiones que se
    -- llaman igual.
    puntaje := similarity(
      lower(concat_ws(' ',
        fila->>'brand',
        fila->>'model',
        coalesce(fila->>'version_raw', fila->>'version'))),
      buscado
    );

    -- El año de la unidad rompe los empates: la guía dice de qué año es el
    -- precio que devuelve en la búsqueda.
    if t.anio is not null and (fila->>'price_year') is not null
       and (fila->>'price_year')::int = t.anio then
      puntaje := puntaje + 0.15;
    end if;

    if puntaje > mejor then
      mejor := puntaje;
      elegido := fila;
    end if;
  end loop;

  -- Un parecido muy bajo es un error con disfraz: mejor dejar la unidad sin
  -- valor de revista que ponerle el precio de otro auto.
  if elegido is null or mejor < 0.25 then
    update public.ref_cola
       set estado = 'sin_resultado',
           procesado_at = now(),
           detalle = case
                       when elegido is null
                         then 'La guía no devolvió resultados.'
                       else format('El mejor candidato (%s) se parece muy '
                                   'poco: %s', elegido->>'version_raw',
                                   round(mejor, 2))
                     end
     where id = p_tarea;
    return 0;
  end if;

  insert into public.ref_versiones (id, nombre, nombre_raw, marca_nombre, modelo_nombre)
  values (
    (elegido->>'version_id')::int,
    coalesce(elegido->>'version', ''),
    elegido->>'version_raw',
    elegido->>'brand',
    elegido->>'model'
  )
  on conflict (id) do update
    set nombre        = excluded.nombre,
        nombre_raw    = excluded.nombre_raw,
        marca_nombre  = excluded.marca_nombre,
        modelo_nombre = excluded.modelo_nombre;

  if t.vehiculo_id is not null then
    update public.vehiculos
       set ref_version_id = (elegido->>'version_id')::int
     where id = t.vehiculo_id
       and ref_version_id is null;
  end if;

  update public.ref_cola
     set estado = 'hecha',
         procesado_at = now(),
         detalle = format('%s (parecido %s)',
                          elegido->>'version_raw', round(mejor, 2))
   where id = p_tarea;

  insert into public.ref_cola (tipo, version_id, anio, vehiculo_id, prioridad)
  values ('valuar', (elegido->>'version_id')::int, t.anio, t.vehiculo_id, 3)
  on conflict do nothing;

  return (elegido->>'version_id')::int;
end $$;

revoke all on function public.guardar_busqueda_revista(bigint, jsonb)
  from public, anon, authenticated;

-- El refresco mensual también manda la consulta limpia.
create or replace function public.encolar_revista_mensual()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cuantas integer;
begin
  insert into public.ref_cola (tipo, version_id, anio, prioridad)
  select distinct 'valuar'::tarea_revista, v.ref_version_id, v.anio, 8
    from public.vehiculos v
   where v.deleted_at is null
     and v.ref_version_id is not null
     and v.estado <> 'vendido'
  on conflict do nothing;

  get diagnostics cuantas = row_count;

  insert into public.ref_cola (tipo, consulta, texto, anio, vehiculo_id, prioridad)
  select distinct
         'buscar'::tarea_revista,
         public.consulta_para_revista(v.marca, v.modelo, v.version),
         trim(both ' ' from concat_ws(' ', v.marca, v.modelo, v.version)),
         v.anio,
         v.id,
         9
    from public.vehiculos v
   where v.deleted_at is null
     and v.ref_version_id is null
     and v.estado <> 'vendido'
     and public.consulta_para_revista(v.marca, v.modelo, v.version) is not null
  on conflict do nothing;

  return cuantas;
end $$;

revoke all on function public.encolar_revista_mensual() from public, anon, authenticated;
