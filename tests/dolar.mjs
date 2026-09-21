// La ganancia real ajustada por dólar oficial (migración 0020), contra
// Postgres de verdad (PGlite).
//
// Reproduce el ejemplo del checklist del cliente (tanda 2, punto 2.1): un
// Corolla comprado el 10/05/2024, con gastos el 20/01/2025, ingresado al
// stock el 15/01/2025 y vendido el 18/09/2026. La ganancia real correcta es
// −$837.078 (−5,8 %); anclada en la fecha de INGRESO daba +$1.344.454.
//
// Las cotizaciones son las oficiales (venta) de argentinadatos.com para esas
// fechas, recortadas a los días que usa la prueba.
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
const cerca = (a, b, tol = 1) => Math.abs(a - b) <= tol;

console.log('Ganancia real por dólar oficial\n');

// --- Carga de cotizaciones -------------------------------------------------
// Formato de argentinadatos. Viernes 10/05/2024 y el lunes siguiente, para
// probar que un fin de semana toma el último día hábil.
const SERIE = [
  { casa: 'oficial', compra: 861.5, venta: 901.5, fecha: '2024-05-10' },
  { casa: 'oficial', compra: 862, venta: 902, fecha: '2024-05-13' },
  { casa: 'oficial', compra: 1021.5, venta: 1061.5, fecha: '2025-01-15' },
  { casa: 'oficial', compra: 1026, venta: 1066, fecha: '2025-01-20' },
  { casa: 'oficial', compra: 1485, venta: 1535, fecha: '2026-09-18' },
];
const r1 = (await q(`select public.cargar_cotizaciones($1::jsonb) as r`, [JSON.stringify(SERIE)]))[0].r;
afirmar('carga las cinco cotizaciones', r1.nuevas_o_cambiadas === 5, JSON.stringify(r1));

const r2 = (await q(`select public.cargar_cotizaciones($1::jsonb) as r`, [JSON.stringify(SERIE)]))[0].r;
afirmar('volver a cargar lo mismo no cambia nada', r2.nuevas_o_cambiadas === 0, JSON.stringify(r2));

const d = async (f) => Number((await q(`select public.dolar_oficial_en($1::date) as d`, [f]))[0].d);
afirmar('el 10/05/2024 vale 901,5', (await d('2024-05-10')) === 901.5);
afirmar('un sábado toma el viernes', (await d('2024-05-11')) === 901.5);
afirmar('hoy toma la última cotización', (await d('2099-01-01')) === 1535);
afirmar('la cotización vigente de la config también se actualiza',
  Number((await q(`select public.cotizacion_vigente('oficial') as d`))[0].d) === 1535);

let rechazo = false;
try { await q(`select public.cargar_cotizaciones('[]'::jsonb)`); } catch { rechazo = true; }
afirmar('una respuesta vacía se rechaza', rechazo);

// --- El Corolla del cliente -----------------------------------------------
await db.exec(`
  alter table public.agencias disable row level security;
  alter table public.vehiculos disable row level security;
  alter table public.gastos disable row level security;
  alter table public.ventas disable row level security;
`);
const ag = (await q(`insert into public.agencias (nombre, slug) values ('T','t') returning id`))[0].id;
const nuevoAuto = async (codigo) => (await q(`
  insert into public.vehiculos (agencia_id, codigo, marca, modelo, anio, fecha_compra, fecha_ingreso,
                                precio_compra, precio_objetivo)
  values ($1, $2, 'Toyota', 'Corolla', 2020, '2024-05-10', '2025-01-15', 8500000, 14500000)
  returning id`, [ag, codigo]))[0].id;

const vendido = await nuevoAuto('V001');
await q(`insert into public.gastos (agencia_id, vehiculo_id, fecha, categoria, importe)
         values ($1, $2, '2025-01-20', 'service', 600000)`, [ag, vendido]);
await q(`insert into public.ventas (agencia_id, vehiculo_id, fecha_venta, precio_final)
         values ($1, $2, '2026-09-18', 14500000)`, [ag, vendido]);

const v = (await q(`
  select costo_total::float8 as nominal, costo_total_hoy::float8 as hoy,
         costo_total_usd::float8 as usd, ganancia_real_ipc::float8 as real,
         margen_real_ipc::float8 as margen, ganancia_real_usd::float8 as real_usd,
         dias_en_stock, dolar_compra::float8 as dc, dolar_referencia::float8 as dr
    from public.v_inventario where id = $1`, [vendido]))[0];

// USD 8.500.000/901,5 + 600.000/1.066 = 9.428,73 + 562,85 = 9.991,58
afirmar('el costo en dólares es USD 9.991,58', cerca(v.usd, 9991.58, 0.01), JSON.stringify(v));
afirmar('toma el dólar de la fecha de COMPRA (901,5), no el de ingreso', v.dc === 901.5);
afirmar('vendido: la referencia es el dólar del día de la venta (1.535)', v.dr === 1535);
afirmar('costo a valor de hoy $15.337.078', cerca(v.hoy, 15337078), `${v.hoy}`);
afirmar('ganancia real −$837.078', cerca(v.real, -837078), `${v.real}`);
afirmar('margen real −5,8 %', cerca(v.margen * 100, -5.77, 0.01), `${v.margen}`);
afirmar('ganancia real en dólares ≈ USD −545', cerca(v.real_usd, -837078 / 1535, 0.01), `${v.real_usd}`);
afirmar('los días en stock siguen contando desde el INGRESO',
  v.dias_en_stock === 611, `${v.dias_en_stock}`);  // 15/01/2025 → 18/09/2026
afirmar('la nominal no cambia: $9.100.000', v.nominal === 9100000);

// El dashboard suma la ganancia en dólares de cada venta al dólar de SU día.
const dash = (await q(`select ganancia_realizada_ipc::float8 as real, ganancia_realizada_usd::float8 as usd
                         from public.v_dashboard where agencia_id = $1`, [ag]))[0];
afirmar('el dashboard muestra la misma ganancia real', cerca(dash.real, -837078), JSON.stringify(dash));
afirmar('y la misma en dólares', cerca(dash.usd, -837078 / 1535, 0.01));

// --- Gastos de cierre ------------------------------------------------------
// Se pagan el día de la venta: a dólar de ese día entran nominales.
await q(`update public.ventas set gastos_finales = 100000 where vehiculo_id = $1`, [vendido]);
const conCierre = (await q(`select ganancia_real_ipc::float8 as real from public.v_inventario where id = $1`, [vendido]))[0];
afirmar('los gastos de cierre restan nominales', cerca(conCierre.real, -937078), `${conCierre.real}`);

// --- En stock: la referencia es el dólar de hoy -----------------------------
const enStock = await nuevoAuto('V002');
const s = (await q(`select dolar_referencia::float8 as dr, costo_total_hoy::float8 as hoy,
                           precio_referencia::float8 as precio
                      from public.v_inventario where id = $1`, [enStock]))[0];
afirmar('en stock usa la última cotización', s.dr === 1535);
afirmar('y el precio publicado como referencia', s.precio === 14500000);
afirmar('costo de la compra a hoy = 8.500.000 × 1.535 / 901,5',
  cerca(s.hoy, 8500000 * 1535 / 901.5), `${s.hoy}`);

// --- Sin cotizaciones, nada se inventa --------------------------------------
await q(`delete from public.cotizaciones`);
const sin = (await q(`select costo_total::float8 as nominal, costo_total_hoy::float8 as hoy,
                             ganancia_real_ipc::float8 as real
                        from public.v_inventario where id = $1`, [enStock]))[0];
afirmar('sin cotizaciones el costo de hoy es el nominal', sin.hoy === sin.nominal, JSON.stringify(sin));

console.log(fallos === 0
  ? `\n${corridos} comprobaciones, todas OK.`
  : `\n${fallos} de ${corridos} comprobaciones fallaron.`);
process.exit(fallos === 0 ? 0 : 1);
