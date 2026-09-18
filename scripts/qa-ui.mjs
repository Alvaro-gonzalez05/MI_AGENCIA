// Crea una cuenta aislada para recorrer la interfaz contra Supabase y la
// elimina por sus IDs exactos al terminar. Nunca toca una agencia existente.
//
//   node scripts/qa-ui.mjs --create
//   node scripts/qa-ui.mjs --cleanup
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';

const ref = 'zthpwqcoirrpvslambhz';
const base = `https://${ref}.supabase.co`;
const management = `https://api.supabase.com/v1/projects/${ref}`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
const statePath = path.join(os.tmpdir(), 'mi-agencia-qa-ui.json');

if (!token) throw new Error('Falta SUPABASE_TOKEN_MI_AGENCIA en el entorno.');

async function request(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(60000),
  });
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${typeof body === 'object' ? JSON.stringify(body) : text.slice(0, 200)}`);
  }
  return body;
}

const keys = await request(`${management}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` },
});
const service = keys.find((key) => key.name === 'service_role')?.api_key;
if (!service) throw new Error('No se encontró service_role.');
const admin = {
  apikey: service,
  Authorization: `Bearer ${service}`,
  'Content-Type': 'application/json',
};

async function post(endpoint, body) {
  return request(`${base}${endpoint}`, {
    method: 'POST',
    headers: { ...admin, Prefer: 'return=representation' },
    body: JSON.stringify(body),
  });
}

if (process.argv.includes('--create')) {
  if (fs.existsSync(statePath)) {
    throw new Error(`Ya existe una sesión QA en ${statePath}. Ejecutá --cleanup.`);
  }
  const marker = randomUUID();
  const email = `qa-ui-${marker}@example.test`;
  const password = `Qa!${randomBytes(18).toString('base64url')}9`;
  let user;
  let agency;
  try {
    user = await post('/auth/v1/admin/users', {
      email,
      password,
      email_confirm: true,
      user_metadata: { nombre: 'Vendedor QA temporal' },
    });
    [agency] = await post('/rest/v1/agencias', {
      nombre: 'Agencia QA temporal',
      slug: `qa-ui-${marker}`,
    });
    await post('/rest/v1/membresias', {
      agencia_id: agency.id,
      usuario_id: user.id,
      rol: 'owner',
      activa: true,
    });
    const state = {
      userId: user.id,
      agencyId: agency.id,
      email,
      password,
      createdAt: new Date().toISOString(),
    };
    fs.writeFileSync(statePath, JSON.stringify(state), { mode: 0o600 });
    console.log(JSON.stringify({ statePath, email, password }));
  } catch (error) {
    if (agency?.id) {
      await request(`${base}/rest/v1/agencias?id=eq.${agency.id}`, {
        method: 'DELETE',
        headers: admin,
      });
    }
    if (user?.id) {
      await request(`${base}/auth/v1/admin/users/${user.id}`, {
        method: 'DELETE',
        headers: admin,
      });
    }
    throw error;
  }
} else if (process.argv.includes('--cleanup')) {
  if (!fs.existsSync(statePath)) {
    console.log('No hay una sesión QA pendiente.');
    process.exit(0);
  }
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  await request(`${base}/rest/v1/agencias?id=eq.${state.agencyId}`, {
    method: 'DELETE',
    headers: admin,
  });
  await request(`${base}/auth/v1/admin/users/${state.userId}`, {
    method: 'DELETE',
    headers: admin,
  });
  fs.rmSync(statePath);
  console.log('Cuenta y agencia QA eliminadas.');
} else {
  throw new Error('Usá --create o --cleanup.');
}
