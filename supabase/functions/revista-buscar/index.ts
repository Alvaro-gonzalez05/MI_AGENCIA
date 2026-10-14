// =====================================================================
//  revista-buscar — el precio de revista, en el momento
//
//  La agencia tiene al cliente enfrente y pregunta cuánto vale un auto que
//  no tiene en el inventario. Esperar al cosechador no sirve: el dato se
//  necesita ahora.
//
//  `/search` de la guía devuelve hasta 25 versiones CON su precio en una
//  sola llamada, así que una búsqueda a mano es una consulta y no
//  veinticinco. Lo que entra se guarda, con dos efectos: la próxima vez
//  sale de nuestra copia sin gastar cupo, y la base se va llenando con lo
//  que la gente pregunta de verdad.
//
//  El límite de la guía es de 30 consultas por día y es de la IP: se gasta
//  entre todas las agencias y el cosechador de la noche. Cuando se acaba,
//  esto no falla: devuelve lo que haya guardado y dice que el cupo se
//  terminó, para que la pantalla lo pueda explicar.
//
//  Desplegar: node tests/desplegar_funcion.mjs revista-buscar
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GUIA = 'https://argautos.com/api/v1';

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

/// Lo que se le manda a la guía no es lo que escribió la agencia: "FORD
/// RANGER XLT 3.2 (2016)" no devuelve nada, "ford ranger xlt" sí. Se sacan
/// los números sueltos, los signos y las palabras de menos de tres letras.
function consulta(texto: string): string {
  return texto
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9 ]/g, ' ')
    .split(/\s+/)
    .filter((p) => p.length > 2 && !/^\d+$/.test(p))
    .slice(0, 4)
    .join(' ')
    .trim();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  if (!req.headers.get('Authorization')) {
    return responder({ error: 'Iniciá sesión.' }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = await req.json();
  } catch {
    return responder({ error: 'El pedido no trae datos.' }, 400);
  }

  const q = consulta(String(cuerpo.q ?? ''));
  if (q.length < 3) {
    return responder(
      { error: 'Escribí al menos la marca y el modelo. Ej: Hilux SRV' },
      400,
    );
  }

  // El cupo se cuenta antes de llamar: si la llamada falla igual gastó.
  const { data: usoPrevio } = await admin
    .from('ref_api_uso')
    .select('consultas, limite')
    .eq('fecha', new Date().toISOString().slice(0, 10))
    .maybeSingle();

  const limite = usoPrevio?.limite ?? 28;
  const usadas = usoPrevio?.consultas ?? 0;

  if (usadas >= limite) {
    return responder({
      q,
      agotado: true,
      guardadas: 0,
      quedan: 0,
      mensaje:
        'Se acabaron las consultas del día a la guía. Lo que ya está ' +
        'guardado se sigue viendo; mañana se renueva.',
    });
  }

  await admin
    .from('ref_api_uso')
    .upsert(
      {
        fecha: new Date().toISOString().slice(0, 10),
        consultas: usadas + 1,
        limite,
      },
      { onConflict: 'fecha' },
    );

  let respuesta: Response;
  try {
    respuesta = await fetch(`${GUIA}/search?q=${encodeURIComponent(q)}`, {
      headers: { Accept: 'application/json' },
    });
  } catch (e) {
    return responder(
      { error: `No se pudo hablar con la guía de precios: ${e}` },
      502,
    );
  }

  if (respuesta.status === 429) {
    return responder({
      q,
      agotado: true,
      guardadas: 0,
      quedan: 0,
      mensaje:
        'La guía nos frenó por hoy. Lo que ya está guardado se sigue ' +
        'viendo; mañana se renueva.',
    });
  }

  if (!respuesta.ok) {
    return responder(
      { error: `La guía contestó ${respuesta.status}.` },
      502,
    );
  }

  const datos = await respuesta.json();
  const filas = Array.isArray(datos?.data) ? datos.data : [];

  if (filas.length === 0) {
    return responder({ q, guardadas: 0, quedan: limite - usadas - 1 });
  }

  const { data: guardadas, error } = await admin.rpc(
    'guardar_busqueda_en_vivo',
    { p_resultado: filas },
  );

  if (error) {
    return responder(
      { error: `Llegaron los precios pero no se pudieron guardar: ${error.message}` },
      500,
    );
  }

  return responder({
    q,
    guardadas: guardadas ?? 0,
    quedan: Math.max(limite - usadas - 1, 0),
    restantes_guia: Number(
      respuesta.headers.get('x-dailyquota-remaining') ?? -1,
    ),
  });
});
