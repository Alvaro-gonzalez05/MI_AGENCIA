import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../dominio/alta_vehiculo.dart';
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
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  });
  Future<List<Interesado>> interesados();
  Future<ConfigAgencia> config();

  /// Codigo sugerido para la proxima unidad (V001, V002...). Lo calcula la
  /// base por agencia, no la app: dos vendedores cargando a la vez desde
  /// distintas maquinas no pueden generar el mismo.
  Future<String> siguienteCodigo();

  /// Da de alta una unidad y devuelve su id.
  Future<String> crearVehiculo(AltaVehiculo v);

  Future<void> actualizarVehiculo(AltaVehiculo v);

  /// Baja logica: conserva el historial de gastos, precios y ventas.
  Future<void> eliminarVehiculo(String id);
}

/// Implementacion en memoria con los datos de ejemplo del cliente.
///
/// Las altas se guardan en una lista y se pierden al cerrar la app. Es a
/// proposito: el modo demo sirve para recorrer la app, no para trabajar.
class RepositorioDemo implements Repositorio {
  RepositorioDemo();

  final List<VehiculoSemilla> _agregados = [];

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async {
    // Demora minima a proposito: deja ver los estados de carga reales de la
    // UI en vez de que todo aparezca instantaneo y nunca se prueben.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return Motor.inventario(extras: _agregados)
        .skip(desde)
        .take(cantidad)
        .toList();
  }

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<String> siguienteCodigo() async {
    final usados = [
      ...DatosDemo.vehiculos.map((v) => v.codigo),
      ..._agregados.map((v) => v.codigo),
    ];
    final numeros = usados.map(
      (c) => int.tryParse(c.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
    );
    final siguiente =
        (numeros.isEmpty ? 0 : numeros.reduce((a, b) => a > b ? a : b)) + 1;
    return 'V${siguiente.toString().padLeft(3, '0')}';
  }

  @override
  Future<String> crearVehiculo(AltaVehiculo v) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final codigo = v.codigo ?? await siguienteCodigo();
    _agregados.add(
      VehiculoSemilla(
        codigo: codigo,
        marca: v.marca.trim(),
        modelo: v.modelo.trim(),
        anio: v.anio!,
        version: v.version.trim().isEmpty ? null : v.version.trim(),
        km: v.km,
        fechaCompra: v.fechaCompra!,
        fechaIngreso: v.fechaIngreso!,
        precioCompra: v.precioCompra!,
        precioObjetivo: v.precioObjetivo!,
        estado: v.estado,
        observaciones: v.observaciones.trim().isEmpty
            ? null
            : v.observaciones.trim(),
      ),
    );
    return codigo;
  }

  @override
  Future<void> actualizarVehiculo(AltaVehiculo v) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final i = _agregados.indexWhere((x) => x.codigo == v.codigo);
    if (i < 0) {
      throw Exception(
        'En modo demo solo se pueden editar las unidades que '
        'cargaste vos en esta sesion.',
      );
    }
    _agregados.removeAt(i);
    await crearVehiculo(v);
  }

  @override
  Future<void> eliminarVehiculo(String id) async {
    _agregados.removeWhere((x) => x.codigo == id);
  }

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

final repositorioProvider = Provider<Repositorio>(
  (ref) => Config.modoDemo ? RepositorioDemo() : const RepositorioSupabase(),
);

final inventarioProvider = FutureProvider<List<VehiculoInventario>>(
  (ref) => ref.watch(repositorioProvider).inventario(),
);

final interesadosProvider = FutureProvider<List<Interesado>>(
  (ref) => ref.watch(repositorioProvider).interesados(),
);

final configAsyncProvider = FutureProvider<ConfigAgencia>(
  (ref) => ref.watch(repositorioProvider).config(),
);

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
