// Corre SQL contra el proyecto por la Management API. El token sale del
// entorno y nunca se imprime.
import { readFileSync } from 'node:fs';

const REF = 'zthpwqcoirrpvslambhz';
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;
if (!token) { console.error('falta SUPABASE_TOKEN_MI_AGENCIA'); process.exit(1); }

const arg = process.argv[2];
const query = arg?.startsWith('@') ? readFileSync(arg.slice(1), 'utf8') : arg;
if (!query) { console.error('uso: node sql.mjs "select 1" | @archivo.sql'); process.exit(1); }

const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query }),
});
const texto = await r.text();
if (!r.ok) { console.error('HTTP', r.status, texto); process.exit(1); }
console.log(texto);
