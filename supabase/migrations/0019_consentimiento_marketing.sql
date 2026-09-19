-- =====================================================================
--  MI AGENCIA — 0019: el alta de interesados respeta el consentimiento
--
--  Checklist del cliente, punto 4.1: al armar una campaña decía "lo van a
--  recibir 0 personas" aunque había un interesado con email.
--
--  La causa: crear_interesado (0014) guardaba acepta_marketing = false
--  SIEMPRE, y ninguna pantalla dejaba cambiarlo. Todo interesado cargado
--  desde la app quedaba afuera de las campañas para siempre.
--
--  No se arregla poniendo true por defecto. Mandarle mails a alguien que no
--  lo aceptó es spam, quema la reputación del dominio y en Argentina choca
--  con la ley de datos personales. Lo correcto es preguntarlo: el formulario
--  ahora tiene el interruptor, y esta función guarda lo que se marcó. Si no
--  hay email, no hay consentimiento que valga: queda en false.
--
--  Única diferencia con la 0014: la línea del acepta_marketing del insert.
-- =====================================================================

create or replace function public.crear_interesado(p_agencia uuid, p_solicitud text, p_datos jsonb)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare
  v_cliente uuid;
  v_oportunidad uuid;
  v_vehiculo uuid := nullif(p_datos->>'vehiculo_id', '')::uuid;
  v_cuit text := p_datos->>'cuit';
  v_suma integer := 0;
  v_pesos integer[] := array[5,4,3,2,7,6,5,4,3,2];
  v_verificador integer;
begin
  if auth.uid() is null or not public.puede_editar(p_agencia) then
    raise exception 'No tenés permiso para cargar interesados en esta agencia.';
  end if;
  for n in 1..10 loop
    v_suma := v_suma + substring(v_cuit,n,1)::integer * v_pesos[n];
  end loop;
  v_verificador := case v_suma % 11 when 0 then 0 when 1 then 9 else 11 - v_suma % 11 end;
  if v_verificador <> substring(v_cuit,11,1)::integer then
    raise exception 'El CUIT/CUIL no tiene un dígito verificador válido.';
  end if;
  if length(trim(coalesce(p_datos->>'nombre',''))) < 2
     or v_cuit is null or v_cuit !~ '^[0-9]{11}$'
     or length(coalesce(p_solicitud,'')) not between 10 and 120 then
    raise exception 'Revisá el nombre, el CUIT/CUIL y la solicitud.';
  end if;
  if (p_datos->>'presupuesto_max')::numeric <= 0 then
    raise exception 'El presupuesto debe ser mayor a cero.';
  end if;
  -- Serializa reintentos y dos vendedores cargando el mismo CUIT.
  perform pg_advisory_xact_lock(hashtextextended(p_agencia::text || v_cuit, 0));
  select id, cliente_id into v_oportunidad, v_cliente from public.oportunidades
    where agencia_id = p_agencia and solicitud_alta = p_solicitud;
  if found then return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente); end if;
  if v_vehiculo is not null and not exists (
    select 1 from public.vehiculos where id = v_vehiculo and agencia_id = p_agencia
      and deleted_at is null and estado <> 'vendido'
  ) then raise exception 'La unidad no está disponible en esta agencia.'; end if;
  select id into v_cliente from public.clientes
    where agencia_id = p_agencia and cuit = v_cuit and deleted_at is null;
  if v_cliente is null then
    insert into public.clientes(agencia_id, nombre, cuit, telefono, email, localidad, acepta_marketing, created_by)
    values (p_agencia, trim(p_datos->>'nombre'), v_cuit, nullif(p_datos->>'telefono',''),
      nullif(p_datos->>'email',''), nullif(p_datos->>'localidad',''),
      -- Consentimiento para mails: solo si lo marcaron Y hay a donde mandar.
      coalesce((p_datos->>'acepta_marketing')::boolean, false)
        and nullif(p_datos->>'email','') is not null,
      auth.uid())
    returning id into v_cliente;
  end if;
  insert into public.oportunidades(agencia_id, cliente_id, vehiculo_id, presupuesto_max,
    necesita_financiacion, notas, created_by, solicitud_alta)
  values (p_agencia, v_cliente, v_vehiculo, (p_datos->>'presupuesto_max')::numeric,
    coalesce((p_datos->>'necesita_financiacion')::boolean,false), nullif(p_datos->>'notas',''),
    auth.uid(), p_solicitud) returning id into v_oportunidad;
  return jsonb_build_object('id', v_oportunidad, 'cliente_id', v_cliente);
end $$;
revoke all on function public.crear_interesado(uuid,text,jsonb) from public, anon;
grant execute on function public.crear_interesado(uuid,text,jsonb) to authenticated;
