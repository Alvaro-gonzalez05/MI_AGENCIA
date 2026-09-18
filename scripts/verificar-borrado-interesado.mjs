// Prueba el RPC de borrado contra Supabase con una agencia temporal.
// Crea dos oportunidades para la misma persona: la primera debe conservarla
// y la segunda debe borrar también su ficha. Todo se limpia al terminar.
import { randomBytes, randomUUID } from 'node:crypto';

const ref = 'zthpwqcoirrpvslambhz';
const base = `https://${ref}.supabase.co`;
const management = `https://api.supabase.com/v1/projects/${ref}`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
if (!token) throw new Error('Falta SUPABASE_TOKEN_MI_AGENCIA.');

async function pedir(url, options = {}) {
  const respuesta = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(60000),
  });
  const texto = await respuesta.text();
  const cuerpo = texto ? JSON.parse(texto) : null;
  if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}: ${texto}`);
  return cuerpo;
}

const keys = await pedir(`${management}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` },
});
const service = keys.find((key) => key.name === 'service_role')?.api_key;
const publica = keys.find((key) => key.name === 'anon')?.api_key ??
  keys.find((key) => key.type === 'publishable')?.api_key;
if (!service || !publica) throw new Error('No se encontraron las API keys.');

const admin = {
  apikey: service,
  Authorization: `Bearer ${service}`,
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
};
const marca = randomUUID();
const email = `qa-borrado-${marca}@example.test`;
const password = `Qa!${randomBytes(18).toString('base64url')}7`;
let userId;
let agenciaId;

try {
  const usuario = await pedir(`${base}/auth/v1/admin/users`, {
    method: 'POST', headers: admin,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  userId = usuario.id;
  const agencias = await pedir(`${base}/rest/v1/agencias`, {
    method: 'POST', headers: admin,
    body: JSON.stringify({ nombre: 'QA borrado', slug: `qa-borrado-${marca}` }),
  });
  agenciaId = agencias[0]?.id;
  await pedir(`${base}/rest/v1/membresias`, {
    method: 'POST', headers: admin,
    body: JSON.stringify({ agencia_id: agenciaId, usuario_id: userId, rol: 'owner', activa: true }),
  });

  const sesion = await pedir(`${base}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: publica, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const usuarioHeaders = {
    apikey: publica,
    Authorization: `Bearer ${sesion.access_token}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };
  const [cliente] = await pedir(`${base}/rest/v1/clientes`, {
    method: 'POST', headers: usuarioHeaders,
    body: JSON.stringify({ agencia_id: agenciaId, nombre: 'Persona QA', cuit: '30500003193' }),
  });
  const oportunidades = await pedir(`${base}/rest/v1/oportunidades`, {
    method: 'POST', headers: usuarioHeaders,
    body: JSON.stringify([
      { agencia_id: agenciaId, cliente_id: cliente.id },
      { agencia_id: agenciaId, cliente_id: cliente.id },
    ]),
  });

  const borrar = (id) => pedir(`${base}/rest/v1/rpc/eliminar_interesado`, {
    method: 'POST', headers: usuarioHeaders,
    body: JSON.stringify({ p_oportunidad: id }),
  });
  const primero = await borrar(oportunidades[0].id);
  const trasPrimero = await pedir(`${base}/rest/v1/clientes?id=eq.${cliente.id}&select=id`, { headers: admin });
  const segundo = await borrar(oportunidades[1].id);
  const trasSegundo = await pedir(`${base}/rest/v1/clientes?id=eq.${cliente.id}&select=id`, { headers: admin });

  if (primero !== false || trasPrimero.length !== 1 || segundo !== true || trasSegundo.length !== 0) {
    throw new Error('El borrado no conservó/eliminó al cliente como correspondía.');
  }
  console.log('OK: conserva al cliente con otro interés y lo elimina con el último.');
} finally {
  if (agenciaId) await pedir(`${base}/rest/v1/agencias?id=eq.${agenciaId}`, { method: 'DELETE', headers: admin });
  if (userId) await pedir(`${base}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: admin });
}
