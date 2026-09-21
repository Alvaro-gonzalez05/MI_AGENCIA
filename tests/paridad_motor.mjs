// Carga los datos reales del cliente en Postgres, corre v_inventario y lo
// compara campo por campo contra computeInventory() del HTML original.
import { PGlite } from '@electric-sql/pglite';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { unaccent } from '@electric-sql/pglite/contrib/unaccent';
import { computeInventory, DATA_SEED } from './motor_original.mjs';
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

for (const f of fs.readdirSync(DIR).filter(f => f.endsWith('.sql')).sort()) {
  await db.exec(fs.readFileSync(path.join(DIR, f), 'utf8'));
}

// El RLS se apaga solo para este banco de pruebas: aca no hay sesion de
// usuario y lo que se esta verificando son las formulas, no los permisos.
await db.exec(`
  do $$ declare t record; begin
    for t in select tablename from pg_tables where schemaname='public' loop
      execute format('alter table public.%I disable row level security', t.tablename);
    end loop;
  end $$;
`);

const AG = '11111111-1111-1111-1111-111111111111';
await db.exec(`insert into public.agencias (id, nombre, slug) values ('${AG}', 'Agencia Demo', 'demo')`);

// Config exacta del HTML original.
const cfg = DATA_SEED.config;
await db.query(
  `update public.agencia_config set dias_verde=$1, dias_amarillo=$2, dias_rojo=$3,
     margen_minimo=$4, margen_objetivo=$5, tolerancia_caida_margen=$6,
     tolerancia_desvio_precio=$7, umbral_gastos_altos=$8, redondeo=$9,
     capacidad=$10, tasa_financiacion_mensual=$11 where agencia_id=$12`,
  [cfg.diasVerde, cfg.diasAmarillo, cfg.diasRojo, cfg.margenMinimo, cfg.margenObjetivo,
   cfg.toleranciaCaidaMargen, cfg.toleranciaDesvioPrecio, cfg.umbralGastosAltos,
   cfg.redondeo, cfg.capacidad, cfg.tasaFinanciacionMensual, AG]);

const ESTADO = { 'En stock': 'en_stock', 'En preparación': 'en_preparacion', 'Reservado': 'reservado' };
const CATEG = {
  'Service': 'service', 'Reparaciones': 'reparaciones', 'Cubiertas': 'cubiertas',
  'Chapa y pintura': 'chapa_y_pintura', 'Lavado/Detallado': 'lavado_detallado',
  'Transferencia': 'transferencia', 'Patentamiento': 'patentamiento',
  'Gestoría': 'gestoria', 'Almacenamiento': 'almacenamiento', 'Otros': 'otros',
};

const idDe = {};
for (const v of DATA_SEED.vehiculos) {
  const r = await db.query(
    `insert into public.vehiculos (agencia_id, codigo, marca, modelo, anio, version, km,
       fecha_compra, fecha_ingreso, precio_compra, precio_objetivo, estado, observaciones)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) returning id`,
    [AG, v.id, v.marca, v.modelo, v.anio, v.version, v.km, v.fechaCompra, v.fechaIngreso,
     v.precioCompra, v.precioObjetivo, ESTADO[v.estado], v.obs]);
  idDe[v.id] = r.rows[0].id;
}
for (const g of DATA_SEED.gastos) {
  await db.query(
    `insert into public.gastos (agencia_id, vehiculo_id, fecha, categoria, descripcion, importe)
     values ($1,$2,$3,$4,$5,$6)`,
    [AG, idDe[g.idVehiculo], g.fecha, CATEG[g.categoria], g.desc, g.importe]);
}
for (const p of DATA_SEED.precios) {
  await db.query(
    `insert into public.cambios_precio (agencia_id, vehiculo_id, fecha, precio_nuevo, motivo)
     values ($1,$2,$3,$4,$5)`,
    [AG, idDe[p.idVehiculo], p.fecha, p.nuevoPrecio, p.motivo]);
}
for (const s of DATA_SEED.ventas) {
  await db.query(
    `insert into public.ventas (agencia_id, vehiculo_id, fecha_venta, precio_final,
       gastos_finales, observaciones) values ($1,$2,$3,$4,$5,$6)`,
    [AG, idDe[s.idVehiculo], s.fechaVenta, s.precioFinal, s.gastosFinales, s.obs]);
}

const sql = await db.query(`select * from public.v_inventario order by codigo`);
const js = computeInventory();
const porCodigo = Object.fromEntries(sql.rows.map(r => [r.codigo, r]));

// Campos que deben coincidir: nombre JS -> nombre SQL.
// `diasEnStock` y `costoDiario` NO entran aca: divergen a proposito y se
// verifican aparte, mas abajo. Compararlos a ciegas hacia que el test
// pasara a la manana y fallara a la tarde.
const CAMPOS = [
  ['costoTotal', 'costo_total'],
  ['gastosAcum', 'gastos_acum'],
  ['precioActual', 'precio_actual'],
  ['capitalInmovilizado', 'capital_inmovilizado'],
  ['gananciaEstimada', 'ganancia_estimada'],
  ['margenEsperado', 'margen_esperado'],
  ['margenActual', 'margen_actual'],
  ['margenReal', 'margen_real'],
  ['precioParaMargenObjetivo', 'precio_para_margen_objetivo'],
  ['precioParaMargenMinimo', 'precio_para_margen_minimo'],
  ['ajusteNecesario', 'ajuste_necesario'],
  ['varVsObjetivo', 'var_vs_objetivo'],
  ['gastosRatio', 'gastos_ratio'],
  // costoTotalHoy, gananciaRealIPC, margenRealIPC y gananciaRealIPCUSD ya
  // NO se comparan: el cliente cambio la regla (checklist tanda 2, punto
  // 2.1). El original ajustaba por IPC desde la fecha de ingreso; ahora se
  // ajusta por dolar oficial desde la fecha de compra (migracion 0020). Esa
  // regla nueva la verifica tests/dolar.mjs con el ejemplo del cliente.
  ['alerta', 'alerta'],
  ['cantidadGastos', 'cantidad_gastos'],
];

// Tolerancia relativa: numeric de Postgres y double de JS no dan bit a bit iguales.
const TOL = 1e-6;
let diffs = 0, comparados = 0;

// La regla de alerta del original (ver motor_original.mjs), para poder
// preguntarle a cada lado si su alerta es coherente con los dias que conto.
const alertaDe = (dias, estado) =>
  estado === 'Vendido' ? 'vendido'
  : dias >= cfg.diasRojo ? 'critico'
  : dias >= cfg.diasAmarillo ? 'atencion'
  : dias >= cfg.diasVerde ? 'observar'
  : 'normal';

// Unidades paradas justo sobre un umbral. No son errores, pero se listan al
// final: es la explicacion de por que el tablero puede cambiar de color en el
// medio del dia sin que nadie haya tocado nada.
const alertasPorElDia = [];

for (const v of js) {
  const r = porCodigo[v.id];
  if (!r) { console.log(`  FALTA en SQL: ${v.id}`); diffs++; continue; }
  for (const [kJs, kSql] of CAMPOS) {
    const a = v[kJs], b = r[kSql];
    comparados++;
    if (kJs === 'alerta') {
      // La alerta sale de los dias en stock, asi que hereda la divergencia de
      // medio dia del original: una unidad parada justo sobre un umbral cae de
      // un lado a la manana y del otro a la tarde. Por eso no se comparan las
      // alertas a ciegas, se comprueba que CADA lado aplique bien la regla a
      // SU conteo de dias. Si los dos son coherentes con lo que contaron, la
      // alerta no tiene ningun error propio. Si alguno no lo es, eso si es un
      // bug, y el test lo dice.
      if (a !== b) {
        const jsCoherente = alertaDe(v.diasEnStock, v.estado) === a;
        const sqlCoherente = alertaDe(Number(r.dias_en_stock), v.estado) === b;
        if (jsCoherente && sqlCoherente) {
          alertasPorElDia.push(
            `${v.id}: js "${a}" con ${v.diasEnStock} dias, sql "${b}" con ${r.dias_en_stock}`,
          );
        } else {
          console.log(`  ${v.id}.${kJs}: js="${a}" sql="${b}"`
            + `  (la regla no cierra: js=${jsCoherente} sql=${sqlCoherente})`);
          diffs++;
        }
      }
      continue;
    }
    const na = (a === null || a === undefined) ? null : Number(a);
    const nb = (b === null || b === undefined) ? null : Number(b);
    if (na === null && nb === null) continue;
    if (na === null || nb === null) {
      console.log(`  ${v.id}.${kJs}: js=${na} sql=${nb}`); diffs++; continue;
    }
    const rel = Math.abs(na - nb) / Math.max(1, Math.abs(na));
    if (rel > TOL) {
      console.log(`  ${v.id}.${kJs}: js=${na} sql=${nb}  (dif ${(rel * 100).toFixed(4)}%)`);
      diffs++;
    }
  }
}


// ---------------------------------------------------------------------
// Diferencia intencional documentada (ver docs/MOTOR_DE_CALCULO.md):
//
// El original hacia Math.round((hoy - ingreso) / 86400000) con `hoy`
// incluyendo la hora, asi que despues del mediodia redondeaba para arriba: una
// unidad mostraba 105 dias a la manana y 106 a la tarde. El SQL resta fechas
// calendario y es estable todo el dia.
//
// Aca no se compara, se AFIRMA que la divergencia es exactamente esa y ninguna
// otra. Es la unica forma de que el test no sea una moneda al aire.
// ---------------------------------------------------------------------
const DIA_MS = 86400000;
let erroresDias = 0;

for (const v of js) {
  const r = porCodigo[v.id];
  if (!r) continue;

  // PGlite usa UTC; no comparar su CURRENT_DATE con medianoche del host.
  // En Argentina esa mezcla fallaba entre las 21:00 y las 00:00.
  const ingreso = new Date(v.fechaIngreso + 'T00:00:00Z');
  const fin = v.venta ? new Date(v.venta.fechaVenta + 'T00:00:00Z') : new Date();
  const diasCalendario = Math.floor((fin - ingreso) / DIA_MS);

  if (Number(r.dias_en_stock) !== diasCalendario) {
    console.log(`  ${v.id}.dias_en_stock: sql=${r.dias_en_stock}, el calendario dice ${diasCalendario}`);
    erroresDias++;
  }

  const brecha = v.diasEnStock - diasCalendario;
  if (brecha !== 0 && brecha !== 1) {
    console.log(`  ${v.id}.diasEnStock: el original difiere en ${brecha} dias (solo se admite 0 o 1)`);
    erroresDias++;
  }

  const esperado = diasCalendario > 0
    ? Number(r.costo_total) / diasCalendario
    : Number(r.costo_total);
  if (Math.abs(Number(r.costo_diario) - esperado) / Math.max(1, esperado) > TOL) {
    console.log(`  ${v.id}.costo_diario: sql=${r.costo_diario}, esperado ${esperado}`);
    erroresDias++;
  }
}

diffs += erroresDias;

if (alertasPorElDia.length) {
  console.log(`\nAlertas que dependen del medio dia de diferencia:`);
  for (const linea of alertasPorElDia) console.log(`  ${linea}`);
  console.log('  (las dos aplican bien la regla: cambia el conteo de dias, no el criterio)');
}

console.log(erroresDias === 0
  ? '\nDias en stock: la unica diferencia con el original es el redondeo de medio dia, como se documento.'
  : `\n${erroresDias} problema(s) en el calculo de dias en stock.`);

console.log(`\n${comparados} valores comparados en ${js.length} vehiculos.`);
console.log(diffs === 0
  ? 'Coincidencia total: el motor SQL replica al original.'
  : `${diffs} diferencia(s).`);

const dash = await db.query(`select * from public.v_dashboard`);
console.log('\nDashboard:', JSON.stringify(dash.rows[0], null, 1));

const diag = await db.query(
  `select public.diagnostico_vehiculo(id) as d from public.v_inventario where codigo='V008'`);
console.log('\nDiagnostico V008:', diag.rows[0].d);
console.log('Original   V008:', js.find(x => x.id === 'V008').diagnostico);

process.exit(diffs === 0 ? 0 : 1);
