-- =====================================================================
--  MI AGENCIA — 0021: detalle del BCRA por entidad y por mes
--
--  Checklist del cliente, tanda 2, punto 2.4: el informe tiene que mostrar,
--  para cada banco, financiera o tarjeta y para cada mes de los últimos 24,
--  la situación (1 a 6), el monto adeudado y si hay gestión judicial.
--
--  Desde esta versión la Edge Function bcra-consulta guarda ese detalle en
--  `historico` (cada mes lleva sus `entidades`). Las consultas hechas antes
--  ya tienen la respuesta cruda del BCRA en `payload_historico`: acá se
--  rearma `historico` a partir de ella, con la misma forma que arma
--  historial.ts, para que el informe de esas personas también lo muestre
--  sin volver a consultar.
-- =====================================================================

update public.bcra_consultas c
   set historico = coalesce((
     select jsonb_agg(
              jsonb_build_object(
                'periodo',    p->>'periodo',
                'situacion',  coalesce((
                    select max(coalesce((e->>'situacion')::int, 0))
                      from jsonb_array_elements(coalesce(p->'entidades', '[]'::jsonb)) e), 0),
                'entidades',  coalesce((
                    select jsonb_agg(
                             jsonb_build_object(
                               'entidad',    trim(coalesce(e->>'entidad', 'Sin identificar')),
                               'situacion',  coalesce((e->>'situacion')::int, 0),
                               'monto',      coalesce((e->>'monto')::numeric, 0),
                               'procesoJud', coalesce((e->>'procesoJud')::boolean, false),
                               'enRevision', coalesce((e->>'enRevision')::boolean, false))
                             order by coalesce((e->>'situacion')::int, 0) desc,
                                      coalesce((e->>'monto')::numeric, 0) desc)
                      from jsonb_array_elements(coalesce(p->'entidades', '[]'::jsonb)) e),
                    '[]'::jsonb))
              order by p->>'periodo' desc)
       from jsonb_array_elements(c.payload_historico->'results'->'periodos') p
      where p->>'periodo' ~ '^\d{6}$'
   ), '[]'::jsonb)
 where c.payload_historico is not null
   and jsonb_typeof(c.payload_historico->'results'->'periodos') = 'array';
