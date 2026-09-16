import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Usuario con sesion iniciada, ya resuelto a lo que la UI necesita saber.
@immutable
class Usuario {
  const Usuario({
    required this.id,
    required this.email,
    required this.nombre,
    required this.esDesarrollador,
    this.agenciaId,
    this.agenciaNombre,
    this.rol,
  });

  final String id;
  final String email;
  final String nombre;

  /// Cuenta de plataforma (nosotros): puede dar de alta agencias y ver todo.
  final bool esDesarrollador;

  final String? agenciaId;
  final String? agenciaNombre;
  final String? rol;

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1))
        .toUpperCase();
  }
}

sealed class EstadoSesion {
  const EstadoSesion();
}

class SesionCargando extends EstadoSesion {
  const SesionCargando();
}

class SesionCerrada extends EstadoSesion {
  const SesionCerrada({this.error});
  final String? error;
}

class SesionAbierta extends EstadoSesion {
  const SesionAbierta(this.usuario);
  final Usuario usuario;
}

class ControlSesion extends Notifier<EstadoSesion> {
  @override
  EstadoSesion build() {
    if (Config.modoDemo) return const SesionCerrada();
    final sesion = Supabase.instance.client.auth.currentSession;
    if (sesion == null) return const SesionCerrada();
    return SesionAbierta(_desdeSupabase(sesion.user));
  }

  /// Version minima, con lo que ya trae el token. Sirve para pintar la UI
  /// sin esperar a la red; [_completar] la enriquece despues.
  static Usuario _desdeSupabase(User u) => Usuario(
    id: u.id,
    email: u.email ?? '',
    nombre:
        (u.userMetadata?['nombre'] as String?) ??
        (u.email ?? '').split('@').first,
    esDesarrollador: false,
  );

  /// Trae el perfil y la agencia del usuario.
  ///
  /// `es_desarrollador` vive en public.perfiles y NO en el token a proposito:
  /// si viviera en los metadatos del usuario, cualquiera con la anon key
  /// podria intentar escribirselo. Asi, cambiarlo exige service_role.
  ///
  /// Si algo de esto falla no se cierra la sesion: se entra con los datos
  /// minimos. Quedarse afuera por no poder leer el nombre seria peor.
  static Future<Usuario> _completar(Usuario base) async {
    final db = Supabase.instance.client;
    try {
      final perfil = await db
          .from('perfiles')
          .select('nombre, apellido, es_desarrollador')
          .eq('id', base.id)
          .maybeSingle();

      final membresia = await db
          .from('membresias')
          .select('rol, agencia_id, agencias ( nombre )')
          .eq('usuario_id', base.id)
          .eq('activa', true)
          .order('agencia_id')
          .limit(1)
          .maybeSingle();

      final nombre = [
        perfil?['nombre'],
        perfil?['apellido'],
      ].whereType<String>().where((s) => s.isNotEmpty).join(' ');

      return Usuario(
        id: base.id,
        email: base.email,
        nombre: nombre.isEmpty ? base.nombre : nombre,
        esDesarrollador: perfil?['es_desarrollador'] as bool? ?? false,
        agenciaId: membresia?['agencia_id'] as String?,
        agenciaNombre: (membresia?['agencias'] as Map?)?['nombre'] as String?,
        rol: membresia?['rol'] as String?,
      );
    } catch (_) {
      return base;
    }
  }

  Future<void> ingresar({required String email, required String clave}) async {
    state = const SesionCargando();

    if (Config.modoDemo) {
      // Sin backend no hay nada que validar: se acepta cualquier credencial y
      // se entra a los datos de ejemplo. La cinta de "modo demo" lo deja claro
      // en pantalla para que nadie lo confunda con la app real.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      state = SesionAbierta(
        Usuario(
          id: 'demo',
          email: email.isEmpty ? 'demo@miagencia.app' : email,
          nombre: 'Usuario Demo',
          esDesarrollador: true,
          agenciaId: 'demo',
          agenciaNombre: 'Agencia Demo',
          rol: 'owner',
        ),
      );
      return;
    }

    try {
      final r = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: clave,
      );
      if (r.user == null) {
        state = const SesionCerrada(error: 'No se pudo iniciar sesión.');
        return;
      }
      state = SesionAbierta(await _completar(_desdeSupabase(r.user!)));
    } on AuthException catch (e) {
      state = SesionCerrada(error: _traducir(e.message));
    } catch (_) {
      state = const SesionCerrada(
        error: 'No se pudo conectar. Revisá tu conexión a internet.',
      );
    }
  }

  Future<void> salir() async {
    if (!Config.modoDemo) {
      await Supabase.instance.client.auth.signOut();
    }
    state = const SesionCerrada();
  }

  /// Supabase responde en ingles; el usuario final es una agencia argentina.
  static String _traducir(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Email o contraseña incorrectos.';
    }
    if (m.contains('email not confirmed')) {
      return 'Todavía no confirmaste tu email. Revisá tu casilla.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Demasiados intentos. Esperá un momento y probá de nuevo.';
    }
    return mensaje;
  }
}

final sesionProvider = NotifierProvider<ControlSesion, EstadoSesion>(
  ControlSesion.new,
);

/// Atajo: el usuario actual, o null si no hay sesion.
final usuarioProvider = Provider<Usuario?>((ref) {
  final s = ref.watch(sesionProvider);
  return s is SesionAbierta ? s.usuario : null;
});
