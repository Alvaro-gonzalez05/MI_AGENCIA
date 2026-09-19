// Prueba la lectura del historial de 24 meses del BCRA
// (supabase/functions/bcra-consulta/historial.ts) sin levantar nada.
//
// Los casos imitan la FORMA de respuestas reales del BCRA, pero con datos
// inventados: no se guardan datos crediticios de personas reales en el repo.
//
// El primero reproduce el patrón del reclamo del cliente (checklist 3.1):
// irrecuperable, después alto riesgo, y hace más de un año al día. La API
// del período actual contesta 404 para esa persona, y la app decía "sin
// deudas". Es el caso que no puede volver a pasar.
//
//     node --experimental-strip-types historial_bcra.mjs
import { resumirHistorial, mesesEntre } from '../supabase/functions/bcra-consulta/historial.ts';

let fallos = 0;
let corridos = 0;

function igual(nombre, real, esperado) {
  corridos++;
  const ok = JSON.stringify(real) === JSON.stringify(esperado);
  if (ok) {
    console.log(`  OK    ${nombre}`);
  } else {
    fallos++;
    console.log(`  FALLA ${nombre}\n        esperado ${JSON.stringify(esperado)}\n        dio      ${JSON.stringify(real)}`);
  }
}

/** 24 períodos hacia atrás desde `desde` ("AAAAMM"), del más nuevo al más viejo. */
function periodos(desde, cantidad) {
  let a = Number(desde.slice(0, 4));
  let m = Number(desde.slice(4, 6));
  const salida = [];
  for (let i = 0; i < cantidad; i++) {
    salida.push(`${a}${String(m).padStart(2, '0')}`);
    m--;
    if (m === 0) { m = 12; a--; }
  }
  return salida;
}

/** Arma un payload con la forma del BCRA a partir de [periodo, situacion]. */
function payload(meses, denominacion = 'PERSONA DE PRUEBA') {
  return {
    status: 200,
    results: {
      identificacion: 20111111112,
      denominacion,
      periodos: meses.map(([periodo, situacion]) => ({
        periodo,
        entidades: [{ entidad: 'BANCO DE PRUEBA', situacion, monto: 100, enRevision: false, procesoJud: false }],
      })),
    },
  };
}

console.log('Historial de 24 meses del BCRA\n');

// --- El caso del reclamo -------------------------------------------------
{
  const ps = periodos('202607', 24);
  // 16 meses al día, 3 en situación 4, 5 en situación 5 (del más nuevo al más viejo).
  const sits = [...Array(16).fill(0), 4, 4, 4, 5, 5, 5, 5, 5];
  const r = resumirHistorial(payload(ps.map((p, i) => [p, sits[i]])));

  igual('el reclamo: guarda los 24 meses', r.historico.length, 24);
  igual('el reclamo: en 24 meses llegó a situación 5', r.situacionMax24m, 5);
  igual('el reclamo: en los últimos 12 meses no tuvo deuda', r.situacionMax12m, null);
  igual('el reclamo: el último mes irregular fue marzo 2025', r.ultimoPeriodoIrregular, '202503');
  igual('el reclamo: el más nuevo va primero', r.historico[0].periodo, '202607');
}

// --- 404 en el histórico: no tiene nada en 24 meses ----------------------
{
  const r = resumirHistorial(null);
  igual('sin histórico: sin meses', r.historico, []);
  igual('sin histórico: sin peor situación', [r.situacionMax12m, r.situacionMax24m], [null, null]);
}

// --- Siempre al día -------------------------------------------------------
{
  const ps = periodos('202607', 24);
  const r = resumirHistorial(payload(ps.map((p) => [p, 1])));
  igual('siempre en situación 1: peor 12m = 1', r.situacionMax12m, 1);
  igual('siempre en situación 1: peor 24m = 1', r.situacionMax24m, 1);
  igual('siempre en situación 1: nunca irregular', r.ultimoPeriodoIrregular, null);
}

// --- Problema reciente: tiene que caer en la ventana de 12 meses ---------
{
  const ps = periodos('202607', 24);
  const sits = ps.map((_, i) => (i === 11 ? 4 : 1)); // el mes 12 contando el más nuevo
  const r = resumirHistorial(payload(ps.map((p, i) => [p, sits[i]])));
  igual('situación 4 hace 11 meses cae en los últimos 12', r.situacionMax12m, 4);

  const sits2 = ps.map((_, i) => (i === 12 ? 4 : 1)); // el mes 13: ya afuera
  const r2 = resumirHistorial(payload(ps.map((p, i) => [p, sits2[i]])));
  igual('situación 4 hace 12 meses ya queda afuera de los 12', r2.situacionMax12m, 1);
  igual('...pero sigue adentro de los 24', r2.situacionMax24m, 4);
}

// --- El orden de llegada no importa --------------------------------------
{
  const ps = periodos('202607', 6).reverse(); // del más viejo al más nuevo
  const r = resumirHistorial(payload(ps.map((p) => [p, 1])));
  igual('ordena del más nuevo al más viejo aunque lleguen al revés', r.historico[0].periodo, '202607');
}

// --- Varias entidades: manda la peor de cada mes -------------------------
{
  const pay = {
    results: {
      periodos: [{
        periodo: '202607',
        entidades: [
          { entidad: 'A', situacion: 1 },
          { entidad: 'B', situacion: 3 },
          { entidad: 'C', situacion: 0 },
        ],
      }],
    },
  };
  const r = resumirHistorial(pay);
  igual('con varias entidades cuenta la peor del mes', r.historico[0].situacion, 3);
}

// --- La cuenta de meses cruza bien el año --------------------------------
igual('meses entre 202607 y 202508', mesesEntre('202607', '202508'), 11);
igual('meses entre 202601 y 202512', mesesEntre('202601', '202512'), 1);
igual('meses entre 202607 y 202407', mesesEntre('202607', '202407'), 24);

console.log(fallos === 0
  ? `\n${corridos} comprobaciones, todas OK.`
  : `\n${fallos} de ${corridos} comprobaciones fallaron.`);
process.exit(fallos === 0 ? 0 : 1);
