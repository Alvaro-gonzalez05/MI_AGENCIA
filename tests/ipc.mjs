// La carga de la serie del IPC (public.cargar_ipc, migración 0018) y su
// efecto en el motor de cálculo, contra Postgres de verdad (PGlite).
//
// Reproduce el caso del checklist del cliente (punto 1.1): "cargar un auto
// que entró hace varios meses, con un gasto viejo (misma época) y uno
// reciente (mes pasado), y confirmar que Ganancia real (IPC) queda por debajo
// de la nominal, con un ajuste distinto para cada gasto según su fecha".
//
// Los niveles del índice son los oficiales del INDEC (datos.gob.ar, base
// dic-2016), recortados a los meses que hacen falta.
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

await db.exec(`
  create schema if not exists auth;
  create schema if not exists storage;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text,
    raw_user_meta_data jsonb default '{}'::jsonb);
  create or replace function auth.uid() returns uuid language sql stable
    as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table storage.buckets (id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(),
    bucket_id text, name text, owner uuid);
  create or replace function storage.foldername(p text) returns text[]
    language sql immutable as $$ select string_to_array(p, '/') $$;
  create role anon; create role authenticated; create role service_role;
`);
for (const f of fs.readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
  await db.exec(fs.readFileSync(path.join(DIR, f), 'utf8'));
}

let fallos = 0;
let corridos = 0;
function afirmar(nombre, condicion, detalle = '') {
  corridos++;
  if (condicion) console.log(`  OK    ${nombre}`);
  else { fallos++; console.log(`  FALLA ${nombre}${detalle ? `\n        ${detalle}` : ''}`); }
}
const q = async (sql, p) => (await db.query(sql, p)).rows;

// Niveles oficiales del INDEC (base dic-2016 = 100), copiados de
// datos.gob.ar el 19/09/2026. Solo los meses que usa la prueba: la base y
// 2026 hasta agosto, que era lo último publicado ese día.
const REALES = [
  ['2016-12-01', 100.0],
  ['2026-01-01', 10413.0309],
  ['2026-02-01', 10714.6255],
  ['2026-03-01', 11077.0608],
  ['2026-04-01', 11363.0904],
  ['2026-05-01', 11607.3937],
  ['2026-06-01', 11826.4103],
  ['2026-07-01', 12076.3937],
  ['2026-08-01', 12276.766],
];

console.log('Serie del IPC — carga y estimación\n');

// --- Carga con la serie publicada hasta agosto, "hoy" 19 de septiembre ----
const r1 = (await q(`select public.cargar_ipc($1::jsonb, '2026-09-19') as r`, [JSON.stringify(REALES)]))[0].r;
afirmar('toma los meses publicados', r1.meses_publicados === REALES.length, JSON.stringify(r1));
afirmar('lo último publicado es agosto', r1.ultimo_publicado === '2026-08');
afirmar('estima septiembre, que el INDEC todavía no publicó', r1.meses_estimados === 1);

const sep = (await q(`select variacion::float8 as v, es_proyeccion from public.ipc_serie where mes = '2026-09-01'`))[0];
const agoVar = 12276.766 / 12076.3937 - 1;
afirmar('septiembre queda marcado como estimación', sep?.es_proyeccion === true);
afirmar('y usa la variación de agosto', Math.abs(sep.v - agoVar) < 1e-8, `${sep.v} vs ${agoVar}`);

// El índice encadenado tiene que coincidir con el oficial: el motor usa
// cocientes, y si la cadena se corriera, todo el ajuste estaría mal.
const niv = Object.fromEntries((await q(`select to_char(mes,'YYYY-MM') as m, indice::float8 as i from public.ipc_serie`)).map((r) => [r.m, r.i]));
afirmar('el índice de dic-2016 vale 100', Math.abs(niv['2016-12'] - 100) < 1e-6);
afirmar('el índice de ago-2026 coincide con el oficial', Math.abs(niv['2026-08'] - 12276.766) < 1e-3, `${niv['2026-08']}`);
afirmar('hoy (septiembre) está por encima de agosto', niv['2026-09'] > niv['2026-08']);
// La semilla de la migración 0010 tenía base 100 en julio de 2025. Si alguna
// de esas filas sobrevive, mezcla dos bases y rompe todos los cocientes.
afirmar('no queda ningún mes de la semilla vieja', niv['2025-07'] === undefined,
        `quedó 2025-07 con índice ${niv['2025-07']}`);

// --- El INDEC publica septiembre: la estimación se reemplaza --------------
// 12500 es inventado: simula el dato que el INDEC todavía no publicó.
const conSep = [...REALES, ['2026-09-01', 12500.0]];
const r2 = (await q(`select public.cargar_ipc($1::jsonb, '2026-10-20') as r`, [JSON.stringify(conSep)]))[0].r;
const sepReal = (await q(`select variacion::float8 as v, es_proyeccion from public.ipc_serie where mes = '2026-09-01'`))[0];
afirmar('al publicarse septiembre deja de ser estimación', sepReal.es_proyeccion === false);
afirmar('y toma el dato real', Math.abs(sepReal.v - (12500 / 12276.766 - 1)) < 1e-8);
afirmar('octubre pasa a ser la estimación', r2.meses_estimados === 1 && r2.hasta === '2026-10');
const est = (await q(`select count(*)::int as n from public.ipc_serie where es_proyeccion`))[0].n;
afirmar('nunca quedan estimaciones de más', est === 1, `quedaron ${est}`);

// --- Una respuesta rota no borra la serie ---------------------------------
let rechazo = false;
try { await q(`select public.cargar_ipc('[]'::jsonb)`); } catch { rechazo = true; }
afirmar('una respuesta vacía se rechaza sin tocar nada', rechazo);
const quedan = (await q(`select count(*)::int as n from public.ipc_serie`))[0].n;
afirmar('la serie sigue entera después del rechazo', quedan >= conSep.length);

// --- El caso del checklist, en el motor -----------------------------------
// "Hoy" es el día real en que corre el test: el motor usa current_date. Se
// carga la serie con estimaciones hasta hoy para que la prueba no dependa
// de la fecha.
await q(`select public.cargar_ipc($1::jsonb, current_date)`, [JSON.stringify(conSep)]);
await db.exec(`
  alter table public.agencias disable row level security;
  alter table public.vehiculos disable row level security;
  alter table public.gastos disable row level security;
`);
const ag = (await q(`insert into public.agencias (nombre, slug) values ('T','t') returning id`))[0].id;
const veh = (await q(`
  insert into public.vehiculos (agencia_id, codigo, marca, modelo, anio, fecha_compra, fecha_ingreso,
                                precio_compra, precio_objetivo)
  values ($1, 'V001', 'Prueba', 'IPC', 2020, '2026-02-10', '2026-02-10', 10000000, 13000000)
  returning id`, [ag]))[0].id;
// Un gasto de la misma época que la compra y otro reciente.
await q(`insert into public.gastos (agencia_id, vehiculo_id, fecha, categoria, importe)
         values ($1, $2, '2026-02-15', 'service', 500000),
                ($1, $2, '2026-08-20', 'service', 500000)`, [ag, veh]);

const v = (await q(`select costo_total::float8 as nominal, costo_total_hoy::float8 as hoy,
                           ganancia_estimada::float8 as gan, ganancia_real_ipc::float8 as real
                      from public.v_inventario where id = $1`, [veh]))[0];
afirmar('el costo en pesos de hoy es mayor que el nominal', v.hoy > v.nominal, JSON.stringify(v));
afirmar('la ganancia real (IPC) queda por debajo de la nominal', v.real < v.gan, JSON.stringify(v));

// Cada gasto se ajusta desde SU fecha: el de febrero suma más inflación que
// el de agosto aunque sean del mismo importe.
const g = await q(`select fecha::text, (importe * public.ipc_indice_hoy() / public.ipc_indice_en(fecha))::float8 as ajustado
                     from public.gastos where vehiculo_id = $1 order by fecha`, [veh]);
afirmar('el gasto viejo se ajusta más que el reciente', g[0].ajustado > g[1].ajustado, JSON.stringify(g));

console.log(fallos === 0
  ? `\n${corridos} comprobaciones, todas OK.`
  : `\n${fallos} de ${corridos} comprobaciones fallaron.`);
process.exit(fallos === 0 ? 0 : 1);
