-- =====================================================================
--  MI AGENCIA — 0037: dónde quedó el dueño en la pizarra
--
--  Las zonas ya guardan su posición (0035). Falta la de la tarjeta del
--  dueño, que es de la que salen todas las líneas: si no se guarda, el
--  cliente acomoda su pizarra, cierra la app y vuelve a encontrarla como
--  la dejamos nosotros.
--
--  Va en `agencia_config` porque es exactamente eso: una preferencia de la
--  agencia, al lado de los umbrales y el redondeo. Una tabla nueva con una
--  fila y dos números sería una tabla de más.
-- =====================================================================

alter table public.agencia_config
  add column if not exists pizarra_x integer not null default 352,
  add column if not exists pizarra_y integer not null default 250;

comment on column public.agencia_config.pizarra_x is
  'Dónde quedó la tarjeta del dueño en la pizarra de usuarios. Es de la '
  'agencia, no de cada usuario: el tablero es de la oficina.';
