import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../funciones/agencias/pantalla_agencias.dart';
import '../funciones/auth/pantalla_login.dart';
import '../funciones/campanas/pantalla_campanas.dart';
import '../funciones/configuracion/pantalla_configuracion.dart';
import '../funciones/gastos/pantalla_gastos.dart';
import '../funciones/interesados/pantalla_interesados.dart';
import '../funciones/inventario/pantalla_ficha.dart';
import '../funciones/inventario/pantalla_inventario.dart';
import '../funciones/panel/pantalla_panel.dart';
import '../funciones/precios/pantalla_precios.dart';
import '../funciones/ventas/pantalla_ventas.dart';
import '../funciones/vehiculos/pantalla_vehiculos.dart';
import '../ui/shell/secciones.dart';
import '../ui/shell/shell_adaptativo.dart';
import 'sesion.dart';
import 'transiciones.dart';

/// Permite que go_router reaccione a los cambios de sesion.
///
/// go_router necesita un Listenable para reevaluar el redirect; Riverpod
/// expone un stream. Este puente los une sin que la UI tenga que enterarse.
class _AvisoSesion extends ChangeNotifier {
  _AvisoSesion(Ref ref) {
    ref.listen(sesionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final aviso = _AvisoSesion(ref);
  ref.onDispose(aviso.dispose);

  return GoRouter(
    initialLocation: Secciones.panel.ruta,
    refreshListenable: aviso,

    // Guard unico: no hay pantalla que tenga que chequear sesion por su cuenta.
    redirect: (context, state) {
      final estado = ref.read(sesionProvider);
      final abierta = estado is SesionAbierta;
      final enLogin = state.matchedLocation == '/login';

      if (!abierta) return enLogin ? null : '/login';
      if (enLogin) return Secciones.panel.ruta;
      return null;
    },

    routes: [
      // El login vive afuera del shell, asi que no pasa por CambioDeSeccion:
      // se queda con la transicion de Material, que para entrar y salir de la
      // app esta bien.
      GoRoute(path: '/login', builder: (_, _) => const PantallaLogin()),

      ShellRoute(
        builder: (_, _, child) => ShellAdaptativo(child: child),
        routes: [
          GoRoute(
            path: Secciones.panel.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaPanel()),
          ),
          GoRoute(
            path: Secciones.inventario.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaInventario()),
            routes: [
              // La ficha SI es un adentro de la lista, asi que entra de
              // costado en vez de fundirse: el movimiento cuenta de donde
              // viene y hacia donde vuelve.
              GoRoute(
                path: ':id',
                pageBuilder: (_, estado) => Transiciones.paginaDetalle(
                  estado,
                  PantallaFicha(id: estado.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: Secciones.interesados.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaInteresados()),
          ),
          GoRoute(
            path: Secciones.vehiculos.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaVehiculos()),
          ),
          GoRoute(
            path: Secciones.gastos.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaGastos()),
          ),
          GoRoute(
            path: Secciones.precios.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaPrecios()),
          ),
          GoRoute(
            path: Secciones.ventas.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaVentas()),
          ),
          GoRoute(
            path: Secciones.campanas.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaCampanas()),
          ),
          GoRoute(
            path: Secciones.configuracion.ruta,
            pageBuilder: (_, estado) => Transiciones.paginaSeccion(
              estado,
              const PantallaConfiguracion(),
            ),
          ),
          GoRoute(
            path: Secciones.agencias.ruta,
            pageBuilder: (_, estado) =>
                Transiciones.paginaSeccion(estado, const PantallaAgencias()),
          ),
        ],
      ),
    ],

    errorBuilder: (context, estado) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Esa pantalla no existe'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go(Secciones.panel.ruta),
                child: const Text('Volver al panel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
