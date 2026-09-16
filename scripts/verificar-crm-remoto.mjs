// Prueba de integración contra el proyecto de Mi Agencia.
// Usa agencias/usuarios temporales propios; nunca modifica datos de agencias existentes.
// node scripts/verificar-crm-remoto.mjs --deploy | --test-remote
import fs from 'node:fs';
import { randomUUID, randomBytes } from 'node:crypto';

const ref = 'zthpwqcoirrpvslambhz';
const base = `https://${ref}.supabase.co`;
const management = `https://api.supabase.com/v1/projects/${ref}`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
if (!token) throw new Error('Falta SUPABASE_TOKEN_MI_AGENCIA en el entorno.');
const headers = { Authorization: `Bearer ${token}` };
async function request(url, options = {}) {
  const r = await fetch(url, { ...options, signal: AbortSignal.timeout(60000) });
  const text = await r.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${typeof body === 'object' ? JSON.stringify(body) : text.slice(0,200)}`);
  return body;
}
async function query(sql) {
  return request(`${management}/database/query`, { method:'POST',
    headers:{...headers,'Content-Type':'application/json'}, body:JSON.stringify({query:sql}) });
}

if (process.argv.includes('--deploy')) {
  const sql = ['0014_alta_interesados_informes.sql','0015_bcra_evaluacion_responsable.sql']
    .map(f => fs.readFileSync(new URL(`../supabase/migrations/${f}`, import.meta.url),'utf8')).join('\n');
  await query(`begin;\n${sql}\nnotify pgrst, 'reload schema';\ncommit;`);
  console.log('Migraciones CRM e informes aplicadas en una transacción.');
  const form = new FormData();
  form.append('metadata', JSON.stringify({name:'bcra-consulta',entrypoint_path:'index.ts',verify_jwt:true}));
  form.append('file', new Blob([fs.readFileSync(new URL('../supabase/functions/bcra-consulta/index.ts',import.meta.url))],
    {type:'application/typescript'}), 'index.ts');
  const resultado = await request(`${management}/functions/deploy?slug=bcra-consulta`, {method:'POST',headers,body:form});
  console.log(`bcra-consulta: ${resultado.status}, versión ${resultado.version}.`);
  process.exit(0);
}

if (!process.argv.includes('--test-remote')) throw new Error('Elegí --deploy o --test-remote.');
const keys = await request(`${management}/api-keys`, {headers});
const service = keys.find(k => k.name === 'service_role')?.api_key;
const anon = keys.find(k => k.name === 'anon')?.api_key;
if (!service || !anon) throw new Error('No se encontraron las claves necesarias para la prueba aislada.');
const admin = {apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'};
const usuarios = [], agencias = [], objetos = [];
const clientes = [];
function assert(condition, label) { if (!condition) throw new Error(label); console.log(`OK: ${label}`); }
async function post(path, body, auth = admin) {
  return request(`${base}${path}`, {method:'POST',headers:{...auth,Prefer:'return=representation'},body:JSON.stringify(body)});
}
try {
  for (let n=0;n<2;n++) {
    const id = randomUUID();
    const email = `qa-crm-${id}@example.test`;
    const password = randomBytes(24).toString('base64url');
    const user = await post('/auth/v1/admin/users', {email,password,email_confirm:true,user_metadata:{nombre:'Prueba CRM temporal'}});
    usuarios.push(user.id);
    const [agencia] = await post('/rest/v1/agencias',{nombre:'QA CRM temporal',slug:`qa-crm-${id}`});
    agencias.push(agencia.id);
    await post('/rest/v1/membresias',{agencia_id:agencia.id,usuario_id:user.id,rol:'owner',activa:true});
    const sesion = await post('/auth/v1/token?grant_type=password',{email,password},{apikey:anon,'Content-Type':'application/json'});
    clientes.push({apikey:anon,Authorization:`Bearer ${sesion.access_token}`,'Content-Type':'application/json'});
  }
  const a = clientes[0], b = clientes[1];
  const alta = {p_agencia:agencias[0],p_solicitud:randomUUID(),p_datos:{nombre:'BANCO BBVA ARGENTINA S.A. (prueba pública)',cuit:'30500003193',presupuesto_max:15000000}};
  const op = await post('/rest/v1/rpc/crear_interesado',alta,a);
  const retry = await post('/rest/v1/rpc/crear_interesado',alta,a);
  assert(op.id === retry.id && op.cliente_id === retry.cliente_id,'reintento idempotente no duplica el alta');
  const op2 = await post('/rest/v1/rpc/crear_interesado',{...alta,p_solicitud:randomUUID(),p_datos:{...alta.p_datos,nombre:'No sobrescribir persona'}},a);
  assert(op2.cliente_id === op.cliente_id,'CUIT existente reutiliza la persona');
  const personas = await request(`${base}/rest/v1/clientes?id=eq.${op.cliente_id}&select=nombre,acepta_marketing`,{headers:a});
  assert(personas[0].nombre === alta.p_datos.nombre && !personas[0].acepta_marketing,'conserva datos de la persona y no la suscribe a campañas');
  const ajenos = await request(`${base}/rest/v1/oportunidades?id=eq.${op.id}&select=id`,{headers:b});
  assert(ajenos.length === 0,'otra agencia no puede leer el interés');
  let rechazo = false;
  try { await post('/rest/v1/rpc/crear_interesado',{...alta,p_solicitud:randomUUID()},b); } catch { rechazo = true; }
  assert(rechazo,'otra agencia no puede crear en la agencia de prueba');
  const preflight = await fetch(`${base}/functions/v1/bcra-consulta`,{method:'OPTIONS',headers:{Origin:'http://localhost:5410','Access-Control-Request-Headers':'authorization,apikey,x-client-info,content-type'}});
  assert(preflight.ok && preflight.headers.get('access-control-allow-headers')?.includes('apikey'),'CORS permite consultar desde Flutter web');
  let bcraDisponible = true;
  try {
    const bcra = await post('/functions/v1/bcra-consulta',{cliente_id:op.cliente_id,cuit:alta.p_datos.cuit},a);
    assert(bcra.ok && bcra.consulta.cuit === alta.p_datos.cuit,'BCRA real consultado con sesión autenticada');
    const cache = await post('/functions/v1/bcra-consulta',{cliente_id:op.cliente_id,cuit:alta.p_datos.cuit},a);
    assert(cache.cacheada === true,'consulta persistida y recuperada desde caché');
  } catch (e) {
    if (!String(e).includes('HTTP 502')) throw e;
    bcraDisponible = false;
    console.log('PENDIENTE EXTERNO: el BCRA no está disponible; se verifica que no se inventó una evaluación.');
  }
  const vista = await request(`${base}/rest/v1/v_clientes_semaforo?cliente_id=eq.${op.cliente_id}&select=semaforo,consultado_at`,{headers:a});
  assert(vista.length === 1 && (bcraDisponible ? vista[0].consultado_at : !vista[0].consultado_at && vista[0].semaforo === 'sin_datos'),
    bcraDisponible ? 'la ficha recupera la evaluación desde la base' : 'error del BCRA conserva ficha sin asignar un semáforo falso');
  const ruta = `${agencias[0]}/${op.cliente_id}/${op.id}/qa.pdf`;
  const pdf = fs.readFileSync(new URL('../app/build/qa/informe-prueba.pdf',import.meta.url));
  await request(`${base}/storage/v1/object/informes/${ruta}`,{method:'POST',headers:{...a,'Content-Type':'application/pdf','x-upsert':'true'},body:pdf});
  objetos.push(ruta);
  const guardado = await fetch(`${base}/storage/v1/object/authenticated/informes/${ruta}`,{headers:a});
  assert(guardado.ok && Buffer.from(await guardado.arrayBuffer()).equals(pdf),'PDF guardado y descargado sin alteraciones');
  const ajeno = await fetch(`${base}/storage/v1/object/authenticated/informes/${ruta}`,{headers:b});
  assert(!ajeno.ok,'otra agencia no puede descargar el PDF');
  const publico = await fetch(`${base}/storage/v1/object/public/informes/${ruta}`);
  assert(!publico.ok,'el PDF no tiene acceso público');
  const anonimo = await fetch(`${base}/functions/v1/bcra-consulta`,{method:'POST',headers:{apikey:anon,'Content-Type':'application/json'},body:JSON.stringify({cliente_id:op.cliente_id,cuit:alta.p_datos.cuit})});
  assert(!anonimo.ok,'BCRA rechaza consultas sin sesión');
  console.log(bcraDisponible ? 'Integración remota completa.' : 'Alta, permisos, PDF y manejo del error verificados; éxito de BCRA pendiente por indisponibilidad externa.');
} finally {
  // Solo IDs generados y capturados en esta ejecución, nunca por nombre o coincidencias amplias.
  if (objetos.length) await request(`${base}/storage/v1/object/informes`,{method:'DELETE',headers:admin,body:JSON.stringify({prefixes:objetos})});
  for (const id of agencias) await request(`${base}/rest/v1/agencias?id=eq.${id}`,{method:'DELETE',headers:admin});
  for (const id of usuarios) await request(`${base}/auth/v1/admin/users/${id}`,{method:'DELETE',headers:admin});
  console.log('Registros temporales de esta ejecución eliminados.');
}
