// =====================================================================
//  bcra-consulta — situación crediticia de un interesado
//
//  Consulta la Central de Deudores del BCRA (pública y gratuita) y guarda
//  el resultado en `bcra_consultas`. La vista `v_clientes_semaforo` lo
//  traduce después a verde / amarillo / rojo.
//
//  Corre en el servidor y no en la app porque el BCRA no manda cabeceras
//  CORS: un fetch desde el navegador falla sin importar qué se haga.
//
//  Endpoints usados (https://api.bcra.gob.ar/centraldedeudores/v1.0):
//    GET /Deudas/{cuit}                  situación actual por entidad
//    GET /Deudas/Historicas/{cuit}       24 meses hacia atrás
//    GET /Deudas/ChequesRechazados/{cuit}
//
//  Los tres. Hasta la 0.5 se usaban solo el primero y el tercero, y eso
//  hacía que alguien que fue irrecuperable y después pagó saliera "sin
//  deudas": /Deudas solo mira el último mes. Ver historial.ts.
//
//  Desplegar: supabase functions deploy bcra-consulta
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { resumirHistorial } from './historial.ts';

const BCRA = 'https://api.bcra.gob.ar/centraldedeudores/v1.0';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/// El BCRA publica una vez por mes: reconsultar antes no trae nada nuevo y
/// solo golpea su API.
const DIAS_VIGENCIA = 30;

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

interface EntidadBcra {
  entidad?: string;
  situacion?: number;
  monto?: number;
  diasAtrasoPago?: number;
  refinanciaciones?: boolean;
  recategorizacionOblig?: boolean;
  situacionJuridica?: boolean;
  irrecDisposicionTecnica?: boolean;
  enRevision?: boolean;
  procesoJud?: boolean;
}

/// El BCRA devuelve 404 cuando ESA consulta no tiene nada para ese CUIT. No
/// es un error, pero tampoco quiere decir "limpio": un 404 en /Deudas solo
/// dice que no debe nada ESTE mes. Por eso se miran las tres consultas y
/// recién con las tres se puede hablar de "sin deudas".
async function traer(url: string): Promise<unknown | null> {
  const r = await fetch(url, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(20000) });
  if (r.status === 404) return null;
  if (!r.ok) throw new Error(`El BCRA respondió ${r.status}`);
  return await r.json();
}

/// Valida el CUIT/CUIL con su dígito verificador.
///
/// Sin esto, un número tipeado de más se manda al BCRA, vuelve 404 y se
/// guarda como "sin deudas" a alguien que nunca se consultó de verdad.
function cuitValido(cuit: string): boolean {
  if (!/^\d{11}$/.test(cuit)) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const digitos = cuit.split('').map(Number);
  const suma = pesos.reduce((acc, p, i) => acc + p * digitos[i], 0);
  const resto = suma % 11;
  const verificador = resto === 0 ? 0 : resto === 1 ? 9 : 11 - resto;
  return verificador === digitos[10];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return responder({ error: 'Falta la sesión.' }, 401);

  let clienteId: string | null = null;
  let cuit = '';
  let forzar = false;
  try {
    const cuerpo = await req.json();
    clienteId = cuerpo.cliente_id ?? null;
    cuit = String(cuerpo.cuit ?? '').replace(/\D/g, '');
    forzar = cuerpo.forzar === true;
  } catch {
    return responder({ error: 'Mandá { "cuit": "...", "cliente_id": "..." }.' }, 400);
  }

  if (!cuitValido(cuit)) {
    return responder(
      { error: 'Ese CUIT/CUIL no es válido. Revisá los 11 dígitos.' },
      400,
    );
  }

  // Con el JWT del usuario: si el cliente no es de su agencia, el RLS
  // devuelve vacío y la consulta se corta acá.
  const comoUsuario = createClient(SUPABASE_URL, SERVICE_ROLE, {
    global: { headers: { Authorization: autorizacion } },
  });
  const { data: autenticacion, error: errorSesion } = await comoUsuario.auth.getUser();
  if (errorSesion || !autenticacion.user) return responder({ error: 'Iniciá sesión para consultar.' }, 401);
  if (!clienteId) return responder({ error: 'Seleccioná un cliente de la agencia.' }, 400);

  let agenciaId: string | null = null;
  if (clienteId) {
    const { data: cliente } = await comoUsuario
      .from('clientes')
      .select('id, agencia_id, cuit')
      .eq('id', clienteId)
      .is('deleted_at', null)
      .maybeSingle();

    if (!cliente) {
      return responder({ error: 'Ese cliente no existe o no es de tu agencia.' }, 404);
    }
    agenciaId = cliente.agencia_id as string;
    if (cliente.cuit !== cuit) return responder({ error: 'Guardá el CUIT del cliente antes de consultar.' }, 400);
    const { data: puedeEditar } = await comoUsuario.rpc('puede_editar', { p_agencia: agenciaId });
    if (!puedeEditar) return responder({ error: 'No tenés permiso para evaluar clientes.' }, 403);

    // Consulta vigente: se devuelve la guardada en vez de volver al BCRA.
    if (!forzar) {
      const { data: previa } = await comoUsuario
        .from('bcra_consultas')
        .select('*')
        .eq('cliente_id', clienteId)
        .eq('cuit', cuit)
        .is('error', null)
        .gt('expira_at', new Date().toISOString())
        // Una consulta guardada antes de mirar el historial puede decir
        // "sin deudas" de alguien que tuvo: no se reutiliza.
        .not('historico', 'is', null)
        .order('consultado_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (previa) return responder({ ok: true, cacheada: true, consulta: previa });
    }
  }

  // ---- Al BCRA ----
  let deudas: Record<string, unknown> | null;
  let cheques: Record<string, unknown> | null;
  let historicas: Record<string, unknown> | null;
  try {
    // En paralelo: son tres consultas independientes.
    const [d, c, h] = await Promise.all([
      traer(`${BCRA}/Deudas/${cuit}`),
      traer(`${BCRA}/Deudas/ChequesRechazados/${cuit}`),
      traer(`${BCRA}/Deudas/Historicas/${cuit}`),
    ]);
    deudas = d as Record<string, unknown> | null;
    cheques = c as Record<string, unknown> | null;
    historicas = h as Record<string, unknown> | null;
  } catch (e) {
    return responder(
      { error: `No se pudo consultar el BCRA: ${e instanceof Error ? e.message : e}` },
      502,
    );
  }

  // ---- Resumir ----
  const resultados = (deudas?.results ?? {}) as Record<string, unknown>;
  const periodos = (resultados.periodos ?? []) as Array<Record<string, unknown>>;
  // El primero es el más reciente.
  const ultimo = periodos[0];
  const entidades = ((ultimo?.entidades ?? []) as EntidadBcra[]);

  const situacionMaxima = entidades.length
    ? Math.max(...entidades.map((e) => e.situacion ?? 1))
    : null;

  const diasAtrasoMax = entidades.length
    ? Math.max(...entidades.map((e) => e.diasAtrasoPago ?? 0))
    : 0;

  // El BCRA informa los montos en MILES de pesos.
  const totalMiles = entidades.reduce((s, e) => s + (e.monto ?? 0), 0);

  const chequesResultados = (cheques?.results ?? {}) as Record<string, unknown>;
  const causales = (chequesResultados.causales ?? []) as Array<Record<string, unknown>>;

  let sinPagar = 0;
  let totalCheques = 0;
  for (const causal of causales) {
    for (const ent of ((causal.entidades ?? []) as Array<Record<string, unknown>>)) {
      for (const det of ((ent.detalle ?? []) as Array<Record<string, unknown>>)) {
        totalCheques++;
        // fechaPago vacía = el cheque sigue impago, que es lo grave.
        if (!det.fechaPago) sinPagar++;
      }
    }
  }

  const historial = resumirHistorial(historicas);

  const fila = {
    agencia_id: agenciaId,
    cliente_id: clienteId,
    cuit,
    // Si hoy no tiene deuda, /Deudas no trae la razón social; el histórico
    // sí puede traerla.
    denominacion:
      (resultados.denominacion as string) ?? historial.denominacion ?? null,
    periodo: (ultimo?.periodo as string) ?? null,
    situacion_maxima: situacionMaxima,
    total_deuda_miles: totalMiles,
    cantidad_entidades: entidades.length,
    dias_atraso_max: diasAtrasoMax,
    tiene_proceso_judicial: entidades.some((e) => e.procesoJud === true),
    tiene_refinanciaciones: entidades.some((e) => e.refinanciaciones === true),
    tiene_situacion_juridica: entidades.some((e) => e.situacionJuridica === true),
    en_revision: entidades.some((e) => e.enRevision === true),
    tiene_cheques_rechazados: totalCheques > 0,
    cheques_sin_pagar: sinPagar,
    entidades,
    cheques: causales,
    situacion_max_12m: historial.situacionMax12m,
    situacion_max_24m: historial.situacionMax24m,
    ultimo_periodo_irregular: historial.ultimoPeriodoIrregular,
    historico: historial.historico,
    payload_deudas: deudas,
    payload_cheques: cheques,
    payload_historico: historicas,
    consultado_at: new Date().toISOString(),
    expira_at: new Date(Date.now() + DIAS_VIGENCIA * 86400000).toISOString(),
  };

  // Se guarda con service_role: el historial de consultas lo escribe el
  // sistema, no el usuario, y así queda la traza aunque el rol sea de lectura.
  if (clienteId && agenciaId) {
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { error } = await admin.from('bcra_consultas').insert({
      ...fila,
      consultado_por: autenticacion.user.id,
    });
    if (error) {
      return responder(
        { error: `Se consultó el BCRA pero no se pudo guardar: ${error.message}` },
        500,
      );
    }
  }

  return responder({
    ok: true,
    cacheada: false,
    // "Sin deudas" solo si no hay nada hoy Y nada en 24 meses.
    sinDeudasInformadas: entidades.length === 0 && historial.historico.length === 0,
    consulta: fila,
  });
});
