import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../funciones/auth/pantalla_login.dart';
import '../funciones/interesados/pantalla_interesados.dart';
import '../funciones/inventario/pantalla_ficha.dart';
import '../funciones/inventario/pantalla_inventario.dart';
import '../funciones/pantalla_pendiente.dart';
import '../funciones/panel/pantalla_panel.dart';
import '../funciones/vehiculos/pantalla_vehiculos.dart';
import '../ui/shell/secciones.dart';
import '../ui/shell/shell_adaptativo.dart';
import 'sesion.dart';

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
      GoRoute(path: '/login', builder: (_, _) => const PantallaLogin()),

      ShellRoute(
        builder: (_, _, child) => ShellAdaptativo(child: child),
        routes: [
          GoRoute(
            path: Secciones.panel.ruta,
            builder: (_, _) => const PantallaPanel(),
          ),
          GoRoute(
            path: Secciones.inventario.ruta,
            builder: (_, _) => const PantallaInventario(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, estado) =>
                    PantallaFicha(id: estado.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: Secciones.interesados.ruta,
            builder: (_, _) => const PantallaInteresados(),
          ),
          GoRoute(
            path: Secciones.vehiculos.ruta,
            builder: (_, _) => const PantallaVehiculos(),
          ),
          GoRoute(
            path: Secciones.gastos.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.gastos,
              puntos: [
                'Carga rápida de gastos por unidad, con las diez categorías del '
                    'sistema original.',
                'Adjuntar el comprobante como foto o PDF.',
                'Cada gasto queda ajustado por el IPC del mes en que se hizo, '
                    'que es lo que permite saber el costo real de hoy.',
                'Vista por categoría para detectar en qué se va la plata.',
              ],
            ),
          ),
          GoRoute(
            path: Secciones.precios.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.precios,
              puntos: [
                'Historial completo de cambios de precio por unidad, con motivo.',
                'El precio anterior lo completa la base sola: el usuario solo '
                    'escribe el nuevo.',
                'Gráfico de la evolución del precio contra el costo acumulado.',
              ],
            ),
          ),
          GoRoute(
            path: Secciones.ventas.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.ventas,
              puntos: [
                'Registro de la venta: precio final, gastos de cierre, '
                    'comprador y vendedor.',
                'Al guardarla, la unidad sale del stock automáticamente.',
                'Margen real de la operación, en pesos nominales, ajustado por '
                    'inflación y en dólares.',
                'Una unidad no se puede vender dos veces: lo impide la base.',
              ],
            ),
          ),
          GoRoute(
            path: Secciones.campanas.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.campanas,
              puntos: [
                'Armado de campañas de email a la base de interesados.',
                'Segmentación por semáforo crediticio, interés y marca buscada: '
                    'por ejemplo, todos los que preguntaron por una pickup y '
                    'están en verde.',
                'Envío por Resend o Brevo desde una Edge Function, con '
                    'seguimiento de aperturas y clics.',
                'Baja automática: a quien pide no recibir más, no se le vuelve '
                    'a escribir nunca.',
              ],
            ),
          ),
          GoRoute(
            path: Secciones.configuracion.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.configuracion,
              puntos: [
                'Umbrales de rotación, margen mínimo y objetivo, redondeo de '
                    'precios y tasa de financiación.',
                'Todo el sistema se recalcula solo al guardarlos.',
                'Serie del IPC del INDEC y cotización del dólar, actualizadas '
                    'automáticamente.',
                'Usuarios de la agencia: invitar, asignar rol y dar de baja.',
              ],
            ),
          ),
          GoRoute(
            path: Secciones.agencias.ruta,
            builder: (_, _) => const PantallaPendiente(
              seccion: Secciones.agencias,
              puntos: [
                'Panel exclusivo de la cuenta de desarrollador.',
                'Alta de agencias cliente: nombre, CUIT, plan y vencimiento.',
                'Invitar al dueño de cada agencia por email; al registrarse '
                    'queda vinculado solo.',
                'Suspender una agencia sin borrarle los datos.',
                'Métricas de uso por agencia.',
              ],
            ),
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
