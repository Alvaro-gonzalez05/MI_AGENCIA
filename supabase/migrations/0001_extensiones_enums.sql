-- =====================================================================
-- MI AGENCIA — 0001: extensiones y tipos enumerados
-- =====================================================================
create extension if not exists "pgcrypto";
create extension if not exists "citext";
create extension if not exists "pg_trgm";     -- busqueda difusa marca/modelo
create extension if not exists "unaccent";    -- busqueda sin tildes

-- Rol de un usuario DENTRO de una agencia.
-- El rol de plataforma (desarrollador) vive en perfiles.es_desarrollador,
-- porque no pertenece a ninguna agencia en particular.
do $$ begin
  create type rol_membresia as enum ('owner','admin','vendedor','solo_lectura');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_vehiculo as enum ('en_stock','en_preparacion','reservado','vendido','dado_de_baja');
exception when duplicate_object then null; end $$;

do $$ begin
  create type categoria_gasto as enum (
    'service','reparaciones','cubiertas','chapa_y_pintura','lavado_detallado',
    'transferencia','patentamiento','gestoria','almacenamiento','comision','otros');
exception when duplicate_object then null; end $$;

-- Embudo de venta. El semaforo (rojo/amarillo/verde) NO es un estado del
-- embudo: se deriva de la situacion crediticia BCRA. Son ejes distintos.
do $$ begin
  create type estado_oportunidad as enum
    ('nuevo','contactado','visita_agendada','visita_realizada','negociacion','reservado','ganado','perdido');
exception when duplicate_object then null; end $$;

do $$ begin
  create type semaforo_crediticio as enum ('verde','amarillo','rojo','sin_datos');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_interaccion as enum ('llamada','whatsapp','email','visita','mensaje_web','otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_campana as enum ('borrador','programada','enviando','enviada','cancelada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type estado_envio as enum ('pendiente','enviado','entregado','abierto','click','rebote','baja','error');
exception when duplicate_object then null; end $$;

do $$ begin
  create type tipo_cotizacion as enum ('oficial','blue','mayorista','mep','ccl','tarjeta');
exception when duplicate_object then null; end $$;
