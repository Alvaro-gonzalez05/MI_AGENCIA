// Prueba de punta a punta contra el proyecto real, como la haría un usuario:
// se crea una cuenta de vendedor, se entra con usuario y clave, se pide el
// inventario por la API pública y se mira qué llega. Al final se borra todo.
//
// Las claves salen de la Management API y nunca se imprimen.

const REF = 'zthpwqcoirrpvslambhz';
const URL = `https://${REF}.supabase.co`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
if (!token) { console.error('falta SUPABASE_TOKEN_MI_AGENCIA'); process.exit(1); }

const claves = await (await fetch(
  `https://api.supabase.com/v1/projects/${REF}/api-keys`,
  { headers: { Authorization: `Bearer ${token}` } })).json();
const anon = claves.find((k) => k.name === 'anon').api_key;
const secreta = claves.find((k) => k.name === 'service_role').api_key;

const sql = async (query) => {
  const r = await fetch(
    `https://api.supabase.com/v1/projects/${REF}/database/query`,
    { method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }) });
  const t = await r.text();
  if (!r.ok) throw new Error(`SQL ${r.status}: ${t}`);
  return JSON.parse(t);
};

const paso = (ok, texto) => console.log(`${ok ? '  OK  ' : ' FALLA'} ${texto}`);
let fallas = 0;
const afirmar = (ok, texto) => { if (!ok) fallas++; paso(ok, texto); };

const email = `prueba.e2e.${Date.now()}@miagencia.com`;
const clave = 'Prueba-' + Math.random().toString(36).slice(2, 10);
let usuarioId = null;

try {
  const [{ id: agenciaId, nombre: agenciaNombre }] =
    await sql(`select id, nombre from public.agencias order by created_at limit 1`);
  console.log(`\nAgencia de prueba: ${agenciaNombre}\n`);

  // 1. Alta del usuario, como la hace la Edge Function.
  const alta = await fetch(`${URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { apikey: secreta, Authorization: `Bearer ${secreta}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: clave, email_confirm: true,
                           user_metadata: { nombre: 'Vendedor de Prueba' } }),
  });
  const creado = await alta.json();
  afirmar(alta.ok && creado.id, 'se crea la cuenta del vendedor');
  usuarioId = creado.id;

  await sql(`
    insert into public.perfiles (id, email, nombre, es_desarrollador)
    values ('${usuarioId}', '${email}', 'Vendedor de Prueba', false)
    on conflict (id) do update set nombre = excluded.nombre;
    insert into public.membresias (usuario_id, agencia_id, rol, activa)
    values ('${usuarioId}', '${agenciaId}', 'vendedor', true)
    on conflict (agencia_id, usuario_id) do update set rol = 'vendedor';`);
  paso(true, 'queda como vendedor de la agencia');

  // 2. Entrar con usuario y clave, como desde la app.
  const login = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: clave }),
  });
  const sesion = await login.json();
  afirmar(login.ok && sesion.access_token, 'entra con esa clave');
  const jwt = sesion.access_token;
  const comoVendedor = { apikey: anon, Authorization: `Bearer ${jwt}` };

  // 3. El inventario que le llega.
  const inv = await (await fetch(
    `${URL}/rest/v1/v_inventario?select=codigo,precio_compra,costo_total,ganancia_estimada,margen_actual,precio_actual,revista_ars&order=codigo&limit=3`,
    { headers: comoVendedor })).json();
  afirmar(Array.isArray(inv) && inv.length > 0, `ve el inventario (${inv.length ?? 0} unidades)`);
  const u = inv[0] ?? {};
  afirmar(u.precio_compra === null, 'NO le llega el precio de compra');
  afirmar(u.costo_total === null, 'NO le llega el costo total');
  afirmar(u.ganancia_estimada === null, 'NO le llega la ganancia');
  afirmar(u.margen_actual === null, 'NO le llega el margen');
  afirmar(u.precio_actual !== null, 'SÍ le llega el precio de venta');

  // 4. Lo que no es suyo no lo ve.
  const otras = await (await fetch(`${URL}/rest/v1/agencias?select=id,nombre`,
    { headers: comoVendedor })).json();
  afirmar(Array.isArray(otras) && otras.length <= 1,
    `solo ve su propia agencia (${otras.length ?? 0})`);

  // 5. Guardar no puede borrar lo que no ve.
  const [{ id: vehId, precio_compra: antes }] = await sql(
    `select id, precio_compra from public.vehiculos where deleted_at is null
      and precio_compra > 0 order by codigo limit 1`);
  const edicion = await fetch(`${URL}/rest/v1/vehiculos?id=eq.${vehId}`, {
    method: 'PATCH',
    headers: { ...comoVendedor, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ observaciones: 'Tocado por la prueba e2e', precio_compra: null }),
  });
  const [{ precio_compra: despues }] = await sql(
    `select precio_compra from public.vehiculos where id = '${vehId}'`);
  afirmar(edicion.ok, 'puede editar la unidad (es vendedor)');
  afirmar(String(antes) === String(despues),
    `el precio de compra sobrevive a su edición (${antes} → ${despues})`);
  await sql(`update public.vehiculos set observaciones = null where id = '${vehId}'`);

  // 6. Dar de alta cuentas es solo del desarrollador.
  const funcion = await fetch(`${URL}/functions/v1/crear-cuenta-agencia`, {
    method: 'POST',
    headers: { ...comoVendedor, 'Content-Type': 'application/json' },
    body: JSON.stringify({ agencia_id: agenciaId, email: 'colado@miagencia.com' }),
  });
  const respuesta = await funcion.json().catch(() => ({}));
  afirmar(funcion.status === 403, `no puede crear cuentas (HTTP ${funcion.status})`);
  afirmar(/desarrollador/i.test(respuesta.error ?? ''), 'y lo dice con todas las letras');

  // 7. Lo mismo pero como solo lectura: no puede ni tocar.
  await sql(`update public.membresias set rol = 'solo_lectura'
              where usuario_id = '${usuarioId}'`);
  const sinPermiso = await fetch(`${URL}/rest/v1/vehiculos?id=eq.${vehId}`, {
    method: 'PATCH',
    headers: { ...comoVendedor, 'Content-Type': 'application/json', Prefer: 'return=representation' },
    body: JSON.stringify({ observaciones: 'no deberia entrar' }),
  });
  const filas = await sinPermiso.json().catch(() => []);
  afirmar(Array.isArray(filas) && filas.length === 0,
    'solo lectura no modifica nada (el RLS filtra)');
} catch (e) {
  fallas++;
  console.error('  ERROR', e.message);
} finally {
  if (usuarioId) {
    await sql(`delete from public.membresias where usuario_id = '${usuarioId}';
               delete from public.perfiles where id = '${usuarioId}';`);
    await fetch(`${URL}/auth/v1/admin/users/${usuarioId}`, {
      method: 'DELETE',
      headers: { apikey: secreta, Authorization: `Bearer ${secreta}` },
    });
    paso(true, 'se borra la cuenta de prueba');
  }
}

console.log(fallas === 0 ? '\nTodo bien.\n' : `\n${fallas} comprobación(es) fallaron.\n`);
process.exit(fallas === 0 ? 0 : 1);
