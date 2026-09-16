import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../dominio/alta_vehiculo.dart';
import '../dominio/alta_interesado.dart';
import '../dominio/agencias.dart';
import '../dominio/bcra.dart';
import '../dominio/campanas.dart';
import '../dominio/gastos.dart';
import '../dominio/precios.dart';
import '../dominio/ventas.dart';
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
  Future<Interesado> crearInteresado(AltaInteresado alta);
  Future<void> guardarInforme(Interesado interesado, List<int> bytes);
  Future<List<InformeGuardado>> informes(Interesado interesado);
  Future<List<int>> descargarInforme(String ruta);
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

  /// Gastos de una unidad, o de toda la agencia si no se pasa ninguna.
  Future<List<Gasto>> gastos({String? vehiculoId});

  Future<void> crearGasto(AltaGasto g);

  Future<void> eliminarGasto(String id);

  /// Historial de precios de una unidad, o de toda la agencia.
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId});

  Future<void> crearCambioPrecio(AltaPrecio p);

  Future<List<Venta>> ventas();

  /// Al guardarla, un trigger de la base saca la unidad del stock.
  Future<void> crearVenta(AltaVenta v);

  /// Guarda los umbrales de la agencia. Al volver, todo el sistema se
  /// recalcula solo: el motor lee esta config en cada consulta.
  Future<void> guardarConfig(ConfigAgencia c);

  /// La agencia del usuario: nombre, CUIT, contacto.
  ///
  /// No es lo mismo que [config], que son los umbrales del motor de calculo.
  /// Esto es la identidad: lo que sale en el encabezado y en los informes.
  Future<Agencia?> miAgencia();

  /// Guarda los datos de la propia agencia. Solo el dueno puede.
  ///
  /// Plan, vencimiento y estado no entran: los blinda un trigger de la base
  /// para que nadie se mejore el plan solo.
  Future<void> guardarDatosAgencia(DatosAgencia d);

  // --- Solo para la cuenta de desarrollador ---

  Future<List<Agencia>> agencias();

  /// Crea la agencia e invita a su dueño. Devuelve el id de la agencia.
  Future<String> crearAgencia(AltaAgencia a);

  /// Suspende o reactiva una agencia sin borrarle los datos.
  Future<void> cambiarEstadoAgencia(String id, {required bool activa});

  Future<List<Invitacion>> invitacionesPendientes();

  // --- BCRA ---

  /// Consulta la situacion crediticia en la Central de Deudores del BCRA.
  ///
  /// La hace el servidor, no la app: el BCRA no manda cabeceras CORS, asi
  /// que un fetch desde el cliente falla siempre. De paso queda el historial
  /// guardado y cacheado, porque el BCRA publica una vez por mes y volver a
  /// preguntar antes no trae nada nuevo.
  ///
  /// [forzar] saltea ese cache. Sirve para el boton "volver a consultar"
  /// cuando el vendedor sabe que la persona regularizo su situacion.
  Future<ConsultaBcra> consultarBcra({
    required String clienteId,
    required String cuit,
    bool forzar = false,
  });

  /// Guarda el CUIT de una persona. Es lo unico que hace falta para poder
  /// consultarle el BCRA.
  Future<void> guardarCuit({required String clienteId, required String cuit});

  // --- Email marketing ---

  Future<List<Campana>> campanas();

  Future<String> crearCampana(AltaCampana c);

  /// Cuantos clientes recibirian la campana. Excluye a los que pidieron la
  /// baja: eso no es configurable.
  Future<int> destinatariosPosibles();

  /// Dispara el envio en el servidor. Devuelve cuantos salieron.
  Future<int> enviarCampana(String campanaId);
}

/// Implementacion en memoria con los datos de ejemplo del cliente.
///
/// Las altas se guardan en una lista y se pierden al cerrar la app. Es a
/// proposito: el modo demo sirve para recorrer la app, no para trabajar.
class RepositorioDemo implements Repositorio {
  RepositorioDemo();

  final List<VehiculoSemilla> _agregados = [];
  final List<GastoSemilla> _gastosAgregados = [];
  final List<PrecioSemilla> _preciosAgregados = [];
  final List<VentaSemilla> _ventasAgregadas = [];

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
  Future<ConfigAgencia> config() async => _config;

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
  Future<List<Gasto>> gastos({String? vehiculoId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final inv = Motor.inventario(
      extras: _agregados,
      gastosExtra: _gastosAgregados,
    );

    // En demo el id del vehiculo ES su codigo, asi que se filtra por codigo.
    final todos =
        [
            ...DatosDemo.gastos,
            ..._gastosAgregados,
          ].where((g) => vehiculoId == null || g.codigo == vehiculoId).toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));

    return todos.map((g) {
      final v = inv.where((x) => x.codigo == g.codigo).firstOrNull;
      return Gasto(
        // La semilla no trae id: se arma uno estable con lo que la identifica.
        id: '${g.codigo}-${g.fecha.toIso8601String()}-${g.importe}',
        vehiculoId: g.codigo,
        fecha: g.fecha,
        categoria: CategoriaGasto.desde(g.categoria),
        importe: g.importe,
        descripcion: g.descripcion,
        vehiculoCodigo: g.codigo,
        vehiculoTitulo: v?.titulo,
      );
    }).toList();
  }

  @override
  Future<void> crearGasto(AltaGasto g) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _gastosAgregados.add(
      GastoSemilla(
        codigo: g.vehiculoId!,
        fecha: g.fecha!,
        categoria: g.categoria.valorBd,
        descripcion: g.descripcion.trim().isEmpty ? null : g.descripcion.trim(),
        importe: g.importe!,
      ),
    );
  }

  List<VehiculoInventario> _inv() => Motor.inventario(
    extras: _agregados,
    gastosExtra: _gastosAgregados,
    preciosExtra: _preciosAgregados,
    ventasExtra: _ventasAgregadas,
  );

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final inv = _inv();

    final todos =
        [
            ...DatosDemo.precios,
            ..._preciosAgregados,
          ].where((x) => vehiculoId == null || x.codigo == vehiculoId).toList()
          ..sort((a, b) => a.fecha.compareTo(b.fecha));

    // El precio anterior se reconstruye recorriendo en orden cronologico,
    // que es lo que hace el trigger de la base al insertar.
    final anteriorPorCodigo = <String, double>{};
    final resultado = <CambioPrecio>[];
    for (final x in todos) {
      final v = inv.where((i) => i.codigo == x.codigo).firstOrNull;
      final anterior = anteriorPorCodigo[x.codigo] ?? v?.precioObjetivo;
      resultado.add(
        CambioPrecio(
          id: '${x.codigo}-${x.fecha.toIso8601String()}-${x.precio}',
          vehiculoId: x.codigo,
          fecha: x.fecha,
          precioNuevo: x.precio,
          precioAnterior: anterior,
          motivo: x.motivo,
          vehiculoCodigo: x.codigo,
          vehiculoTitulo: v?.titulo,
        ),
      );
      anteriorPorCodigo[x.codigo] = x.precio;
    }
    return resultado.reversed.toList();
  }

  @override
  Future<void> crearCambioPrecio(AltaPrecio p) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _preciosAgregados.add(
      PrecioSemilla(
        codigo: p.vehiculoId!,
        fecha: p.fecha!,
        precio: p.precioNuevo!,
        motivo: p.motivo.trim().isEmpty ? null : p.motivo.trim(),
      ),
    );
  }

  @override
  Future<List<Venta>> ventas() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final inv = _inv();
    final cfg = const ConfigAgencia();

    return [...DatosDemo.ventas, ..._ventasAgregadas].map((x) {
      final v = inv.where((i) => i.codigo == x.codigo).firstOrNull;
      return Venta(
        id: '${x.codigo}-${x.fecha.toIso8601String()}',
        vehiculoId: x.codigo,
        fechaVenta: x.fecha,
        precioFinal: x.precioFinal,
        gastosFinales: x.gastosFinales,
        observaciones: x.obs,
        vehiculoCodigo: x.codigo,
        vehiculoTitulo: v?.titulo,
        costoTotal: v?.costoTotal,
        costoTotalHoy: v?.costoTotalHoy,
        diasEnStock: v?.diasEnStock,
        tipoCambio: cfg.tipoCambio,
      );
    }).toList()..sort((a, b) => b.fechaVenta.compareTo(a.fechaVenta));
  }

  @override
  Future<void> crearVenta(AltaVenta v) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _ventasAgregadas.add(
      VentaSemilla(
        codigo: v.vehiculoId!,
        fecha: v.fechaVenta!,
        precioFinal: v.precioFinal!,
        gastosFinales: v.gastosFinales,
        obs: v.observaciones.trim().isEmpty ? null : v.observaciones.trim(),
      ),
    );
  }

  ConfigAgencia _config = const ConfigAgencia();
  final List<Agencia> _agencias = [];

  @override
  Future<void> guardarConfig(ConfigAgencia c) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _config = c;
  }

  Agencia _miAgencia = Agencia(
    id: 'demo',
    nombre: 'Agencia Demo',
    slug: 'demo',
    activa: true,
    plan: 'basico',
    localidad: 'Godoy Cruz',
    provincia: 'Mendoza',
    creadaEl: DateTime(2026, 9, 12),
  );

  @override
  Future<Agencia?> miAgencia() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _miAgencia;
  }

  @override
  Future<void> guardarDatosAgencia(DatosAgencia d) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final a = _miAgencia;
    _miAgencia = Agencia(
      id: a.id,
      nombre: d.nombre.trim(),
      slug: a.slug,
      activa: a.activa,
      plan: a.plan,
      cuit: d.cuitLimpio.isEmpty ? null : d.cuitLimpio,
      emailContacto: d.emailContacto.trim().isEmpty
          ? null
          : d.emailContacto.trim(),
      telefono: d.telefono.trim().isEmpty ? null : d.telefono.trim(),
      localidad: d.localidad.trim().isEmpty ? null : d.localidad.trim(),
      provincia: d.provincia.trim().isEmpty ? null : d.provincia.trim(),
      vigenteHasta: a.vigenteHasta,
      creadaEl: a.creadaEl,
    );
  }

  @override
  Future<List<Agencia>> agencias() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return [
      Agencia(
        id: 'demo',
        nombre: 'Agencia Demo',
        slug: 'demo',
        activa: true,
        plan: 'basico',
        localidad: 'Godoy Cruz',
        provincia: 'Mendoza',
        miembros: 1,
        vehiculos: DatosDemo.vehiculos.length + _agregados.length,
        creadaEl: DateTime(2026, 9, 12),
      ),
      ..._agencias,
    ];
  }

  @override
  Future<String> crearAgencia(AltaAgencia a) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final id = 'demo-${_agencias.length + 1}';
    _agencias.add(
      Agencia(
        id: id,
        nombre: a.nombre.trim(),
        slug: a.slug,
        activa: true,
        plan: a.plan,
        cuit: a.cuitLimpio.isEmpty ? null : a.cuitLimpio,
        emailContacto: a.emailContacto.trim().isEmpty
            ? null
            : a.emailContacto.trim(),
        localidad: a.localidad.trim().isEmpty ? null : a.localidad.trim(),
        provincia: a.provincia.trim().isEmpty ? null : a.provincia.trim(),
        vigenteHasta: a.vigenteHasta,
        creadaEl: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<void> cambiarEstadoAgencia(String id, {required bool activa}) async {
    final i = _agencias.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = _agencias[i];
    _agencias[i] = Agencia(
      id: a.id,
      nombre: a.nombre,
      slug: a.slug,
      activa: activa,
      plan: a.plan,
      cuit: a.cuit,
      emailContacto: a.emailContacto,
      telefono: a.telefono,
      localidad: a.localidad,
      provincia: a.provincia,
      vigenteHasta: a.vigenteHasta,
      creadaEl: a.creadaEl,
      miembros: a.miembros,
      vehiculos: a.vehiculos,
    );
  }

  @override
  Future<List<Invitacion>> invitacionesPendientes() async => const [];

  final List<Campana> _campanas = [];

  @override
  Future<List<Campana>> campanas() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.of(_campanas.reversed);
  }

  @override
  Future<String> crearCampana(AltaCampana c) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final id = 'campana-${_campanas.length + 1}';
    _campanas.add(
      Campana(
        id: id,
        nombre: c.nombre.trim(),
        asunto: c.asunto.trim(),
        estado: EstadoCampana.borrador,
        cuerpoHtml: c.html,
        creadaEl: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<int> destinatariosPosibles() async {
    // En demo los interesados no tienen email cargado: el numero honesto
    // es cero, y la pantalla lo explica en vez de inventar un total.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return 0;
  }

  @override
  Future<int> enviarCampana(String campanaId) async {
    throw Exception(
      'El envio real necesita la base conectada y la Edge Function '
      'desplegada. En modo demo la campana se guarda pero no sale.',
    );
  }

  @override
  Future<void> eliminarGasto(String id) async {
    _gastosAgregados.removeWhere(
      (g) => '${g.codigo}-${g.fecha.toIso8601String()}-${g.importe}' == id,
    );
  }

  /// CUIT que se cargaron en esta sesion de demo.
  final Map<String, String> _cuits = {};
  final Map<String, Interesado> _altasInteresados = {};
  final Map<String, List<int>> _informes = {};

  @override
  Future<Interesado> crearInteresado(AltaInteresado alta) async {
    alta.validar();
    return _altasInteresados.putIfAbsent(
      alta.solicitud,
      () => alta.comoInteresado(alta.solicitud, alta.solicitud),
    );
  }

  @override
  Future<void> guardarInforme(Interesado interesado, List<int> bytes) async {
    _informes['${interesado.id}/informe.pdf'] = List.of(bytes);
  }

  @override
  Future<List<InformeGuardado>> informes(Interesado interesado) async => [
    for (final ruta in _informes.keys.where(
      (r) => r.startsWith('${interesado.id}/'),
    ))
      InformeGuardado(ruta: ruta, fecha: DateTime.now()),
  ];

  @override
  Future<List<int>> descargarInforme(String ruta) async => _informes[ruta]!;

  @override
  Future<List<Interesado>> interesados() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final inv = Motor.inventario();

    // Los interesados del sistema original no tienen CUIT ni consulta al
    // BCRA, asi que el semaforo arranca en "sin consultar", que es la verdad.
    return [
      ..._altasInteresados.values,
      ...DatosDemo.interesados.map((i) {
        final v = inv.where((x) => x.codigo == i.codigo).firstOrNull;
        final id = '${i.codigo}-${i.nombre}';
        return Interesado(
          id: id,
          clienteId: id,
          nombre: i.nombre,
          telefono: i.telefono,
          cuit: _cuits[id],
          vehiculoCodigo: i.codigo,
          vehiculoTitulo: v?.titulo,
          vehiculoPrecio: v?.precioActual,
          notas: i.notas,
          fecha: i.fecha,
        );
      }),
    ];
  }

  @override
  Future<void> guardarCuit({
    required String clienteId,
    required String cuit,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _cuits[clienteId] = cuit.replaceAll(RegExp(r'\D'), '');
  }

  @override
  Future<ConsultaBcra> consultarBcra({
    required String clienteId,
    required String cuit,
    bool forzar = false,
  }) async {
    // No se inventa una situacion crediticia ni para la demo. Un semaforo
    // verde falso es exactamente el dato que hace que una agencia financie
    // a quien no debia: el modo demo dice la verdad, que es que no consulto.
    throw Exception(
      'La consulta al BCRA necesita la base conectada. En modo demo no se '
      'consulta nada, y un resultado inventado seria peor que ninguno.',
    );
  }
}

final repositorioProvider = Provider<Repositorio>(
  (ref) => Config.modoDemo ? RepositorioDemo() : const RepositorioSupabase(),
);

final inventarioProvider = FutureProvider<List<VehiculoInventario>>(
  (ref) => ref.watch(repositorioProvider).inventario(),
);

final gastosProvider = FutureProvider<List<Gasto>>(
  (ref) => ref.watch(repositorioProvider).gastos(),
);

/// Gastos de una unidad, para la ficha.
final gastosDeVehiculoProvider = FutureProvider.family<List<Gasto>, String>(
  (ref, vehiculoId) =>
      ref.watch(repositorioProvider).gastos(vehiculoId: vehiculoId),
);

final preciosProvider = FutureProvider<List<CambioPrecio>>(
  (ref) => ref.watch(repositorioProvider).cambiosPrecio(),
);

final ventasProvider = FutureProvider<List<Venta>>(
  (ref) => ref.watch(repositorioProvider).ventas(),
);

final campanasProvider = FutureProvider<List<Campana>>(
  (ref) => ref.watch(repositorioProvider).campanas(),
);

final destinatariosProvider = FutureProvider<int>(
  (ref) => ref.watch(repositorioProvider).destinatariosPosibles(),
);

final agenciasProvider = FutureProvider<List<Agencia>>(
  (ref) => ref.watch(repositorioProvider).agencias(),
);

final interesadosProvider = FutureProvider<List<Interesado>>(
  (ref) => ref.watch(repositorioProvider).interesados(),
);

final configAsyncProvider = FutureProvider<ConfigAgencia>(
  (ref) => ref.watch(repositorioProvider).config(),
);

/// La agencia del usuario. La leen el encabezado y el informe crediticio.
final miAgenciaProvider = FutureProvider<Agencia?>(
  (ref) => ref.watch(repositorioProvider).miAgencia(),
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
