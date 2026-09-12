-- =====================================================================
-- MI AGENCIA — 0006: CRM (clientes, oportunidades) + BCRA
--
-- El HTML original tenia una sola tabla "interesados" con nombre, telefono
-- y una observacion suelta. Aca se separa en dos cosas distintas:
--   clientes      -> la PERSONA (se repite entre vehiculos y entre anios)
--   oportunidades -> el INTERES de esa persona en UN vehiculo concreto
-- Sin esa separacion no se puede hacer ni email marketing ni semaforo
-- crediticio, porque ambos son propiedades de la persona, no del interes.
-- =====================================================================

create table if not exists public.clientes (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  nombre      text not null,
  apellido    text,
  -- CUIT/CUIL es la clave para consultar el BCRA. 11 digitos sin guiones.
  cuit        text,
  dni         text,
  email       citext,
  telefono    text,
  whatsapp    text,
  localidad   text,
  provincia   text,
  origen      text,           -- de donde vino: web, showroom, referido, MercadoLibre...
  notas       text,
  -- Baja de la lista de email marketing. Obligatorio por buenas practicas
  -- anti-spam: nunca se le vuelve a escribir a quien pidio la baja.
  acepta_marketing boolean not null default true,
  baja_marketing_at timestamptz,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  constraint cuit_formato check (cuit is null or cuit ~ '^[0-9]{11}$')
);
create index if not exists idx_clientes_agencia on public.clientes(agencia_id) where deleted_at is null;
create index if not exists idx_clientes_cuit    on public.clientes(agencia_id, cuit) where cuit is not null;
create index if not exists idx_clientes_email   on public.clientes(agencia_id, email) where email is not null;
create index if not exists idx_clientes_busqueda on public.clientes
  using gin ((nombre || ' ' || coalesce(apellido, '')) gin_trgm_ops);
-- Un mismo CUIT no se carga dos veces en la misma agencia.
create unique index if not exists idx_clientes_cuit_unico
  on public.clientes(agencia_id, cuit) where cuit is not null and deleted_at is null;

drop trigger if exists trg_clientes_updated on public.clientes;
create trigger trg_clientes_updated before update on public.clientes
  for each row execute function public.tocar_updated_at();

-- Ahora que existe clientes, se cierra la FK que quedo pendiente en 0005.
alter table public.ventas
  drop constraint if exists ventas_cliente_id_fkey;
alter table public.ventas
  add constraint ventas_cliente_id_fkey
  foreign key (cliente_id) references public.clientes(id) on delete set null;

-- ---------- Oportunidades (el embudo) -----------------------------------
create table if not exists public.oportunidades (
  id                uuid primary key default gen_random_uuid(),
  agencia_id        uuid not null references public.agencias(id) on delete cascade,
  cliente_id        uuid not null references public.clientes(id) on delete cascade,
  -- Puede ser null: alguien que "busca una pickup" sin unidad definida.
  vehiculo_id       uuid references public.vehiculos(id) on delete set null,
  estado            estado_oportunidad not null default 'nuevo',
  -- 1 = frio, 5 = caliente. Lo pone el vendedor a mano.
  interes           smallint not null default 3 check (interes between 1 and 5),
  presupuesto_max   numeric(16,2),
  necesita_financiacion boolean not null default false,
  -- Si entrega un usado como parte de pago, se anota aca.
  entrega_usado     boolean not null default false,
  usado_descripcion text,
  usado_valor_estimado numeric(16,2),
  proxima_accion    text,
  proxima_accion_fecha date,
  asignado_a        uuid references auth.users(id) on delete set null,
  motivo_perdida    text,
  notas             text,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  cerrada_at        timestamptz
);
create index if not exists idx_oport_agencia  on public.oportunidades(agencia_id, estado);
create index if not exists idx_oport_cliente  on public.oportunidades(cliente_id);
create index if not exists idx_oport_vehiculo on public.oportunidades(vehiculo_id);
create index if not exists idx_oport_agenda   on public.oportunidades(agencia_id, proxima_accion_fecha)
  where proxima_accion_fecha is not null and cerrada_at is null;

drop trigger if exists trg_oport_updated on public.oportunidades;
create trigger trg_oport_updated before update on public.oportunidades
  for each row execute function public.tocar_updated_at();

-- Sella la fecha de cierre cuando la oportunidad se gana o se pierde.
create or replace function public.sellar_cierre_oportunidad()
returns trigger language plpgsql as $fn$
begin
  if new.estado in ('ganado', 'perdido') and old.estado not in ('ganado', 'perdido') then
    new.cerrada_at := now();
  elsif new.estado not in ('ganado', 'perdido') then
    new.cerrada_at := null;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_oport_cierre on public.oportunidades;
create trigger trg_oport_cierre before update on public.oportunidades
  for each row execute function public.sellar_cierre_oportunidad();

-- ---------- Bitacora de contactos ---------------------------------------
create table if not exists public.interacciones (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references public.agencias(id) on delete cascade,
  oportunidad_id  uuid references public.oportunidades(id) on delete cascade,
  cliente_id      uuid not null references public.clientes(id) on delete cascade,
  tipo            tipo_interaccion not null default 'llamada',
  fecha           timestamptz not null default now(),
  resumen         text,
  usuario_id      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists idx_interacciones_oport   on public.interacciones(oportunidad_id, fecha desc);
create index if not exists idx_interacciones_cliente on public.interacciones(cliente_id, fecha desc);

-- =====================================================================
-- BCRA — Central de Deudores
--
-- API publica y gratuita del Banco Central:
--   GET https://api.bcra.gob.ar/centraldedeudores/v1.0/Deudas/{cuit}
--   GET .../Deudas/Historicas/{cuit}          (24 meses)
--   GET .../Deudas/ChequesRechazados/{cuit}
--
-- Se consulta desde una Edge Function (no desde la app) por dos razones:
-- el BCRA no manda cabeceras CORS, y asi cacheamos para no golpear su API
-- cada vez que alguien abre una ficha.
--
-- Situacion BCRA: 1 normal .. 6 irrecuperable. Ese numero es el insumo
-- del semaforo que pidio el cliente.
-- =====================================================================
create table if not exists public.bcra_consultas (
  id                uuid primary key default gen_random_uuid(),
  agencia_id        uuid not null references public.agencias(id) on delete cascade,
  cliente_id        uuid references public.clientes(id) on delete cascade,
  cuit              text not null,
  denominacion      text,                  -- nombre que devuelve el BCRA
  -- Peor situacion informada entre todas las entidades (1..6).
  situacion_maxima  smallint,
  total_deuda_miles numeric(16,2),         -- el BCRA informa en miles de pesos
  cantidad_entidades smallint,
  tiene_cheques_rechazados boolean not null default false,
  cheques_sin_pagar smallint not null default 0,
  -- Banderas que el BCRA informa por entidad y que agravan el riesgo aunque
  -- la situacion sea baja. Se guardan desnormalizadas para poder filtrar
  -- "mostrame todos los interesados con juicio" sin abrir el jsonb.
  dias_atraso_max        smallint not null default 0,
  tiene_proceso_judicial boolean not null default false,
  tiene_refinanciaciones boolean not null default false,
  tiene_situacion_juridica boolean not null default false,
  en_revision            boolean not null default false,
  periodo                text,                  -- "202607": mes informado por el BCRA
  -- Detalle crudo por entidad, tal como llego, para poder mostrar el desglose
  -- sin volver a consultar y para auditar si el BCRA cambia su respuesta.
  entidades         jsonb,
  cheques           jsonb,
  payload_deudas    jsonb,
  payload_cheques   jsonb,
  consultado_por    uuid references auth.users(id) on delete set null,
  consultado_at     timestamptz not null default now(),
  -- El BCRA actualiza mensualmente; no tiene sentido reconsultar antes.
  expira_at         timestamptz not null default now() + interval '30 days',
  error             text
);
create index if not exists idx_bcra_cliente on public.bcra_consultas(cliente_id, consultado_at desc);
create index if not exists idx_bcra_cuit    on public.bcra_consultas(cuit, consultado_at desc);

-- Traduce la situacion BCRA al semaforo que pidio el cliente.
--   verde    -> situacion 1-2, sin cheques rechazados: apto para financiar
--   amarillo -> situacion 3, o cheques rechazados ya pagados: mirar con lupa
--   rojo     -> situacion 4-6, o cheques sin pagar: no dar credito
create or replace function public.semaforo_de_situacion(
  p_situacion smallint,
  p_cheques_sin_pagar smallint default 0,
  p_tiene_cheques boolean default false,
  p_proceso_judicial boolean default false,
  p_dias_atraso smallint default 0)
returns semaforo_crediticio
language sql
immutable
as $fn$
  select case
    when p_situacion is null then 'sin_datos'::semaforo_crediticio
    -- Rojo: irrecuperable/con alto riesgo de insolvencia, cheques impagos o juicio.
    when p_situacion >= 4
      or coalesce(p_cheques_sin_pagar, 0) > 0
      or coalesce(p_proceso_judicial, false) then 'rojo'::semaforo_crediticio
    -- Amarillo: cumplimiento deficiente, o senales tempranas de mora.
    when p_situacion = 3
      or coalesce(p_tiene_cheques, false)
      or coalesce(p_dias_atraso, 0) > 30 then 'amarillo'::semaforo_crediticio
    when p_situacion <= 2 then 'verde'::semaforo_crediticio
    else 'sin_datos'::semaforo_crediticio
  end;
$fn$;

-- Ultima consulta vigente de cada cliente, ya traducida a semaforo.
-- Es lo que consume la pantalla de Interesados.
create or replace view public.v_clientes_semaforo as
select c.id            as cliente_id,
       c.agencia_id,
       c.nombre,
       c.apellido,
       c.cuit,
       b.situacion_maxima,
       b.total_deuda_miles,
       b.cantidad_entidades,
       b.cheques_sin_pagar,
       b.tiene_cheques_rechazados,
       b.dias_atraso_max,
       b.tiene_proceso_judicial,
       b.tiene_refinanciaciones,
       b.tiene_situacion_juridica,
       b.en_revision,
       b.periodo,
       b.entidades,
       b.consultado_at,
       b.expira_at,
       (b.expira_at < now())                        as consulta_vencida,
       coalesce(
         public.semaforo_de_situacion(
           b.situacion_maxima, b.cheques_sin_pagar, b.tiene_cheques_rechazados,
           b.tiene_proceso_judicial, b.dias_atraso_max),
         'sin_datos'::semaforo_crediticio)          as semaforo
from public.clientes c
left join lateral (
  select * from public.bcra_consultas bb
   where bb.cliente_id = c.id and bb.error is null
   order by bb.consultado_at desc
   limit 1
) b on true
where c.deleted_at is null;
