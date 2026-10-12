// =====================================================================
//  crear-cuenta-agencia — alta de una agencia con su usuario y clave
//
//  Hasta ahora dar de alta una agencia dejaba una invitación: el dueño
//  tenía que registrarse solo con ese email y recién ahí quedaba vinculado.
//  En la práctica eso no pasa: al cliente se le entrega la app funcionando,
//  con un usuario y una clave anotados en un papel.
//
//  Esto crea las dos cosas de una: la cuenta en auth y la membresía de
//  dueño en la agencia. Corre en el servidor porque crear usuarios exige la
//  service_role, que nunca puede estar en la app.
//
//  Solo la cuenta de desarrollador puede llamarla. Eso se verifica contra
//  `perfiles.es_desarrollador`, que vive en la base y no en el token: si
//  viviera en los metadatos del usuario, cualquiera con la anon key podría
//  intentar escribírselo.
//
//  Desplegar: supabase functions deploy crear-cuenta-agencia
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

/// Una clave que se pueda dictar por teléfono: sin eñes, sin acentos y sin
/// los caracteres que se confunden al leerlos (0/O, 1/l/I).
function claveLegible(largo = 10): string {
  const letras = 'abcdefghjkmnpqrstuvwxyz';
  const numeros = '23456789';
  const todo = letras + letras.toUpperCase() + numeros;
  const azar = crypto.getRandomValues(new Uint32Array(largo));
  let clave = '';
  for (let i = 0; i < largo; i++) clave += todo[azar[i] % todo.length];
  // Que siempre tenga al menos un número: algunos validadores lo piden.
  return clave.slice(0, largo - 1) + numeros[azar[0] % numeros.length];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return responder({ error: 'Iniciá sesión.' }, 401);

  const comoUsuario = createClient(SUPABASE_URL, SERVICE_ROLE, {
    global: { headers: { Authorization: autorizacion } },
  });
  const { data: sesion, error: errorSesion } = await comoUsuario.auth.getUser();
  if (errorSesion || !sesion.user) {
    return responder({ error: 'Iniciá sesión.' }, 401);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  const { data: perfil } = await admin
    .from('perfiles')
    .select('es_desarrollador')
    .eq('id', sesion.user.id)
    .maybeSingle();

  if (!perfil?.es_desarrollador) {
    return responder(
      { error: 'Solo la cuenta de desarrollador puede dar de alta cuentas.' },
      403,
    );
  }

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = await req.json();
  } catch {
    return responder({ error: 'El pedido no trae datos.' }, 400);
  }

  const agenciaId = String(cuerpo.agencia_id ?? '').trim();
  const email = String(cuerpo.email ?? '').trim().toLowerCase();
  const nombre = String(cuerpo.nombre ?? '').trim();
  const rol = String(cuerpo.rol ?? 'owner').trim();
  const clave = String(cuerpo.clave ?? '').trim() || claveLegible();

  if (!agenciaId) return responder({ error: 'Falta la agencia.' }, 400);
  if (!email.includes('@')) return responder({ error: 'Email inválido.' }, 400);
  if (clave.length < 8) {
    return responder({ error: 'La clave necesita 8 caracteres o más.' }, 400);
  }
  if (!['owner', 'admin', 'vendedor', 'solo_lectura'].includes(rol)) {
    return responder({ error: 'Ese rol no existe.' }, 400);
  }

  const { data: agencia } = await admin
    .from('agencias')
    .select('id, nombre')
    .eq('id', agenciaId)
    .maybeSingle();
  if (!agencia) return responder({ error: 'Esa agencia no existe.' }, 404);

  // ¿Ya existe esa cuenta? Si existe, se le da acceso a la agencia en vez
  // de romper: pasa cuando alguien administra dos agencias.
  const { data: existentes } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 200,
  });
  const yaEstaba = existentes?.users.find(
    (u) => (u.email ?? '').toLowerCase() === email,
  );

  let usuarioId: string;
  let claveEntregada: string | null = clave;

  if (yaEstaba) {
    usuarioId = yaEstaba.id;
    // No se le cambia la clave a alguien que ya la tiene: sería sacarle el
    // acceso a la otra agencia sin avisarle.
    claveEntregada = null;
  } else {
    const { data: creado, error: errorAlta } =
      await admin.auth.admin.createUser({
        email,
        password: clave,
        email_confirm: true,
        user_metadata: { nombre: nombre || agencia.nombre },
      });

    if (errorAlta || !creado.user) {
      return responder(
        { error: `No se pudo crear la cuenta: ${errorAlta?.message}` },
        400,
      );
    }
    usuarioId = creado.user.id;
  }

  // El perfil ya existe: lo crea el trigger `on_auth_user_created`. Se
  // completa el nombre, y va el email porque la columna es NOT NULL y
  // Postgres la valida ANTES de resolver el `on conflict`: sin el email,
  // este upsert falla en silencio y el nombre nunca se guarda.
  const { error: errorPerfil } = await admin.from('perfiles').upsert(
    {
      id: usuarioId,
      email,
      nombre: nombre || agencia.nombre,
      es_desarrollador: false,
    },
    { onConflict: 'id' },
  );

  if (errorPerfil) {
    return responder(
      { error: `No se pudo guardar el perfil: ${errorPerfil.message}` },
      500,
    );
  }

  const { error: errorMembresia } = await admin.from('membresias').upsert(
    {
      usuario_id: usuarioId,
      agencia_id: agenciaId,
      rol,
      activa: true,
    },
    { onConflict: 'agencia_id,usuario_id' },
  );

  if (errorMembresia) {
    return responder(
      { error: `La cuenta quedó creada pero sin acceso: ${errorMembresia.message}` },
      500,
    );
  }

  return responder({
    usuario_id: usuarioId,
    email,
    // La clave se devuelve UNA sola vez, para poder entregarla. No queda
    // guardada en ningún lado: si se pierde, se genera otra.
    clave: claveEntregada,
    ya_existia: Boolean(yaEstaba),
    rol,
    agencia: agencia.nombre,
  });
});
