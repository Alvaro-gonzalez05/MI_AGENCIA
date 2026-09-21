// =====================================================================
//  enviar-campana — envío de una campaña de email por Resend
//
//  Corre en el servidor y no en la app por tres razones, en orden de
//  importancia:
//
//  1. La API key de Resend no puede viajar dentro de la app. Un APK se
//     descompila en dos minutos y esa clave permite mandar mails a nombre
//     del dominio de la agencia.
//  2. Resend no manda cabeceras CORS: un fetch desde el navegador falla.
//  3. Enviar 300 mails desde un celular con la pantalla encendida no es
//     un plan.
//
//  Configuración (una sola vez, ver docs/EMAIL_MARKETING.md):
//    RESEND_API_KEY   la clave de Resend (re_...)
//    RESEND_FROM      el remitente, con un dominio verificado en Resend:
//                     "Automotores del Oeste <novedades@automotoresoeste.com>"
//
//  Desplegar:  supabase functions deploy enviar-campana
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const RESEND_FROM = Deno.env.get('RESEND_FROM');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/// Resend acepta hasta 100 destinatarios por llamada al endpoint batch.
const TAMANO_LOTE = 100;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/// Reemplaza {{nombre}}, {{agencia}} y similares en el cuerpo del mail.
function completar(plantilla: string, datos: Record<string, string>): string {
  return plantilla.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, clave) =>
    datos[clave] ?? ''
  );
}

/// Escapa lo que se interpola en el HTML del mail.
///
/// El nombre de un cliente lo escribe un vendedor, y un apellido con `<`
/// rompería el mail de todos los destinatarios de ese lote.
function escapar(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  // Sin configurar no se toca nada: ni la campaña ni los contadores. El
  // mensaje es para quien usa la app, no para un programador.
  if (!RESEND_API_KEY || !RESEND_FROM) {
    return responder(
      {
        error:
          'El envío de mails todavía no está configurado. Hace falta conectar ' +
          'la cuenta de envío (Resend) y el dominio de la agencia. La campaña ' +
          'quedó guardada como borrador y se puede mandar cuando esté listo.',
        falta_configurar: true,
      },
      503,
    );
  }

  // El JWT del usuario se reenvía tal cual: así el select de la campaña
  // pasa por RLS y nadie puede mandar la campaña de otra agencia.
  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return responder({ error: 'Falta la sesión.' }, 401);

  const comoUsuario = createClient(SUPABASE_URL, SERVICE_ROLE, {
    global: { headers: { Authorization: autorizacion } },
  });

  let campanaId: string;
  try {
    const cuerpo = await req.json();
    campanaId = cuerpo.campana_id;
    if (!campanaId) throw new Error('falta campana_id');
  } catch {
    return responder({ error: 'Mandá { "campana_id": "..." }.' }, 400);
  }

  // 1. La campaña, leída con los permisos del usuario.
  const { data: campana, error: errorCampana } = await comoUsuario
    .from('campanas')
    .select('id, agencia_id, nombre, asunto, cuerpo_html, estado, filtro, remitente_nombre')
    .eq('id', campanaId)
    .single();

  if (errorCampana || !campana) {
    return responder({ error: 'No se encontró la campaña.' }, 404);
  }

  if (campana.estado === 'enviada' || campana.estado === 'enviando') {
    // Sin esto, dos toques seguidos al botón mandan la campaña dos veces.
    return responder({ error: 'Esa campaña ya se envió.' }, 409);
  }

  // La agencia: su nombre es {{agencia}} en el mail, y su email de contacto
  // es a donde llegan las respuestas. Antes {{agencia}} ponía el nombre de
  // la CAMPAÑA ("Pickups septiembre") en lugar del de la agencia.
  const { data: agencia } = await comoUsuario
    .from('agencias')
    .select('nombre, email_contacto')
    .eq('id', campana.agencia_id)
    .single();

  // 2. Los destinatarios: clientes con email que aceptaron recibir mails.
  //    El filtro de baja no es configurable a propósito.
  let consulta = comoUsuario
    .from('clientes')
    .select('id, nombre, apellido, email')
    .eq('agencia_id', campana.agencia_id)
    .eq('acepta_marketing', true)
    .not('email', 'is', null)
    .is('deleted_at', null);

  const filtro = (campana.filtro ?? {}) as Record<string, unknown>;
  if (Array.isArray(filtro.origen) && filtro.origen.length > 0) {
    consulta = consulta.in('origen', filtro.origen as string[]);
  }

  const { data: clientes, error: errorClientes } = await consulta.limit(2000);
  if (errorClientes) {
    return responder({ error: 'No se pudieron leer los destinatarios.' }, 500);
  }
  if (!clientes || clientes.length === 0) {
    return responder({ error: 'No hay destinatarios que cumplan el filtro.' }, 400);
  }

  // A partir de acá se usa service_role: los contadores y los estados de
  // envío los escribe el sistema, no el usuario.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  await admin
    .from('campanas')
    .update({ estado: 'enviando', total_destinatarios: clientes.length })
    .eq('id', campana.id);

  // El remitente sale de la configuración: tiene que ser de un dominio
  // verificado en Resend, o Resend lo rechaza. Si la agencia puso un nombre
  // propio en la campaña, se usa ese nombre con la dirección configurada.
  const direccion = RESEND_FROM.match(/<([^>]+)>/)?.[1] ?? RESEND_FROM;
  const nombreRemitente = campana.remitente_nombre ?? agencia?.nombre;
  const remitente = nombreRemitente ? `${nombreRemitente} <${direccion}>` : RESEND_FROM;

  const nombreAgencia = escapar(agencia?.nombre ?? '');
  let enviados = 0;
  const fallidos: { email: string; motivo: string }[] = [];

  for (let i = 0; i < clientes.length; i += TAMANO_LOTE) {
    const lote = clientes.slice(i, i + TAMANO_LOTE);

    const mails = lote.map((c) => {
      const nombre = escapar([c.nombre, c.apellido].filter(Boolean).join(' '));
      return {
        from: remitente,
        to: [c.email as string],
        // Las respuestas —incluido el "BAJA" que promete el pie del mail—
        // le llegan a la agencia y no se pierden en una casilla sin dueño.
        ...(agencia?.email_contacto ? { reply_to: agencia.email_contacto } : {}),
        subject: completar(campana.asunto, { nombre, agencia: nombreAgencia }),
        html: completar(campana.cuerpo_html, { nombre, agencia: nombreAgencia }),
      };
    });

    try {
      const r = await fetch('https://api.resend.com/emails/batch', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(mails),
      });

      const respuesta = await r.json();

      if (!r.ok) {
        // Un lote que falla no frena el resto: se anota y se sigue.
        for (const c of lote) {
          fallidos.push({
            email: c.email as string,
            motivo: respuesta?.message ?? `HTTP ${r.status}`,
          });
        }
        continue;
      }

      const ids: string[] = (respuesta?.data ?? []).map(
        (x: { id: string }) => x.id,
      );

      await admin.from('campana_destinatarios').upsert(
        lote.map((c, j) => ({
          campana_id: campana.id,
          cliente_id: c.id,
          email: c.email,
          estado: 'enviado',
          proveedor_id: ids[j] ?? null,
          enviado_at: new Date().toISOString(),
        })),
        { onConflict: 'campana_id,cliente_id' },
      );

      enviados += lote.length;
    } catch (e) {
      for (const c of lote) {
        fallidos.push({ email: c.email as string, motivo: String(e) });
      }
    }
  }

  if (fallidos.length > 0) {
    await admin.from('campana_destinatarios').upsert(
      fallidos.map((f) => ({
        campana_id: campana.id,
        cliente_id: clientes.find((c) => c.email === f.email)?.id,
        email: f.email,
        estado: 'error',
        error: f.motivo.slice(0, 500),
      })),
      { onConflict: 'campana_id,cliente_id' },
    );
  }

  // Si no salió NINGUNO, la campaña vuelve a borrador. Antes quedaba como
  // "enviada" con cero mails y no había forma de reintentarla: justo lo que
  // pasa la primera vez, mientras se termina de configurar el dominio.
  if (enviados === 0) {
    await admin.from('campanas').update({ estado: 'borrador' }).eq('id', campana.id);
    return responder(
      {
        error:
          'No salió ningún mail. Resend respondió: ' +
          (fallidos[0]?.motivo ?? 'sin detalle') +
          '. La campaña volvió a borrador para poder reintentarla.',
        destinatarios: clientes.length,
        enviados: 0,
        fallidos: fallidos.length,
      },
      502,
    );
  }

  await admin
    .from('campanas')
    .update({
      estado: 'enviada',
      enviada_at: new Date().toISOString(),
      total_enviados: enviados,
    })
    .eq('id', campana.id);

  return responder({
    ok: true,
    destinatarios: clientes.length,
    enviados,
    fallidos: fallidos.length,
  });
});
