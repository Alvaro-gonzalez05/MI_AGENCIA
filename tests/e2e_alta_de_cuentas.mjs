// Segunda parte de la prueba: dar de alta la cuenta de una agencia, como lo
// hace el botón de la pantalla de Agencias, y después entrar con el usuario
// y la clave que devuelve. Al final se borra todo lo que creó.

const REF = 'zthpwqcoirrpvslambhz';
const URL = `https://${REF}.supabase.co`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;

const claves = await (await fetch(
  `https://api.supabase.com/v1/projects/${REF}/api-keys`,
  { headers: { Authorization: `Bearer ${token}` } })).json();
const anon = claves.find((k) => k.name === 'anon').api_key;
const servicio = claves.find((k) => k.name === 'service_role').api_key;

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

const comoAdmin = { apikey: servicio, Authorization: `Bearer ${servicio}`,
                    'Content-Type': 'application/json' };

let fallas = 0;
const afirmar = (ok, texto) => {
  if (!ok) fallas++;
  console.log(`${ok ? '  OK  ' : ' FALLA'} ${texto}`);
};

const sello = Date.now();
const emailDev = `prueba.dev.${sello}@miagencia.com`;
const claveDev = 'Prueba-' + Math.random().toString(36).slice(2, 10);
const emailAgencia = `prueba.agencia.${sello}@miagencia.com`;
let devId = null;
let nuevoId = null;

const crearUsuario = async (email, password, nombre) => {
  const r = await fetch(`${URL}/auth/v1/admin/users`, {
    method: 'POST', headers: comoAdmin,
    body: JSON.stringify({ email, password, email_confirm: true,
                           user_metadata: { nombre } }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`alta ${r.status}: ${JSON.stringify(j).slice(0, 200)}`);
  return j.id;
};

const entrar = async (email, password) => {
  const r = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const j = await r.json();
  return r.ok ? j.access_token : null;
};

try {
  const [{ id: agenciaId, nombre: agenciaNombre }] =
    await sql(`select id, nombre from public.agencias order by created_at limit 1`);
  console.log(`\nAgencia: ${agenciaNombre}\n`);

  // Una cuenta de desarrollador de mentira, para no usar la de Álvaro.
  devId = await crearUsuario(emailDev, claveDev, 'Desarrollador de Prueba');
  await sql(`update public.perfiles set es_desarrollador = true where id = '${devId}'`);
  const jwtDev = await entrar(emailDev, claveDev);
  afirmar(Boolean(jwtDev), 'entra la cuenta de desarrollador');

  // El botón "dar de alta la cuenta" de la pantalla de Agencias.
  const r = await fetch(`${URL}/functions/v1/crear-cuenta-agencia`, {
    method: 'POST',
    headers: { apikey: anon, Authorization: `Bearer ${jwtDev}`,
               'Content-Type': 'application/json' },
    body: JSON.stringify({ agencia_id: agenciaId, email: emailAgencia,
                           nombre: 'Cuenta de Prueba', rol: 'owner' }),
  });
  const cuenta = await r.json();
  afirmar(r.ok, `la función contesta bien (HTTP ${r.status})`);
  if (!r.ok) console.log('   ', JSON.stringify(cuenta).slice(0, 300));
  afirmar(cuenta.email === emailAgencia, 'devuelve el usuario que pedimos');
  afirmar(typeof cuenta.clave === 'string' && cuenta.clave.length >= 8,
    `devuelve una clave para dictar (${cuenta.clave?.length} caracteres)`);
  afirmar(!/[0OlI1]/.test(cuenta.clave ?? 'O'),
    'sin los caracteres que se confunden al dictarla');
  afirmar(cuenta.ya_existia === false, 'dice que la cuenta es nueva');
  afirmar(cuenta.agencia === agenciaNombre, 'y de qué agencia es');

  // Lo que importa de verdad: que con eso se entre.
  const jwtNuevo = await entrar(emailAgencia, cuenta.clave);
  afirmar(Boolean(jwtNuevo), 'el cliente entra con ese usuario y esa clave');

  const estado = await sql(`
    select p.nombre, p.email, p.es_desarrollador, m.rol, m.activa
      from public.perfiles p
      join public.membresias m on m.usuario_id = p.id
     where p.email = '${emailAgencia}'`);
  afirmar(estado.length === 1, 'queda una sola membresía');
  afirmar(estado[0]?.rol === 'owner', 'con el rol que elegimos (dueño)');
  afirmar(estado[0]?.es_desarrollador === false, 'y sin permisos de plataforma');
  afirmar(estado[0]?.nombre === 'Cuenta de Prueba',
    `con el nombre que escribimos (${estado[0]?.nombre})`);

  const [{ id: nid }] = await sql(
    `select id from public.perfiles where email = '${emailAgencia}'`);
  nuevoId = nid;

  // Como dueña, esa cuenta sí ve la plata.
  const inv = await (await fetch(
    `${URL}/rest/v1/v_inventario?select=codigo,precio_compra,ganancia_estimada&limit=1`,
    { headers: { apikey: anon, Authorization: `Bearer ${jwtNuevo}` } })).json();
  afirmar(inv[0]?.precio_compra !== null && inv[0]?.precio_compra !== undefined,
    'y como dueña sí ve el precio de compra');

  // Repetir el alta con el mismo email no le cambia la clave.
  const otra = await (await fetch(`${URL}/functions/v1/crear-cuenta-agencia`, {
    method: 'POST',
    headers: { apikey: anon, Authorization: `Bearer ${jwtDev}`,
               'Content-Type': 'application/json' },
    body: JSON.stringify({ agencia_id: agenciaId, email: emailAgencia,
                           nombre: 'Cuenta de Prueba', rol: 'owner' }),
  })).json();
  afirmar(otra.ya_existia === true, 'si la cuenta ya existía, lo avisa');
  afirmar(otra.clave === null, 'y no le cambia la clave');
  afirmar(Boolean(await entrar(emailAgencia, cuenta.clave)),
    'la clave vieja sigue sirviendo');
} catch (e) {
  fallas++;
  console.error('  ERROR', e.message);
} finally {
  for (const id of [devId, nuevoId].filter(Boolean)) {
    await sql(`delete from public.membresias where usuario_id = '${id}';
               delete from public.perfiles where id = '${id}';`);
    await fetch(`${URL}/auth/v1/admin/users/${id}`,
      { method: 'DELETE', headers: comoAdmin });
  }
  console.log('  OK   se borran las cuentas de prueba');
}

console.log(fallas === 0 ? '\nTodo bien.\n' : `\n${fallas} comprobación(es) fallaron.\n`);
process.exit(fallas === 0 ? 0 : 1);
