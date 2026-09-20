// =====================================================================
//  importar-vehiculos — lee una lista de autos de donde sea y la devuelve
//  como filas listas para cargar
//
//  La agencia que llega con su stock en un Excel, en un PDF del contador o
//  anotado a mano en una hoja no tiene por qué tipear cincuenta unidades:
//  manda el archivo (o una foto de la hoja) y Gemini devuelve las filas.
//
//  Corre en el servidor y no en la app por una sola razón, que es la
//  importante: **la API key de Gemini no puede viajar dentro de la app**.
//  Un .exe o un .apk se abren con cualquier editor; una clave metida ahí es
//  una clave publicada. Acá vive como secreto del proyecto:
//
//      supabase secrets set GEMINI_API_KEY=...
//
//  Esta función NO escribe en la base. Solo lee los archivos y devuelve
//  filas; el alta la hace la app con la sesión del usuario, y por lo tanto
//  bajo el RLS de su agencia. Si algo sale mal, lo peor que puede pasar es
//  que devuelva filas que el usuario descarta en la pantalla de revisión.
//
//  Desplegar: supabase functions deploy importar-vehiculos
// =====================================================================

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? '';

/// Configurable por si mañana conviene otro: el default es el modelo barato
/// y multimodal, que es exactamente lo que hace falta acá.
const MODELO = Deno.env.get('GEMINI_MODELO') ?? 'gemini-2.5-flash';

const API = 'https://generativelanguage.googleapis.com/v1beta/models';

/// Tope de lo que se acepta en una llamada. La app ya parte los archivos en
/// tandas; esto es la red de seguridad del lado del servidor.
const MAXIMO_BYTES = 18 * 1024 * 1024;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

interface ArchivoEntrante {
  nombre?: string;
  /// 'texto' para planillas y documentos que la app ya convirtió a texto;
  /// 'binario' para fotos y PDF, que Gemini lee directo.
  tipo?: 'texto' | 'binario';
  mime?: string;
  contenido?: string;
}

/// Lo que se le pide al modelo. Es un esquema y no "devolveme un JSON" en
/// palabras: con esquema, la respuesta siempre parsea.
const ESQUEMA = {
  type: 'OBJECT',
  properties: {
    vehiculos: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          marca: { type: 'STRING' },
          modelo: { type: 'STRING' },
          version: { type: 'STRING', nullable: true },
          anio: { type: 'INTEGER', nullable: true },
          km: { type: 'INTEGER', nullable: true },
          patente: { type: 'STRING', nullable: true },
          precio_compra: { type: 'NUMBER', nullable: true },
          precio_objetivo: { type: 'NUMBER', nullable: true },
          fecha_compra: { type: 'STRING', nullable: true },
          fecha_ingreso: { type: 'STRING', nullable: true },
          observaciones: { type: 'STRING', nullable: true },
          confianza: { type: 'NUMBER' },
          origen: { type: 'STRING', nullable: true },
        },
        required: ['marca', 'modelo', 'confianza'],
      },
    },
    nota: { type: 'STRING', nullable: true },
  },
  required: ['vehiculos'],
};

const INSTRUCCIONES = `
Sos el asistente de carga de una agencia de autos usados de Argentina. Te
llegan planillas, documentos o fotos con el stock de la agencia y tenés que
devolver una fila por vehículo.

Reglas, en orden de importancia:

1. NO INVENTES. Si un dato no está, va en null. Es preferible una fila
   incompleta que un dato inventado: cada número de estos define cuánta plata
   gana la agencia. Nunca completes precios, años ni kilómetros "estimando".
2. Una fila por unidad física. Si la misma unidad aparece dos veces, devolvela
   una sola vez.
3. Ignorá los totales, subtotales, encabezados, pies de página y cualquier
   fila que no sea un vehículo.
4. Números en formato argentino: "1.250.000" son 1250000; "12.500,50" son
   12500.5. Sacá "$", "ARS", "USD", puntos de miles y espacios. Si un precio
   está claramente en dólares, dejá el número igual y aclaralo en
   observaciones.
5. Fechas en ISO (AAAA-MM-DD). El formato de origen es día/mes/año: 03/07/2026
   es 2026-07-03. Si solo hay mes y año, usá el día 1. Si hay día y mes pero
   NO año ("ingresó 20/08"), es del año en curso; si eso diera una fecha
   futura, es del año anterior.
5 bis. Si el listado tiene una fecha general arriba ("stock al 15/09",
   "anotado 12/09") y una unidad no trae fecha propia, usá esa como
   fecha_ingreso. Es mucho más cerca de la verdad que la de hoy.
6. Precios: si la planilla distingue compra y venta/publicación, poné
   precio_compra y precio_objetivo. Si hay un solo precio y no se aclara cuál
   es, es el de venta: va en precio_objetivo y precio_compra queda en null.
7. Patente argentina: 3 letras + 3 números (ABC123) o 2 letras + 3 números +
   2 letras (AB123CD). Devolvela en mayúsculas y sin espacios ni guiones. Si
   lo que hay no tiene esa forma, va null.
8. Marca y modelo separados: "Volkswagen Gol Trend 1.6" es marca
   "Volkswagen", modelo "Gol Trend", version "1.6". Marca y modelo con la
   ortografía real de fábrica (Volkswagen, Chevrolet, Peugeot, Renault).
9. km: solo el número, sin "km" ni puntos. "45.000 km" son 45000.
10. confianza: entre 0 y 1, qué tan seguro estás de ESA fila. Calibrala de
    verdad, no pongas 1 en todo: el número se usa para decidir qué revisa un
    humano, y si todo dice 1 no sirve para nada. Guía:
    - 0.95 a 1: texto digital (planilla, PDF exportado), todos los campos
      explícitos y sin ambigüedad.
    - 0.8 a 0.95: texto digital pero tuviste que interpretar algo (separar
      marca de modelo, deducir cuál precio es cuál).
    - 0.6 a 0.8: manuscrito claro, o foto nítida de un impreso.
    - 0.3 a 0.6: manuscrito con abreviaturas, números dudosos, foto con
      reflejos o fuera de foco.
    - menos de 0.3: adivinaste más de lo que leíste.
    Un dato faltante NO baja la confianza: la confianza es sobre lo que SÍ
    leíste.
11. observaciones: solo lo que estaba escrito y no entra en ningún otro campo
    (color, detalles, "a nombre de", "con GNC"). No escribas comentarios tuyos.
12. origen: de dónde sacaste la fila, para que un humano pueda encontrarla
    (nombre del archivo y fila o renglón). Corto.

Si el material no tiene ningún vehículo, devolvé la lista vacía y explicá en
"nota" qué viste.
`.trim();

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  if (!GEMINI_API_KEY) {
    return responder(
      {
        error:
          'Falta la clave de Gemini en el servidor. Cargala con: ' +
          'supabase secrets set GEMINI_API_KEY=...',
      },
      503,
    );
  }

  let cuerpo: { archivos?: ArchivoEntrante[] };
  try {
    cuerpo = await req.json();
  } catch {
    return responder({ error: 'El pedido no es JSON válido.' }, 400);
  }

  const archivos = (cuerpo.archivos ?? []).filter((a) => a?.contenido);
  if (archivos.length === 0) {
    return responder({ error: 'No mandaste ningún archivo.' }, 400);
  }

  const pesoTotal = archivos.reduce(
    (suma, a) => suma + (a.contenido?.length ?? 0),
    0,
  );
  if (pesoTotal > MAXIMO_BYTES) {
    return responder(
      { error: 'Son demasiados archivos juntos. Probá con menos por vez.' },
      413,
    );
  }

  // Sin esto, una fecha sin año ("ingresó 20/08") la completa con el año que
  // se le ocurra: el modelo no sabe en qué día vive.
  const hoy = new Date().toLocaleDateString('sv-SE', {
    timeZone: 'America/Argentina/Buenos_Aires',
  });

  const partes: unknown[] = [{ text: `Hoy es ${hoy}.` }];
  for (const a of archivos) {
    const nombre = (a.nombre ?? 'archivo').slice(0, 120);
    if (a.tipo === 'binario') {
      partes.push({
        inline_data: {
          mime_type: a.mime ?? 'application/octet-stream',
          data: a.contenido,
        },
      });
      partes.push({ text: `(el archivo anterior se llama "${nombre}")` });
    } else {
      partes.push({ text: `--- Archivo "${nombre}" ---\n${a.contenido}` });
    }
  }
  partes.push({
    text: 'Devolvé ahora la lista de vehículos con el esquema pedido.',
  });

  let respuesta: Response;
  try {
    respuesta = await fetch(
      `${API}/${MODELO}:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: INSTRUCCIONES }] },
          contents: [{ role: 'user', parts: partes }],
          generationConfig: {
            temperature: 0,
            responseMimeType: 'application/json',
            responseSchema: ESQUEMA,
          },
        }),
        signal: AbortSignal.timeout(110000),
      },
    );
  } catch (e) {
    const tardo = e instanceof DOMException && e.name === 'TimeoutError';
    return responder(
      {
        error: tardo
          ? 'La lectura tardó demasiado. Probá con menos archivos por vez.'
          : 'No se pudo contactar a Gemini. Reintentá en un momento.',
      },
      504,
    );
  }

  if (!respuesta.ok) {
    const detalle = await respuesta.text();
    console.error('Gemini respondió', respuesta.status, detalle.slice(0, 500));
    // El 429 es el caso que de verdad va a pasar: cuota agotada del día.
    return responder(
      {
        error:
          respuesta.status === 429
            ? 'Se agotó la cuota de Gemini por hoy. Probá más tarde.'
            : `Gemini respondió ${respuesta.status}.`,
      },
      502,
    );
  }

  const datos = await respuesta.json();
  const texto = datos?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof texto !== 'string') {
    // Pasa cuando el modelo corta por filtros de contenido o por tamaño.
    const motivo = datos?.candidates?.[0]?.finishReason ?? 'desconocido';
    return responder(
      { error: `El modelo no devolvió filas (motivo: ${motivo}).` },
      502,
    );
  }

  let leido: { vehiculos?: unknown[]; nota?: string };
  try {
    leido = JSON.parse(texto);
  } catch {
    return responder({ error: 'El modelo devolvió algo que no parsea.' }, 502);
  }

  const uso = datos?.usageMetadata ?? {};
  return responder({
    vehiculos: Array.isArray(leido.vehiculos) ? leido.vehiculos : [],
    desde_foto: archivos.some((a) => a.tipo === 'binario'),
    nota: leido.nota ?? null,
    modelo: MODELO,
    tokens: uso.totalTokenCount ?? null,
  });
});
