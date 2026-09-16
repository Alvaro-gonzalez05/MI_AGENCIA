// Corre los casos de casos_semaforo.json contra Postgres de verdad
// (PGlite/WASM), con todas las migraciones aplicadas.
//
// Prueba las DOS piezas que deciden el color:
//   public.semaforo_de_situacion(...)  -> que significa una situacion
//   public.v_clientes_semaforo         -> quien fue consultado y quien no
//
// La segunda importa tanto como la primera: el BCRA devuelve 404 igual para
// "no tiene deudas" que para "no existe", y si la vista las tratara igual,
// a alguien limpio le apareceria "Sin consultar" para siempre.
//
// El mismo archivo de casos lo corre app/test/bcra_test.dart contra el Dart.
import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { unaccent } from '@electric-sql/pglite/contrib/unaccent';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));
const CASOS = fileURLToPath(new URL('./casos_semaforo.json', import.meta.url));

const db = await PGlite.create({ extensions: { citext, pg_trgm, pgcrypto, unaccent } });

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

for (const archivo of fs.readdirSync(DIR).filter(f => f.endsWith('.sql')).sort()) {
  await db.exec(fs.readFileSync(path.join(DIR, archivo), 'utf8'));
}

// RLS apagado: aca se prueba el criterio del semaforo, no quien puede verlo.
// De eso se encarga la suite de politicas.
await db.exec(`
  alter table public.agencias      disable row level security;
  alter table public.clientes      disable row level security;
  alter table public.bcra_consultas disable row level security;
`);

const { casos } = JSON.parse(fs.readFileSync(CASOS, 'utf8'));

const { rows: [{ id: agencia }] } = await db.query(
  `insert into public.agencias (nombre, slug) values ('Test', 'test') returning id`,
);

let fallos = 0;
let corridos = 0;

console.log('Semaforo crediticio — criterio en SQL\n');

for (const c of casos) {
  const {
    caso,
    consultado = true,
    situacion = null,
    entidades = 1,
    chequesSinPagar = 0,
    chequesRechazados = false,
    procesoJudicial = false,
    diasAtraso = 0,
    esperado,
  } = c;

  const { rows: [{ id: cliente }] } = await db.query(
    `insert into public.clientes (agencia_id, nombre, cuit) values ($1, $2, $3) returning id`,
    [agencia, caso.slice(0, 60), String(20000000000 + corridos)],
  );

  if (consultado) {
    await db.query(
      `insert into public.bcra_consultas
         (agencia_id, cliente_id, cuit, situacion_maxima, cantidad_entidades,
          cheques_sin_pagar, tiene_cheques_rechazados, tiene_proceso_judicial,
          dias_atraso_max)
       values ($1, $2, (select cuit from public.clientes where id=$2), $3, $4, $5, $6, $7, $8)`,
      [agencia, cliente, entidades === 0 ? null : situacion, entidades,
       chequesSinPagar, chequesRechazados, procesoJudicial, diasAtraso],
    );
  }

  const { rows: [fila] } = await db.query(
    `select semaforo::text, sin_deudas_informadas
       from public.v_clientes_semaforo where cliente_id = $1`,
    [cliente],
  );

  corridos++;
  if (fila.semaforo === esperado) {
    console.log(`  OK    ${caso}  ->  ${esperado}`);
  } else {
    fallos++;
    console.log(`  FALLA ${caso}`);
    console.log(`        esperado ${esperado}, la base dijo ${fila.semaforo}`);
  }

  // La bandera que separa "sin deudas" de "sin consultar" tambien se afirma:
  // es la que decide si el informe dice "limpio" o "no sabemos".
  const sinDeudasEsperado = consultado && entidades === 0;
  if (fila.sin_deudas_informadas !== sinDeudasEsperado) {
    fallos++;
    console.log(`  FALLA ${caso}`);
    console.log(`        sin_deudas_informadas: esperado ${sinDeudasEsperado},`
      + ` la base dijo ${fila.sin_deudas_informadas}`);
  }
}

// La funcion suelta, sin pasar por la vista: es la que puede llamar cualquier
// consulta SQL a mano, asi que tiene que sostener el criterio por si sola.
const sueltos = [
  [null, 0, false, false, 0, 'sin_datos'],
  [1, 0, false, false, 0, 'verde'],
  [2, 0, false, false, 0, 'amarillo'],
  [3, 0, false, false, 0, 'amarillo'],
  [4, 0, false, false, 0, 'rojo'],
  [6, 0, false, false, 0, 'rojo'],
  [1, 1, true, false, 0, 'rojo'],
  [1, 0, false, true, 0, 'rojo'],
  [1, 0, false, false, 31, 'amarillo'],
];

console.log('\nLa funcion semaforo_de_situacion por separado\n');

for (const [sit, sinPagar, tieneCheques, judicial, atraso, esperado] of sueltos) {
  const { rows: [{ r }] } = await db.query(
    `select public.semaforo_de_situacion($1::smallint, $2::smallint, $3, $4, $5::smallint)::text as r`,
    [sit, sinPagar, tieneCheques, judicial, atraso],
  );
  corridos++;
  if (r === esperado) {
    console.log(`  OK    situacion ${sit ?? 'null'} -> ${r}`);
  } else {
    fallos++;
    console.log(`  FALLA situacion ${sit ?? 'null'}: esperado ${esperado}, dio ${r}`);
  }
}

console.log(
  fallos === 0
    ? `\n${corridos} comprobaciones, todas OK.`
    : `\n${fallos} de ${corridos} comprobaciones fallaron.`,
);
process.exit(fallos === 0 ? 0 : 1);
