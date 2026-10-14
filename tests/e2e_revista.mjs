// El precio de revista pedido en el momento, como lo pide la agencia con el
// cliente enfrente. Corre contra la guía de verdad, así que GASTA UNA de las
// consultas del día: no la dejes en un bucle.
//
// Lo que prueba: que una sola llamada traiga las versiones con su precio,
// que queden guardadas en nuestra copia, y que la próxima búsqueda salga de
// ahí sin volver a preguntar.

const REF = 'zthpwqcoirrpvslambhz';
const URL = `https://${REF}.supabase.co`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
if (!token) { console.error('falta SUPABASE_TOKEN_MI_AGENCIA'); process.exit(1); }

const claves = await (await fetch(
  `https://api.supabase.com/v1/projects/${REF}/api-keys`,
  { headers: { Authorization: `Bearer ${token}` } })).json();
const anon = claves.find((k) => k.name === 'anon').api_key;
const servicio = claves.find((k) => k.name === 'service_role').api_key;
const comoAdmin = { apikey: servicio, Authorization: `Bearer ${servicio}`,
                    'Content-Type': 'application/json' };

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

let fallas = 0;
const afirmar = (ok, texto) => {
  if (!ok) fallas++;
  console.log(`${ok ? '  OK  ' : ' FALLA'} ${texto}`);
};

const sello = Date.now();
const email = `prueba.revista.${sello}@miagencia.com`;
const clave = 'Prueba-' + Math.random().toString(36).slice(2, 10);
let usuarioId = null;

// Un auto que no estaba: si se prueba con uno ya guardado, no se prueba nada.
const BUSCADO = 'peugeot 208 feline';

try {
  const [{ id: agenciaId }] =
    await sql(`select id from public.agencias order by created_at limit 1`);

  const alta = await fetch(`${URL}/auth/v1/admin/users`, {
    method: 'POST', headers: comoAdmin,
    body: JSON.stringify({ email, password: clave, email_confirm: true,
                           user_metadata: { nombre: 'Prueba Revista' } }),
  });
  const creado = await alta.json();
  usuarioId = creado.id;
  await sql(`
    insert into public.perfiles (id, email, nombre, es_desarrollador)
    values ('${usuarioId}', '${email}', 'Prueba Revista', false)
    on conflict (id) do nothing;
    insert into public.membresias (usuario_id, agencia_id, rol, activa)
    values ('${usuarioId}', '${agenciaId}', 'vendedor', true)
    on conflict (agencia_id, usuario_id) do nothing;`);

  const login = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: clave }),
  });
  const jwt = (await login.json()).access_token;
  afirmar(Boolean(jwt), 'entra un vendedor cualquiera');
  const como = { apikey: anon, Authorization: `Bearer ${jwt}`,
                 'Content-Type': 'application/json' };

  const [cupoAntes] = await sql(`select * from public.cupo_revista()`);
  console.log(`\n  Cupo del día antes: ${cupoAntes.quedan} de ${cupoAntes.limite}\n`);

  const r = await fetch(`${URL}/functions/v1/revista-buscar`, {
    method: 'POST', headers: como, body: JSON.stringify({ q: BUSCADO }),
  });
  const datos = await r.json();
  afirmar(r.ok, `la guía contesta (HTTP ${r.status})`);
  if (datos.agotado) {
    console.log('  (se acabó el cupo del día: el resto no se puede probar)');
  } else {
    afirmar((datos.guardadas ?? 0) > 1,
      `una sola consulta deja ${datos.guardadas} precios guardados`);
    afirmar(datos.quedan >= 0, `quedan ${datos.quedan} consultas hoy`);

    // Y ahora sale de nuestra copia, instantáneo y sin gastar cupo.
    const encontrados = await (await fetch(
      `${URL}/rest/v1/rpc/buscar_revista`,
      { method: 'POST', headers: como,
        body: JSON.stringify({ p_texto: BUSCADO, p_tope: 5 }) })).json();
    afirmar(Array.isArray(encontrados) && encontrados.length > 0,
      `la app lo encuentra en nuestra copia (${encontrados.length ?? 0})`);
    if (encontrados[0]) {
      const x = encontrados[0];
      console.log(`      ${x.marca} ${x.modelo} ${x.version} ${x.anio}: ` +
                  `$${Math.round(x.precio_ars).toLocaleString('es-AR')}`);
      afirmar(Number(x.precio_ars) > 1000000,
        'y el precio está en pesos, no en dólares');
    }

    const [cupoDespues] = await sql(`select * from public.cupo_revista()`);
    afirmar(cupoDespues.quedan === cupoAntes.quedan - 1,
      'gastó exactamente una consulta');
  }

  // Un texto corto no gasta cupo: se rechaza antes.
  const corto = await fetch(`${URL}/functions/v1/revista-buscar`, {
    method: 'POST', headers: como, body: JSON.stringify({ q: 'a' }),
  });
  afirmar(corto.status === 400, 'un texto de una letra se rechaza sin gastar');
} catch (e) {
  fallas++;
  console.error('  ERROR', e.message);
} finally {
  if (usuarioId) {
    await sql(`delete from public.membresias where usuario_id = '${usuarioId}';
               delete from public.perfiles where id = '${usuarioId}';`);
    await fetch(`${URL}/auth/v1/admin/users/${usuarioId}`,
      { method: 'DELETE', headers: comoAdmin });
    console.log('  OK   se borra la cuenta de prueba');
  }
}

console.log(fallas === 0 ? '\nTodo bien.\n' : `\n${fallas} comprobación(es) fallaron.\n`);
process.exit(fallas === 0 ? 0 : 1);
