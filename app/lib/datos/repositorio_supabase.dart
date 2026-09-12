import 'package:supabase_flutter/supabase_flutter.dart';

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
      precioCompra: _decimal(f['precio_compra']) ?? 0,
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
