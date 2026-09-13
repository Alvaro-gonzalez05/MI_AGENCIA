import 'package:supabase_flutter/supabase_flutter.dart';

import '../dominio/alta_vehiculo.dart';
import '../dominio/gastos.dart';
import '../dominio/precios.dart';
import '../dominio/ventas.dart';
import '../dominio/modelos.dart';
import 'repositorio.dart';

/// Lectura contra la base real.
///
/// Las pantallas no saben que esto existe: hablan con [Repositorio]. Por eso
/// pasar de modo demo a base real no toca una sola linea de UI.
///
/// No hace falta filtrar por agencia en ningun select: el RLS de la base ya
/// devuelve solo las filas de las agencias del usuario. Filtrar de nuevo aca
/// seria seguridad de mentira, porque viviria en el cliente.
class RepositorioSupabase implements Repositorio {
  const RepositorioSupabase();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async {
    final filas = await _db
        .from('v_inventario')
        .select()
        .order('dias_en_stock', ascending: false)
        .range(desde, desde + cantidad - 1);

    return filas.map(_aVehiculo).toList();
  }

  @override
  Future<ConfigAgencia> config() async {
    final fila = await _db
        .from('agencia_config')
        .select()
        .limit(1)
        .maybeSingle();
    if (fila == null) return const ConfigAgencia();

    // El tipo de cambio no vive en agencia_config: la config solo elige CUAL
    // usar, y la cotizacion en si es un dato publico compartido.
    final tipo = fila['tipo_cambio_preferido'] as String? ?? 'oficial';
    final cotizacion = await _db
        .from('cotizaciones')
        .select('venta')
        .eq('tipo', tipo)
        .order('fecha', ascending: false)
        .limit(1)
        .maybeSingle();

    return ConfigAgencia(
      diasVerde: _entero(fila['dias_verde']) ?? 30,
      diasAmarillo: _entero(fila['dias_amarillo']) ?? 60,
      diasRojo: _entero(fila['dias_rojo']) ?? 90,
      margenMinimo: _decimal(fila['margen_minimo']) ?? 0.10,
      margenObjetivo: _decimal(fila['margen_objetivo']) ?? 0.30,
      toleranciaCaidaMargen: _decimal(fila['tolerancia_caida_margen']) ?? 0.005,
      toleranciaDesvioPrecio:
          _decimal(fila['tolerancia_desvio_precio']) ?? 0.02,
      umbralGastosAltos: _decimal(fila['umbral_gastos_altos']) ?? 1000000,
      redondeo: _decimal(fila['redondeo']) ?? 50000,
      capacidad: _entero(fila['capacidad']) ?? 60,
      tasaFinanciacionMensual:
          _decimal(fila['tasa_financiacion_mensual']) ?? 0.06,
      tipoCambio: _decimal(cotizacion?['venta']) ?? 1,
    );
  }

  @override
  Future<List<Interesado>> interesados() async {
    // Una sola ida y vuelta: PostgREST resuelve las relaciones anidadas.
    final filas = await _db
        .from('oportunidades')
        .select('''
          id, estado, interes, notas, created_at, proxima_accion_fecha,
          clientes!inner ( id, nombre, apellido, cuit, email, telefono ),
          vehiculos ( codigo, marca, modelo )
        ''')
        .order('created_at', ascending: false)
        .limit(500);

    if (filas.isEmpty) return const [];

    // El semaforo se resuelve aparte porque vive en una vista y PostgREST no
    // puede unirla dentro del mismo select anidado.
    final idsClientes = filas
        .map((f) => (f['clientes'] as Map)['id'] as String)
        .toSet()
        .toList();

    final semaforos = await _db
        .from('v_clientes_semaforo')
        .select('cliente_id, semaforo, situacion_maxima')
        .inFilter('cliente_id', idsClientes);

    final porCliente = {
      for (final s in semaforos) s['cliente_id'] as String: s,
    };

    return filas.map((f) {
      final cliente = f['clientes'] as Map<String, dynamic>;
      final vehiculo = f['vehiculos'] as Map<String, dynamic>?;
      final sem = porCliente[cliente['id']];

      return Interesado(
        id: f['id'] as String,
        nombre: [
          cliente['nombre'],
          cliente['apellido'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
        semaforo: _aSemaforo(sem?['semaforo'] as String?),
        telefono: cliente['telefono'] as String?,
        email: cliente['email'] as String?,
        cuit: cliente['cuit'] as String?,
        situacionBcra: _entero(sem?['situacion_maxima']),
        vehiculoCodigo: vehiculo?['codigo'] as String?,
        vehiculoTitulo: vehiculo == null
            ? null
            : '${vehiculo['marca']} ${vehiculo['modelo']}',
        notas: f['notas'] as String?,
        fecha: _fecha(f['created_at']),
      );
    }).toList();
  }

  // -------------------------------------------------------------------
  // Escritura
  // -------------------------------------------------------------------

  /// La agencia del usuario. Se resuelve en la base y no se guarda en el
  /// cliente: si viniera del cliente, bastaria con editarlo para escribir en
  /// la agencia de otro. El RLS lo rechazaria igual, pero mejor no llegar.
  Future<String> _miAgencia() async {
    final fila = await _db
        .from('membresias')
        .select('agencia_id')
        .eq('activa', true)
        .limit(1)
        .maybeSingle();
    if (fila == null) {
      throw Exception(
        'Tu usuario no está asignado a ninguna agencia. '
        'Pedile al administrador que te dé acceso.',
      );
    }
    return fila['agencia_id'] as String;
  }

  @override
  Future<String> siguienteCodigo() async {
    final agencia = await _miAgencia();
    final r = await _db.rpc<String>(
      'siguiente_codigo_vehiculo',
      params: {'p_agencia': agencia},
    );
    return r;
  }

  @override
  Future<String> crearVehiculo(AltaVehiculo v) async {
    final agencia = await _miAgencia();
    final fila = await _db
        .from('vehiculos')
        .insert({
          'agencia_id': agencia,
          'codigo': v.codigo ?? await siguienteCodigo(),
          ..._camposEditables(v),
        })
        .select('id')
        .single();
    return fila['id'] as String;
  }

  @override
  Future<void> actualizarVehiculo(AltaVehiculo v) async {
    if (v.id == null) throw ArgumentError('Falta el id del vehiculo a editar.');
    await _db.from('vehiculos').update(_camposEditables(v)).eq('id', v.id!);
  }

  @override
  Future<void> eliminarVehiculo(String id) async {
    // Baja logica: la unidad desaparece del inventario pero conserva su
    // historial de gastos, precios y ventas. Borrarla de verdad se llevaria
    // por cascada la trazabilidad de operaciones ya cerradas.
    await _db
        .from('vehiculos')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async {
    var consulta = _db.from('gastos').select('''
          id, vehiculo_id, fecha, categoria, descripcion, importe, proveedor,
          vehiculos!inner ( codigo, marca, modelo )
        ''');

    if (vehiculoId != null) consulta = consulta.eq('vehiculo_id', vehiculoId);

    final filas = await consulta.order('fecha', ascending: false).limit(500);

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      return Gasto(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fecha: _fecha(f['fecha']) ?? DateTime.now(),
        categoria: CategoriaGasto.desde(f['categoria'] as String?),
        importe: _decimal(f['importe']) ?? 0,
        descripcion: f['descripcion'] as String?,
        proveedor: f['proveedor'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
      );
    }).toList();
  }

  @override
  Future<void> crearGasto(AltaGasto g) async {
    final agencia = await _miAgencia();
    await _db.from('gastos').insert({
      'agencia_id': agencia,
      'vehiculo_id': g.vehiculoId,
      'fecha': _soloFecha(g.fecha!),
      'categoria': g.categoria.valorBd,
      'descripcion': _oNulo(g.descripcion),
      'proveedor': _oNulo(g.proveedor),
      'importe': g.importe,
    });
  }

  @override
  Future<void> eliminarGasto(String id) async {
    // Los gastos si se borran de verdad: a diferencia de una unidad, un gasto
    // mal cargado no tiene historial que preservar, y dejarlo marcado como
    // borrado obligaria a filtrarlo en cada suma del motor de calculo.
    await _db.from('gastos').delete().eq('id', id);
  }

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async {
    var consulta = _db.from('cambios_precio').select('''
          id, vehiculo_id, fecha, precio_anterior, precio_nuevo, motivo,
          vehiculos!inner ( codigo, marca, modelo )
        ''');

    if (vehiculoId != null) consulta = consulta.eq('vehiculo_id', vehiculoId);

    final filas = await consulta.order('fecha', ascending: false).limit(500);

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      return CambioPrecio(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fecha: _fecha(f['fecha']) ?? DateTime.now(),
        precioNuevo: _decimal(f['precio_nuevo']) ?? 0,
        precioAnterior: _decimal(f['precio_anterior']),
        motivo: f['motivo'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
      );
    }).toList();
  }

  @override
  Future<void> crearCambioPrecio(AltaPrecio p) async {
    final agencia = await _miAgencia();
    // precio_anterior NO se manda: lo completa un trigger leyendo el ultimo
    // precio vigente. Calcularlo en el cliente abre la puerta a que dos
    // vendedores guarden a la vez y uno pise el historial del otro.
    await _db.from('cambios_precio').insert({
      'agencia_id': agencia,
      'vehiculo_id': p.vehiculoId,
      'fecha': _soloFecha(p.fecha!),
      'precio_nuevo': p.precioNuevo,
      'motivo': _oNulo(p.motivo),
    });
  }

  @override
  Future<List<Venta>> ventas() async {
    final filas = await _db
        .from('ventas')
        .select('''
          id, vehiculo_id, fecha_venta, precio_final, gastos_finales,
          forma_pago, cuotas, observaciones,
          vehiculos!inner ( codigo, marca, modelo )
        ''')
        .order('fecha_venta', ascending: false)
        .limit(500);

    if (filas.isEmpty) return const [];

    // Los costos y el ajuste por IPC los calcula la vista, no la app.
    final ids = filas.map((f) => f['vehiculo_id'] as String).toList();
    final calculados = await _db
        .from('v_inventario')
        .select('id, costo_total, costo_total_hoy, dias_en_stock, tipo_cambio')
        .inFilter('id', ids);

    final porId = {for (final c in calculados) c['id'] as String: c};

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      final c = porId[f['vehiculo_id']];
      return Venta(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fechaVenta: _fecha(f['fecha_venta']) ?? DateTime.now(),
        precioFinal: _decimal(f['precio_final']) ?? 0,
        gastosFinales: _decimal(f['gastos_finales']) ?? 0,
        formaPago: f['forma_pago'] as String?,
        cuotas: _entero(f['cuotas']),
        observaciones: f['observaciones'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
        costoTotal: _decimal(c?['costo_total']),
        costoTotalHoy: _decimal(c?['costo_total_hoy']),
        diasEnStock: _entero(c?['dias_en_stock']),
        tipoCambio: _decimal(c?['tipo_cambio']),
      );
    }).toList();
  }

  @override
  Future<void> crearVenta(AltaVenta v) async {
    final agencia = await _miAgencia();
    // El estado del vehiculo no se toca desde aca: un trigger lo pasa a
    // vendido. Y la unicidad de vehiculo_id impide venderlo dos veces.
    await _db.from('ventas').insert({
      'agencia_id': agencia,
      'vehiculo_id': v.vehiculoId,
      'fecha_venta': _soloFecha(v.fechaVenta!),
      'precio_final': v.precioFinal,
      'gastos_finales': v.gastosFinales,
      'forma_pago': v.formaPago.etiqueta,
      'cuotas': v.pideCuotas ? v.cuotas : null,
      'observaciones': _oNulo(v.observaciones),
    });
  }

  /// Solo lo que el usuario carga. Todo lo demas (costos, margenes, dias en
  /// stock) lo deriva la base: mandarlo desde el cliente seria pisar el motor
  /// de calculo con numeros de dudosa procedencia.
  static Map<String, dynamic> _camposEditables(AltaVehiculo v) => {
    'marca': v.marca.trim(),
    'modelo': v.modelo.trim(),
    'anio': v.anio,
    'version': _oNulo(v.version),
    'km': v.km,
    'patente': _oNulo(v.patente)?.toUpperCase(),
    'fecha_compra': _soloFecha(v.fechaCompra!),
    'fecha_ingreso': _soloFecha(v.fechaIngreso!),
    'precio_compra': v.precioCompra,
    'precio_objetivo': v.precioObjetivo,
    'estado': _deEstado(v.estado),
    'observaciones': _oNulo(v.observaciones),
  };

  static String? _oNulo(String s) => s.trim().isEmpty ? null : s.trim();

  /// La columna es `date`: mandar un timestamp con hora hace que Postgres lo
  /// trunque segun zona horaria y la fecha se puede correr un dia.
  static String _soloFecha(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';

  static String _deEstado(EstadoVehiculo e) => switch (e) {
    EstadoVehiculo.enStock => 'en_stock',
    EstadoVehiculo.enPreparacion => 'en_preparacion',
    EstadoVehiculo.reservado => 'reservado',
    EstadoVehiculo.vendido => 'vendido',
    EstadoVehiculo.dadoDeBaja => 'dado_de_baja',
  };

  // -------------------------------------------------------------------
  // Conversores
  //
  // Postgres devuelve numeric como STRING en JSON, para no perder precision.
  // Si se castea directo a double explota en runtime, y encima solo con
  // ciertos valores: es el tipo de bug que aparece recien en produccion.
  // -------------------------------------------------------------------

  static double? _decimal(dynamic v) => switch (v) {
    null => null,
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _entero(dynamic v) => switch (v) {
    null => null,
    final int n => n,
    final num n => n.round(),
    final String s => int.tryParse(s) ?? double.tryParse(s)?.round(),
    _ => null,
  };

  static DateTime? _fecha(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  static EstadoVehiculo _aEstado(String? s) => switch (s) {
    'en_stock' => EstadoVehiculo.enStock,
    'en_preparacion' => EstadoVehiculo.enPreparacion,
    'reservado' => EstadoVehiculo.reservado,
    'vendido' => EstadoVehiculo.vendido,
    'dado_de_baja' => EstadoVehiculo.dadoDeBaja,
    _ => EstadoVehiculo.enStock,
  };

  static SemaforoCrediticio _aSemaforo(String? s) => switch (s) {
    'verde' => SemaforoCrediticio.verde,
    'amarillo' => SemaforoCrediticio.amarillo,
    'rojo' => SemaforoCrediticio.rojo,
    _ => SemaforoCrediticio.sinDatos,
  };

  static VehiculoInventario _aVehiculo(Map<String, dynamic> f) {
    return VehiculoInventario(
      id: f['id'] as String,
      codigo: f['codigo'] as String,
      marca: f['marca'] as String,
      modelo: f['modelo'] as String,
      anio: _entero(f['anio']) ?? 0,
      version: f['version'] as String?,
      km: _entero(f['km']),
      estado: _aEstado(f['estado'] as String?),
      alerta: AlertaRotacion.desde(f['alerta'] as String? ?? 'normal'),
      fechaIngreso: _fecha(f['fecha_ingreso']) ?? DateTime.now(),
      fechaCompra: _fecha(f['fecha_compra']),
      patente: f['patente'] as String?,
      precioCompra: _decimal(f['precio_compra']) ?? 0,
      precioObjetivo: _decimal(f['precio_objetivo']) ?? 0,
      gastosAcum: _decimal(f['gastos_acum']) ?? 0,
      cantidadGastos: _entero(f['cantidad_gastos']) ?? 0,
      costoTotal: _decimal(f['costo_total']) ?? 0,
      diasEnStock: _entero(f['dias_en_stock']) ?? 0,
      precioActual: _decimal(f['precio_actual']) ?? 0,
      capitalInmovilizado: _decimal(f['capital_inmovilizado']) ?? 0,
      gananciaEstimada: _decimal(f['ganancia_estimada']) ?? 0,
      margenActual: _decimal(f['margen_actual']) ?? 0,
      margenEsperado: _decimal(f['margen_esperado']) ?? 0,
      margenReal: _decimal(f['margen_real']),
      precioParaMargenObjetivo: _decimal(f['precio_para_margen_objetivo']) ?? 0,
      precioSugerido: _decimal(f['precio_sugerido']) ?? 0,
      costoTotalHoy: _decimal(f['costo_total_hoy']) ?? 0,
      gananciaRealIpc: _decimal(f['ganancia_real_ipc']) ?? 0,
      gananciaRealUsd: _decimal(f['ganancia_real_usd']) ?? 0,
      fechaVenta: _fecha(f['fecha_venta']),
      precioFinal: _decimal(f['precio_final']),
      observaciones: f['observaciones'] as String?,
      revistaArs: _decimal(f['revista_ars']),
    );
  }
}
