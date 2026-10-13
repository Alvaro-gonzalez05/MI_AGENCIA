// =====================================================================
//  crear-cuenta-agencia — altas de cuentas y claves nuevas
//
//  Dos cosas que exigen la service_role y por lo tanto no pueden vivir en
//  la app: crear un usuario y cambiarle la clave a alguien.
//
//  Quién puede llamarla:
//    · nosotros (perfiles.es_desarrollador) — damos de alta las agencias y
//      la cuenta de su dueño;
//    · el dueño de una agencia — da de alta a su gente;
//    · un administrador — da de alta vendedores y cuentas de solo lectura.
//
//  Nadie puede crear a alguien por encima suyo: un administrador no nombra
//  dueños, y nadie le cambia la clave a quien está más arriba. Eso se
//  verifica contra la base y no contra el token, porque el token lo escribe
//  el cliente y la base no.
//
//  Desplegar: node tests/desplegar_funcion.mjs crear-cuenta-agencia
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

const ROLES = ['owner', 'admin', 'vendedor', 'solo_lectura'] as const;
type Rol = (typeof ROLES)[number];

/// Qué roles puede repartir cada uno. La regla de siempre: nadie crea a
/// alguien con más poder que él.
const PUEDE_CREAR: Record<string, Rol[]> = {
  desarrollador: ['owner', 'admin', 'vendedor', 'solo_lectura'],
  owner: ['admin', 'vendedor', 'solo_lectura'],
  admin: ['vendedor', 'solo_lectura'],
};

/// Para las claves: el orden de arriba hacia abajo. A alguien de tu mismo
/// nivel o más arriba no le tocás la clave.
const NIVEL: Record<string, number> = {
  desarrollador: 4,
  owner: 3,
  admin: 2,
  vendedor: 1,
  solo_lectura: 1,
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return responder({ error: 'Usá POST.' }, 405);

  const autorizacion = req.headers.get('Authorization');
  if (!autorizacion) return responder({ error: 'Iniciá sesión.' }, 401);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  const comoUsuario = createClient(SUPABASE_URL, SERVICE_ROLE, {
    global: { headers: { Authorization: autorizacion } },
  });
  const { data: sesion, error: errorSesion } = await comoUsuario.auth.getUser();
  if (errorSesion || !sesion.user) {
    return responder({ error: 'Iniciá sesión.' }, 401);
  }
  const quienLlama = sesion.user.id;

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = await req.json();
  } catch {
    return responder({ error: 'El pedido no trae datos.' }, 400);
  }

  const accion = String(cuerpo.accion ?? 'crear');
  const agenciaId = String(cuerpo.agencia_id ?? '').trim();
  if (!agenciaId) return responder({ error: 'Falta la agencia.' }, 400);

  const { data: agencia } = await admin
    .from('agencias')
    .select('id, nombre')
    .eq('id', agenciaId)
    .maybeSingle();
  if (!agencia) return responder({ error: 'Esa agencia no existe.' }, 404);

  // ------------------------------------------------------------------
  //  Quién es el que llama, según la base
  // ------------------------------------------------------------------
  const { data: perfil } = await admin
    .from('perfiles')
    .select('es_desarrollador')
    .eq('id', quienLlama)
    .maybeSingle();

  let quienEs = 'nadie';
  if (perfil?.es_desarrollador) {
    quienEs = 'desarrollador';
  } else {
    const { data: membresia } = await admin
      .from('membresias')
      .select('rol')
      .eq('usuario_id', quienLlama)
      .eq('agencia_id', agenciaId)
      .eq('activa', true)
      .maybeSingle();
    if (membresia) quienEs = membresia.rol as string;
  }

  if (!PUEDE_CREAR[quienEs]) {
    return responder(
      { error: 'No tenés permiso para administrar las cuentas de esta agencia.' },
      403,
    );
  }

  // ------------------------------------------------------------------
  //  Clave nueva para alguien que ya está
  // ------------------------------------------------------------------
  if (accion === 'nueva_clave') {
    const usuarioId = String(cuerpo.usuario_id ?? '').trim();
    if (!usuarioId) return responder({ error: 'Falta la persona.' }, 400);

    const { data: destino } = await admin
      .from('membresias')
      .select('rol')
      .eq('usuario_id', usuarioId)
      .eq('agencia_id', agenciaId)
      .maybeSingle();

    if (!destino) {
      return responder({ error: 'Esa persona no es de esta agencia.' }, 404);
    }

    // En dos consultas y no con un join: `membresias.usuario_id` apunta a
    // `auth.users`, no a `perfiles`, así que PostgREST no sabe unirlas.
    const { data: suPerfil } = await admin
      .from('perfiles')
      .select('email, es_desarrollador')
      .eq('id', usuarioId)
      .maybeSingle();

    if (!suPerfil) {
      return responder({ error: 'Esa persona no tiene perfil.' }, 404);
    }

    // A nosotros no nos cambia la clave el cliente, aunque seamos miembros
    // de su agencia para poder ayudarlo.
    if (suPerfil.es_desarrollador && quienEs !== 'desarrollador') {
      return responder({ error: 'Esa cuenta no se administra desde acá.' }, 403);
    }

    if (NIVEL[quienEs] <= NIVEL[destino.rol as string] &&
        quienEs !== 'desarrollador') {
      return responder(
        { error: 'No podés cambiarle la clave a alguien de tu mismo nivel.' },
        403,
      );
    }

    const clave = claveLegible();
    const { error } = await admin.auth.admin.updateUserById(usuarioId, {
      password: clave,
    });
    if (error) {
      return responder({ error: `No se pudo cambiar la clave: ${error.message}` }, 400);
    }

    return responder({
      usuario_id: usuarioId,
      email: suPerfil.email,
      clave,
      rol: destino.rol,
      agencia: agencia.nombre,
      ya_existia: true,
    });
  }

  // ------------------------------------------------------------------
  //  Alta de una cuenta
  // ------------------------------------------------------------------
  const email = String(cuerpo.email ?? '').trim().toLowerCase();
  const nombre = String(cuerpo.nombre ?? '').trim();
  const rol = String(cuerpo.rol ?? 'vendedor').trim();
  const zonaId = String(cuerpo.zona_id ?? '').trim() || null;
  const clave = String(cuerpo.clave ?? '').trim() || claveLegible();

  if (!email.includes('@')) return responder({ error: 'Email inválido.' }, 400);
  if (clave.length < 8) {
    return responder({ error: 'La clave necesita 8 caracteres o más.' }, 400);
  }
  if (!ROLES.includes(rol as Rol)) {
    return responder({ error: 'Ese rol no existe.' }, 400);
  }
  if (!PUEDE_CREAR[quienEs].includes(rol as Rol)) {
    return responder(
      { error: `Desde tu cuenta no se pueden crear cuentas de ${rol}.` },
      403,
    );
  }

  if (zonaId) {
    const { data: zona } = await admin
      .from('zonas')
      .select('id')
      .eq('id', zonaId)
      .eq('agencia_id', agenciaId)
      .maybeSingle();
    if (!zona) return responder({ error: 'Esa zona no es de esta agencia.' }, 400);
  }

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
      zona_id: zonaId,
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
    zona_id: zonaId,
    agencia: agencia.nombre,
  });
});
