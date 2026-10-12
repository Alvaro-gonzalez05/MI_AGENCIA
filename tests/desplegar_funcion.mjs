// Despliega una Edge Function por la Management API (no hay CLI de Supabase
// en esta máquina). El endpoint JSON devuelve 500; el multipart anda.
import { readFileSync } from 'node:fs';

const REF = 'zthpwqcoirrpvslambhz';
const slug = process.argv[2];
const archivo = `supabase/functions/${slug}/index.ts`;
const token = process.env.SUPABASE_TOKEN_MI_AGENCIA;

const cuerpo = new FormData();
cuerpo.append('metadata', JSON.stringify({
  name: slug, entrypoint_path: 'index.ts', verify_jwt: true,
}));
cuerpo.append('file', new Blob([readFileSync(archivo)], {
  type: 'application/typescript',
}), 'index.ts');

const r = await fetch(
  `https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=${slug}`,
  { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: cuerpo });
const t = await r.text();
if (!r.ok) { console.error('HTTP', r.status, t); process.exit(1); }
const j = JSON.parse(t);
console.log(`${j.slug}: ${j.status}, versión ${j.version}`);
