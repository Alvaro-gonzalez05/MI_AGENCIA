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
//  Desplegar:  supabase functions deploy enviar-campana
//  Secretos:   supabase secrets set RESEND_API_KEY=re_xxx
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/// Resend acepta hasta 100 destinatarios por llamada al endpoint batch.
const TAMANO_LOTE = 100;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
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

  if (!RESEND_API_KEY) {
    return responder(
      { error: 'Falta el secreto RESEND_API_KEY en el proyecto.' },
      500,
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
    .select('id, agencia_id, nombre, asunto, cuerpo_html, estado, filtro, remitente_nombre, remitente_email')
    .eq('id', campanaId)
    .single();

  if (errorCampana || !campana) {
    return responder({ error: 'No se encontró la campaña.' }, 404);
  }

  if (campana.estado === 'enviada' || campana.estado === 'enviando') {
    // Sin esto, dos toques seguidos al botón mandan la campaña dos veces.
    return responder({ error: 'Esa campaña ya se envió.' }, 409);
  }

  // 2. Los destinatarios: clientes con email que NO pidieron la baja.
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

  const remitente = campana.remitente_email
    ? `${campana.remitente_nombre ?? 'Mi Agencia'} <${campana.remitente_email}>`
    : 'Mi Agencia <onboarding@resend.dev>';

  let enviados = 0;
  const fallidos: { email: string; motivo: string }[] = [];

  for (let i = 0; i < clientes.length; i += TAMANO_LOTE) {
    const lote = clientes.slice(i, i + TAMANO_LOTE);

    const mails = lote.map((c) => {
      const nombre = [c.nombre, c.apellido].filter(Boolean).join(' ');
      return {
        from: remitente,
        to: [c.email as string],
        subject: completar(campana.asunto, { nombre: escapar(nombre) }),
        html: completar(campana.cuerpo_html, {
          nombre: escapar(nombre),
          agencia: escapar(campana.nombre ?? ''),
        }),
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
