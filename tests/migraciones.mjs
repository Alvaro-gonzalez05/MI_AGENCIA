// Valida las migraciones ejecutandolas contra un Postgres real (PGlite/WASM).
// No reemplaza a Supabase: sirve para cazar errores de sintaxis y de
// dependencias entre objetos antes de tocar la base de verdad.
import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { unaccent } from '@electric-sql/pglite/contrib/unaccent';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));

const db = await PGlite.create({ extensions: { citext, pg_trgm, pgcrypto, unaccent } });

// Andamios: lo que Supabase ya trae y PGlite no.
await db.exec(`
  create schema if not exists auth;
  create schema if not exists storage;
  create table auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    raw_user_meta_data jsonb default '{}'::jsonb
  );
  create or replace function auth.uid() returns uuid language sql stable
    as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table storage.buckets (
    id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]
  );
  create table storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text, name text, owner uuid
  );
  create or replace function storage.foldername(p text) returns text[]
    language sql immutable as $$ select string_to_array(p, '/') $$;
  create role anon;
  create role authenticated;
  create role service_role;
`);

const archivos = fs.readdirSync(DIR).filter(f => f.endsWith('.sql')).sort();
let fallos = 0;

for (const archivo of archivos) {
  const sql = fs.readFileSync(path.join(DIR, archivo), 'utf8');
  try {
    await db.exec(sql);
    console.log(`  OK   ${archivo}`);
  } catch (e) {
    fallos++;
    console.log(`  FALLA ${archivo}\n        ${String(e.message).split('\n')[0]}`);
    if (e.detail) console.log(`        detalle: ${e.detail}`);
    if (e.hint) console.log(`        pista: ${e.hint}`);
  }
}

console.log(fallos === 0 ? '\nTodas las migraciones corrieron.' : `\n${fallos} migracion(es) con error.`);
process.exit(fallos === 0 ? 0 : 1);
