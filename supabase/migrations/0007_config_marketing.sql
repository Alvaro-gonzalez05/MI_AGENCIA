-- =====================================================================
-- MI AGENCIA — 0007: configuracion por agencia + email marketing
-- =====================================================================

-- Umbrales y parametros del motor de calculo. Una fila por agencia: cada
-- concesionaria define su propio margen objetivo y sus propios plazos de
-- rotacion, y todo el sistema se recalcula solo (igual que el HTML original).
create table if not exists public.agencia_config (
  agencia_id  uuid primary key references public.agencias(id) on delete cascade,

  -- Semaforo de ANTIGUEDAD en stock (dias). Ojo: es otro semaforo distinto
  -- al crediticio del cliente; este mide cuanto tarda en rotar la unidad.
  dias_verde     smallint not null default 30,
  dias_amarillo  smallint not null default 60,
  dias_rojo      smallint not null default 90,

  margen_minimo  numeric(6,4) not null default 0.10,
  margen_objetivo numeric(6,4) not null default 0.30,
  tolerancia_caida_margen numeric(6,4) not null default 0.005,
  tolerancia_desvio_precio numeric(6,4) not null default 0.02,
  umbral_gastos_altos numeric(16,2) not null default 1000000,

  -- A cuanto se redondea el precio a publicar (50.000 -> termina en 00.000).
  redondeo       numeric(12,2) not null default 50000,
  capacidad      smallint not null default 60,   -- unidades que entran en el predio
  tasa_financiacion_mensual numeric(6,4) not null default 0.06,

  -- Que dolar usa esta agencia para expresar la ganancia real en USD.
  tipo_cambio_preferido tipo_cotizacion not null default 'oficial',

  updated_at timestamptz not null default now(),

  constraint dias_ordenados check (dias_verde < dias_amarillo and dias_amarillo < dias_rojo),
  constraint margenes_ordenados check (margen_minimo <= margen_objetivo),
  constraint margenes_en_rango check (margen_objetivo < 1 and margen_minimo >= 0)
);

drop trigger if exists trg_config_updated on public.agencia_config;
create trigger trg_config_updated before update on public.agencia_config
  for each row execute function public.tocar_updated_at();

-- Toda agencia nace con la configuracion por defecto: nunca hay una agencia
-- sin config, asi el motor de calculo no tiene que contemplar el caso null.
create or replace function public.crear_config_por_defecto()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.agencia_config (agencia_id) values (new.id)
  on conflict (agencia_id) do nothing;
  return new;
end $fn$;

drop trigger if exists trg_agencia_config on public.agencias;
create trigger trg_agencia_config after insert on public.agencias
  for each row execute function public.crear_config_por_defecto();

-- =====================================================================
-- EMAIL MARKETING
-- El envio real lo hace una Edge Function contra un proveedor (Resend o
-- Brevo). La base guarda que se mando, a quien y que paso con cada envio.
-- =====================================================================

create table if not exists public.plantillas_email (
  id         uuid primary key default gen_random_uuid(),
  agencia_id uuid not null references public.agencias(id) on delete cascade,
  nombre     text not null,
  asunto     text not null,
  cuerpo_html text not null,
  -- Variables disponibles para reemplazo: {{nombre}}, {{vehiculo}}, {{precio}}...
  variables  text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.campanas (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references public.agencias(id) on delete cascade,
  nombre      text not null,
  asunto      text not null,
  cuerpo_html text not null,
  remitente_nombre text,
  remitente_email  citext,
  estado      estado_campana not null default 'borrador',
  -- Criterio de audiencia guardado como filtro, no como lista congelada:
  -- {"semaforo":["verde"],"interes_min":4,"vehiculo_marca":"Toyota"}
  filtro      jsonb not null default '{}'::jsonb,
  programada_para timestamptz,
  enviada_at  timestamptz,
  total_destinatarios integer not null default 0,
  total_enviados integer not null default 0,
  total_aperturas integer not null default 0,
  total_clicks   integer not null default 0,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_campanas_agencia on public.campanas(agencia_id, created_at desc);
create index if not exists idx_campanas_programadas on public.campanas(programada_para)
  where estado = 'programada';

create table if not exists public.campana_destinatarios (
  id          uuid primary key default gen_random_uuid(),
  campana_id  uuid not null references public.campanas(id) on delete cascade,
  cliente_id  uuid not null references public.clientes(id) on delete cascade,
  email       citext not null,
  estado      estado_envio not null default 'pendiente',
  -- Id que devuelve el proveedor, para casar los webhooks de apertura/click.
  proveedor_id text,
  enviado_at  timestamptz,
  abierto_at  timestamptz,
  click_at    timestamptz,
  error       text,
  unique (campana_id, cliente_id)
);
create index if not exists idx_destinatarios_campana on public.campana_destinatarios(campana_id, estado);
create index if not exists idx_destinatarios_proveedor on public.campana_destinatarios(proveedor_id)
  where proveedor_id is not null;

drop trigger if exists trg_campanas_updated on public.campanas;
create trigger trg_campanas_updated before update on public.campanas
  for each row execute function public.tocar_updated_at();

drop trigger if exists trg_plantillas_updated on public.plantillas_email;
create trigger trg_plantillas_updated before update on public.plantillas_email
  for each row execute function public.tocar_updated_at();

-- Cuando un cliente pide la baja, queda registrado el momento exacto.
create or replace function public.sellar_baja_marketing()
returns trigger language plpgsql as $fn$
begin
  if old.acepta_marketing and not new.acepta_marketing then
    new.baja_marketing_at := now();
  elsif not old.acepta_marketing and new.acepta_marketing then
    new.baja_marketing_at := null;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_baja_marketing on public.clientes;
create trigger trg_baja_marketing before update on public.clientes
  for each row execute function public.sellar_baja_marketing();

-- =====================================================================
-- AUDITORIA — quien toco que y cuando.
-- En un ERP donde se manejan precios de compra y margenes, poder responder
-- "quien bajo el precio de esta unidad" no es opcional.
-- =====================================================================
create table if not exists public.auditoria (
  id          bigserial primary key,
  agencia_id  uuid,
  tabla       text not null,
  registro_id uuid,
  accion      text not null,           -- INSERT | UPDATE | DELETE
  usuario_id  uuid,
  datos_antes  jsonb,
  datos_despues jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists idx_auditoria_registro on public.auditoria(tabla, registro_id, created_at desc);
create index if not exists idx_auditoria_agencia  on public.auditoria(agencia_id, created_at desc);

create or replace function public.registrar_auditoria()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_agencia uuid;
  v_id      uuid;
begin
  if tg_op = 'DELETE' then
    v_agencia := (to_jsonb(old)->>'agencia_id')::uuid;
    -- agencia_config no tiene columna id: su clave es agencia_id.
    v_id      := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'agencia_id')::uuid;
    insert into public.auditoria (agencia_id, tabla, registro_id, accion, usuario_id, datos_antes)
    values (v_agencia, tg_table_name, v_id, tg_op, auth.uid(), to_jsonb(old));
    return old;
  else
    v_agencia := (to_jsonb(new)->>'agencia_id')::uuid;
    v_id      := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'agencia_id')::uuid;
    insert into public.auditoria (agencia_id, tabla, registro_id, accion, usuario_id, datos_antes, datos_despues)
    values (v_agencia, tg_table_name, v_id, tg_op, auth.uid(),
            case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
    return new;
  end if;
end $fn$;

-- Se audita lo que toca plata. Gastos e interacciones generan mucho ruido
-- y poco valor, asi que quedan afuera a proposito.
drop trigger if exists trg_audit_vehiculos on public.vehiculos;
create trigger trg_audit_vehiculos after insert or update or delete on public.vehiculos
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_precios on public.cambios_precio;
create trigger trg_audit_precios after insert or update or delete on public.cambios_precio
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_ventas on public.ventas;
create trigger trg_audit_ventas after insert or update or delete on public.ventas
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_audit_config on public.agencia_config;
create trigger trg_audit_config after update on public.agencia_config
  for each row execute function public.registrar_auditoria();
