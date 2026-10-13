// Prueba de punta a punta del equipo de una agencia: el dueño da de alta a
// su gente, la reparte en zonas, les cambia la clave cuando se pierde y les
// saca el acceso. Corre contra Supabase de verdad y borra todo al final.
//
// Lo que más importa acá no es que funcione: es que NO funcione lo que no
// tiene que funcionar. Un administrador que se asciende a dueño, o un
// vendedor que se da de alta un usuario, serían agujeros de los que no se
// vuelve.

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
const creados = [];

const crearUsuario = async (email, clave, nombre) => {
  const r = await fetch(`${URL}/auth/v1/admin/users`, {
    method: 'POST', headers: comoAdmin,
    body: JSON.stringify({ email, password: clave, email_confirm: true,
                           user_metadata: { nombre } }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`alta ${r.status}: ${JSON.stringify(j).slice(0, 200)}`);
  creados.push(j.id);
  return j.id;
};

const entrar = async (email, clave) => {
  const r = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: clave }),
  });
  const j = await r.json();
  return r.ok ? j.access_token : null;
};

const como = (jwt) => ({ apikey: anon, Authorization: `Bearer ${jwt}`,
                         'Content-Type': 'application/json' });

const funcion = async (jwt, cuerpo) => {
  const r = await fetch(`${URL}/functions/v1/crear-cuenta-agencia`, {
    method: 'POST', headers: como(jwt), body: JSON.stringify(cuerpo),
  });
  return { status: r.status, datos: await r.json().catch(() => ({})) };
};

try {
  const [{ id: agenciaId, nombre: agenciaNombre }] =
    await sql(`select id, nombre from public.agencias order by created_at limit 1`);
  console.log(`\nAgencia: ${agenciaNombre}\n`);

  // --- El dueño, que damos de alta nosotros ---------------------------
  const emailDueno = `prueba.dueno.${sello}@miagencia.com`;
  const claveDueno = 'Prueba-' + Math.random().toString(36).slice(2, 10);
  const duenoId = await crearUsuario(emailDueno, claveDueno, 'Dueño de Prueba');
  await sql(`
    update public.perfiles set nombre = 'Dueño de Prueba' where id = '${duenoId}';
    insert into public.membresias (usuario_id, agencia_id, rol, activa)
    values ('${duenoId}', '${agenciaId}', 'owner', true)
    on conflict (agencia_id, usuario_id) do update set rol = 'owner';`);
  const jwtDueno = await entrar(emailDueno, claveDueno);
  afirmar(Boolean(jwtDueno), 'el dueño entra con su clave');

  const [{ id: zonaVentas }] = await sql(
    `select id from public.zonas where agencia_id = '${agenciaId}'
      and nombre = 'Ventas' limit 1`);

  // --- El dueño da de alta a un vendedor, en una zona -----------------
  const emailVend = `prueba.vendedor.${sello}@miagencia.com`;
  const alta = await funcion(jwtDueno, {
    agencia_id: agenciaId, email: emailVend, nombre: 'Vendedor de Prueba',
    rol: 'vendedor', zona_id: zonaVentas,
  });
  afirmar(alta.status === 200, `el dueño crea la cuenta de su vendedor (HTTP ${alta.status})`);
  if (alta.datos.usuario_id) creados.push(alta.datos.usuario_id);
  afirmar(Boolean(alta.datos.clave), 'con su clave para dictarle');
  afirmar(alta.datos.zona_id === zonaVentas, 'y queda en la zona que eligió');
  const jwtVend = await entrar(emailVend, alta.datos.clave);
  afirmar(Boolean(jwtVend), 'el vendedor entra con esa clave');

  // --- Un administrador, creado por el dueño --------------------------
  const emailAdmin = `prueba.admin.${sello}@miagencia.com`;
  const altaAdmin = await funcion(jwtDueno, {
    agencia_id: agenciaId, email: emailAdmin, nombre: 'Admin de Prueba',
    rol: 'admin',
  });
  afirmar(altaAdmin.status === 200, 'el dueño crea un administrador');
  if (altaAdmin.datos.usuario_id) creados.push(altaAdmin.datos.usuario_id);
  const jwtAdmin = await entrar(emailAdmin, altaAdmin.datos.clave);

  // --- Lo que NO tiene que poder hacer cada uno -----------------------
  const intentoDueno = await funcion(jwtAdmin, {
    agencia_id: agenciaId, email: `colado.${sello}@miagencia.com`,
    nombre: 'Colado', rol: 'owner',
  });
  afirmar(intentoDueno.status === 403,
    `un administrador no nombra dueños (HTTP ${intentoDueno.status})`);

  const intentoVend = await funcion(jwtVend, {
    agencia_id: agenciaId, email: `colado2.${sello}@miagencia.com`,
    nombre: 'Colado', rol: 'vendedor',
  });
  afirmar(intentoVend.status === 403,
    `un vendedor no da de alta a nadie (HTTP ${intentoVend.status})`);

  const [{ id: memAdmin }] = await sql(
    `select id from public.membresias where usuario_id = '${altaAdmin.datos.usuario_id}'`);
  const ascenso = await fetch(`${URL}/rest/v1/membresias?id=eq.${memAdmin}`, {
    method: 'PATCH', headers: { ...como(jwtAdmin), Prefer: 'return=representation' },
    body: JSON.stringify({ rol: 'owner' }),
  });
  const [{ rol: rolAhora }] = await sql(
    `select rol from public.membresias where id = '${memAdmin}'`);
  afirmar(rolAhora === 'admin',
    `un administrador no se asciende solo (quedó ${rolAhora}, HTTP ${ascenso.status})`);

  // --- Claves nuevas --------------------------------------------------
  const nuevaDelVendedor = await funcion(jwtDueno, {
    accion: 'nueva_clave', agencia_id: agenciaId,
    usuario_id: alta.datos.usuario_id,
  });
  afirmar(nuevaDelVendedor.status === 200, 'el dueño le genera una clave nueva al vendedor');
  afirmar(Boolean(await entrar(emailVend, nuevaDelVendedor.datos.clave)),
    'y el vendedor entra con la nueva');
  afirmar((await entrar(emailVend, alta.datos.clave)) === null,
    'la vieja ya no sirve');

  const intentoClave = await funcion(jwtAdmin, {
    accion: 'nueva_clave', agencia_id: agenciaId, usuario_id: duenoId,
  });
  afirmar(intentoClave.status === 403,
    `un administrador no le cambia la clave al dueño (HTTP ${intentoClave.status})`);

  // --- Zonas ----------------------------------------------------------
  const zonaNueva = await fetch(`${URL}/rest/v1/zonas`, {
    method: 'POST', headers: { ...como(jwtDueno), Prefer: 'return=representation' },
    body: JSON.stringify({ agencia_id: agenciaId, nombre: `Playa ${sello}`,
                           icono: 'truck', x: 100, y: 100 }),
  });
  const [zona] = await zonaNueva.json();
  afirmar(zonaNueva.ok && zona?.id, 'el dueño crea una zona');

  const zonaDelVendedor = await fetch(`${URL}/rest/v1/zonas`, {
    method: 'POST', headers: { ...como(jwtVend), Prefer: 'return=representation' },
    body: JSON.stringify({ agencia_id: agenciaId, nombre: `Colada ${sello}`,
                           icono: 'folder' }),
  });
  afirmar(!zonaDelVendedor.ok, `un vendedor no crea zonas (HTTP ${zonaDelVendedor.status})`);

  const [{ id: memVend }] = await sql(
    `select id from public.membresias where usuario_id = '${alta.datos.usuario_id}'`);
  const mover = await fetch(`${URL}/rest/v1/rpc/mover_a_zona`, {
    method: 'POST', headers: como(jwtDueno),
    body: JSON.stringify({ p_membresia: memVend, p_zona: zona.id }),
  });
  afirmar(mover.ok, 'arrastra al vendedor a la zona nueva');

  const moverMal = await fetch(`${URL}/rest/v1/rpc/mover_a_zona`, {
    method: 'POST', headers: como(jwtVend),
    body: JSON.stringify({ p_membresia: memVend, p_zona: zonaVentas }),
  });
  afirmar(!moverMal.ok, `un vendedor no se cambia de zona solo (HTTP ${moverMal.status})`);

  // Borrar la zona no puede dejar a nadie afuera.
  const borrada = await fetch(`${URL}/rest/v1/zonas?id=eq.${zona.id}`, {
    method: 'DELETE', headers: como(jwtDueno),
  });
  const [{ zona_id: zonaDespues, activa }] = await sql(
    `select zona_id, activa from public.membresias where id = '${memVend}'`);
  afirmar(borrada.ok && zonaDespues === null && activa === true,
    'al borrar la zona, su gente queda sin zona pero con acceso');

  // --- La pizarra, como la ve el vendedor -----------------------------
  const equipo = await (await fetch(
    `${URL}/rest/v1/v_equipo?select=nombre,rol,zona_nombre,ve_plata,activa`,
    { headers: como(jwtVend) })).json();
  afirmar(Array.isArray(equipo) && equipo.length >= 3,
    `el vendedor ve a su equipo (${equipo.length ?? 0} personas)`);
  afirmar(equipo.some((p) => p.rol === 'vendedor' && p.ve_plata === false),
    'y la pizarra ya trae quién ve la plata y quién no');

  // --- Sacarle el acceso ----------------------------------------------
  const baja = await fetch(`${URL}/rest/v1/membresias?id=eq.${memVend}`, {
    method: 'PATCH', headers: como(jwtDueno),
    body: JSON.stringify({ activa: false }),
  });
  const [{ activa: sigue }] = await sql(
    `select activa from public.membresias where id = '${memVend}'`);
  afirmar(baja.ok && sigue === false, 'el dueño le saca el acceso');
  const inv = await (await fetch(`${URL}/rest/v1/v_inventario?select=codigo&limit=1`,
    { headers: como(jwtVend) })).json();
  afirmar(Array.isArray(inv) && inv.length === 0,
    'y desde ese momento no ve más el inventario');
  const [{ n: perfilSigue }] = await sql(
    `select count(*) as n from public.perfiles where id = '${alta.datos.usuario_id}'`);
  afirmar(Number(perfilSigue) === 1,
    'pero la persona sigue existiendo: su historial no queda huérfano');
} catch (e) {
  fallas++;
  console.error('  ERROR', e.message);
} finally {
  await sql(`delete from public.zonas where nombre like '%${sello}%';`);
  for (const id of creados) {
    await sql(`delete from public.membresias where usuario_id = '${id}';
               delete from public.perfiles where id = '${id}';`);
    await fetch(`${URL}/auth/v1/admin/users/${id}`,
      { method: 'DELETE', headers: comoAdmin });
  }
  console.log('  OK   se borra todo lo de la prueba');
}

console.log(fallas === 0 ? '\nTodo bien.\n' : `\n${fallas} comprobación(es) fallaron.\n`);
process.exit(fallas === 0 ? 0 : 1);
