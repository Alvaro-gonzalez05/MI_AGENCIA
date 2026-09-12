import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../dominio/modelos.dart';
import '../dominio/motor_calculo.dart';
import 'datos_demo.dart';

/// Acceso a datos.
///
/// La UI habla siempre con esta interfaz, nunca con Supabase directamente.
/// Eso es lo que permite que la app entera funcione hoy en modo demo y que
/// manana, al conectar la base, no haya que tocar una sola pantalla: solo
/// cambia que implementacion devuelve el provider.
abstract interface class Repositorio {
  Future<List<VehiculoInventario>> inventario();
  Future<List<Interesado>> interesados();
  Future<ConfigAgencia> config();
}

/// Implementacion en memoria con los datos de ejemplo del cliente.
class RepositorioDemo implements Repositorio {
  const RepositorioDemo();

  @override
  Future<List<VehiculoInventario>> inventario() async {
    // Demora minima a proposito: deja ver los estados de carga reales de la
    // UI en vez de que todo aparezca instantaneo y nunca se prueben.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return Motor.inventario();
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

/// PENDIENTE: implementacion contra Supabase.
///
/// Cada metodo es un select sobre las vistas que ya existen en la base:
///   inventario()  -> select * from v_inventario
///   interesados() -> select * from oportunidades join v_clientes_semaforo
///   config()      -> select * from agencia_config
///
/// No se escribe todavia porque el proyecto de Supabase aun no esta creado y
/// no tiene sentido codear contra un esquema que no se puede ejecutar.
class RepositorioSupabase implements Repositorio {
  const RepositorioSupabase();

  @override
  Future<List<VehiculoInventario>> inventario() =>
      throw UnimplementedError('Falta conectar Supabase. Ver docs/PENDIENTE.md');

  @override
  Future<List<Interesado>> interesados() =>
      throw UnimplementedError('Falta conectar Supabase. Ver docs/PENDIENTE.md');

  @override
  Future<ConfigAgencia> config() =>
      throw UnimplementedError('Falta conectar Supabase. Ver docs/PENDIENTE.md');
}

final repositorioProvider = Provider<Repositorio>((ref) =>
    Config.modoDemo ? const RepositorioDemo() : const RepositorioSupabase());

final inventarioProvider = FutureProvider<List<VehiculoInventario>>(
  (ref) => ref.watch(repositorioProvider).inventario(),
);

final interesadosProvider = FutureProvider<List<Interesado>>(
  (ref) => ref.watch(repositorioProvider).interesados(),
);

/// La config se lee sincrona porque casi todas las pantallas la necesitan
/// para pintar umbrales, y bloquear cada una en un FutureBuilder por un par
/// de numeros seria ruido. En modo demo son constantes; cuando este Supabase,
/// se precarga al abrir sesion.
final configProvider = Provider<ConfigAgencia>((ref) => const ConfigAgencia());

/// Totales derivados del inventario ya cargado: no se vuelve a pedir nada.
final resumenProvider = Provider<ResumenAgencia>((ref) {
  final inv = ref.watch(inventarioProvider).value ?? const [];
  return Motor.resumen(inv);
});
