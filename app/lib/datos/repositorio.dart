import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../dominio/modelos.dart';
import '../dominio/motor_calculo.dart';
import 'datos_demo.dart';
import 'repositorio_supabase.dart';

/// Acceso a datos.
///
/// La UI habla siempre con esta interfaz, nunca con Supabase directamente.
/// Eso es lo que permite que la app entera funcione hoy en modo demo y que
/// manana, al conectar la base, no haya que tocar una sola pantalla: solo
/// cambia que implementacion devuelve el provider.
abstract interface class Repositorio {
  /// Pagina desde `desde`, trayendo hasta `cantidad` filas. El tope alto por
  /// defecto alcanza para cualquier agencia real; la paginacion existe para
  /// que el contrato no haya que cambiarlo cuando deje de alcanzar.
  Future<List<VehiculoInventario>> inventario({int desde = 0, int cantidad = 500});
  Future<List<Interesado>> interesados();
  Future<ConfigAgencia> config();
}

/// Implementacion en memoria con los datos de ejemplo del cliente.
class RepositorioDemo implements Repositorio {
  const RepositorioDemo();

  @override
  Future<List<VehiculoInventario>> inventario({int desde = 0, int cantidad = 500}) async {
    // Demora minima a proposito: deja ver los estados de carga reales de la
    // UI en vez de que todo aparezca instantaneo y nunca se prueben.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return Motor.inventario().skip(desde).take(cantidad).toList();
  }

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<List<Interesado>> interesados() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final inv = Motor.inventario();

    // Los interesados del sistema original no tienen CUIT ni consulta al
    // BCRA, asi que el semaforo arranca en "sin consultar", que es la verdad.
    return DatosDemo.interesados.map((i) {
      final v = inv.where((x) => x.codigo == i.codigo).firstOrNull;
      return Interesado(
        id: '${i.codigo}-${i.nombre}',
        nombre: i.nombre,
        telefono: i.telefono,
        semaforo: SemaforoCrediticio.sinDatos,
        vehiculoCodigo: i.codigo,
        vehiculoTitulo: v?.titulo,
        notas: i.notas,
        fecha: i.fecha,
      );
    }).toList();
  }
}

final repositorioProvider = Provider<Repositorio>((ref) =>
    Config.modoDemo ? const RepositorioDemo() : const RepositorioSupabase());

final inventarioProvider = FutureProvider<List<VehiculoInventario>>(
  (ref) => ref.watch(repositorioProvider).inventario(),
);

final interesadosProvider = FutureProvider<List<Interesado>>(
  (ref) => ref.watch(repositorioProvider).interesados(),
);

final configAsyncProvider =
    FutureProvider<ConfigAgencia>((ref) => ref.watch(repositorioProvider).config());

/// La config se lee sincrona porque casi todas las pantallas la necesitan para
/// pintar umbrales, y bloquear cada una en un FutureBuilder por un par de
/// numeros seria ruido. Mientras carga rigen los valores por defecto, que son
/// los mismos que la base pone al crear una agencia: la pantalla no parpadea.
final configProvider = Provider<ConfigAgencia>(
  (ref) => ref.watch(configAsyncProvider).value ?? const ConfigAgencia(),
);

/// Totales derivados del inventario ya cargado: no se vuelve a pedir nada.
final resumenProvider = Provider<ResumenAgencia>((ref) {
  final inv = ref.watch(inventarioProvider).value ?? const [];
  return Motor.resumen(inv);
});
