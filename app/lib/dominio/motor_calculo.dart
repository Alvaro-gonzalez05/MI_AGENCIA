import 'dart:math' as math;

import '../datos/datos_demo.dart';
import 'modelos.dart';

/// Motor de calculo en Dart.
///
/// **Ojo con el alcance.** La fuente de verdad de estas formulas es la vista
/// `v_inventario` en Postgres (ver docs/MOTOR_DE_CALCULO.md), verificada
/// contra el JavaScript original del cliente. Esta version en Dart existe
/// para dos cosas y nada mas:
///
///   1. El modo demo, donde no hay base a la cual consultarle.
///   2. Los simuladores interactivos (precio segun margen deseado, cuotas),
///      que recalculan a cada tecla y no tiene sentido que viajen al servidor.
///
/// Cuando Supabase este conectado, las pantallas leen `v_inventario` y NO
/// pasan por aca. Si se cambia una formula, se cambia en el SQL primero.
abstract final class Motor {
  /// Indice IPC acumulado por mes, base 100 en el primer mes de la serie.
  static Map<String, double> _indices() {
    final mapa = <String, double>{};
    var acc = 100.0;
    for (var i = 0; i < DatosDemo.ipc.length; i++) {
      final fila = DatosDemo.ipc[i];
      if (i > 0) acc *= 1 + (fila.variacion ?? 0);
      mapa[_clave(fila.mes)] = acc;
    }
    return mapa;
  }

  static String _clave(DateTime f) =>
      '${f.year}-${f.month.toString().padLeft(2, '0')}';

  /// Indice vigente para una fecha.
  ///
  /// Si la fecha cae fuera de la serie devuelve el extremo mas cercano, sin
  /// extrapolar. El original devolvia el indice de HOY para fechas anteriores
  /// al inicio de la serie, lo que anulaba el ajuste por inflacion justo en
  /// las unidades mas viejas; aca se corrige igual que en el SQL.
  static double _indiceEn(DateTime fecha, Map<String, double> indices) {
    final directo = indices[_clave(fecha)];
    if (directo != null) return directo;

    final claves = indices.keys.toList()..sort();
    if (claves.isEmpty) return 100;
    final clave = _clave(fecha);
    if (clave.compareTo(claves.first) < 0) return indices[claves.first]!;
    return indices[claves.last]!;
  }

  static double _indiceHoy(Map<String, double> indices) =>
      _indiceEn(DateTime.now(), indices);

  /// Reconstruye el inventario completo con todo calculado.
  static List<VehiculoInventario> inventario({ConfigAgencia cfg = const ConfigAgencia()}) {
    final indices = _indices();
    final idxHoy = _indiceHoy(indices);
    final hoy = DateTime.now();

    return DatosDemo.vehiculos.map((v) {
      final venta = DatosDemo.ventas.where((x) => x.codigo == v.codigo).firstOrNull;
      final gastos = DatosDemo.gastos.where((g) => g.codigo == v.codigo).toList();

      final gastosNominal = gastos.fold<double>(0, (s, g) => s + g.importe);
      final gastosFinales = venta?.gastosFinales ?? 0;
      final gastosAcum = gastosNominal + gastosFinales;
      final costoTotal = v.precioCompra + gastosAcum;

      final fechaFin = venta?.fecha ?? hoy;
      final diasEnStock = fechaFin.difference(v.fechaIngreso).inDays;

      // Ultimo cambio de precio; si no hubo, rige el precio objetivo de alta.
      final historial = DatosDemo.precios.where((p) => p.codigo == v.codigo).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      final precioActual =
          historial.isNotEmpty ? historial.last.precio : v.precioObjetivo;

      final vendido = venta != null;
      final estado = vendido ? EstadoVehiculo.vendido : v.estado;

      // Costo llevado a moneda de hoy: la compra con el IPC de su mes, y cada
      // gasto con el IPC del mes en que se hizo.
      final gastosAjustados = gastos.fold<double>(
        0,
        (s, g) => s + g.importe * idxHoy / _indiceEn(g.fecha, indices),
      );
      final costoTotalHoy =
          v.precioCompra * idxHoy / _indiceEn(v.fechaIngreso, indices) +
              gastosAjustados +
              gastosFinales;

      final margenActual =
          precioActual > 0 ? (precioActual - costoTotal) / precioActual : 0.0;
      final margenEsperado = v.precioObjetivo > 0
          ? (v.precioObjetivo - costoTotal) / v.precioObjetivo
          : 0.0;
      final margenReal = venta != null && venta.precioFinal > 0
          ? (venta.precioFinal - costoTotal) / venta.precioFinal
          : null;

      final precioObjetivoMargen = costoTotal / (1 - cfg.margenObjetivo);
      final gananciaRealIpc = precioActual - costoTotalHoy;

      final AlertaRotacion alerta;
      if (vendido) {
        alerta = AlertaRotacion.vendido;
      } else if (diasEnStock >= cfg.diasRojo) {
        alerta = AlertaRotacion.critico;
      } else if (diasEnStock >= cfg.diasAmarillo) {
        alerta = AlertaRotacion.atencion;
      } else if (diasEnStock >= cfg.diasVerde) {
        alerta = AlertaRotacion.observar;
      } else {
        alerta = AlertaRotacion.normal;
      }

      return VehiculoInventario(
        id: v.codigo,
        codigo: v.codigo,
        marca: v.marca,
        modelo: v.modelo,
        anio: v.anio,
        version: v.version,
        km: v.km,
        estado: estado,
        alerta: alerta,
        fechaIngreso: v.fechaIngreso,
        precioCompra: v.precioCompra,
        gastosAcum: gastosAcum,
        cantidadGastos: gastos.length,
        costoTotal: costoTotal,
        diasEnStock: diasEnStock,
        precioActual: precioActual,
        capitalInmovilizado: vendido ? 0 : costoTotal,
        gananciaEstimada: precioActual - costoTotal,
        margenActual: margenActual,
        margenEsperado: margenEsperado,
        margenReal: margenReal,
        precioParaMargenObjetivo: precioObjetivoMargen,
        precioSugerido: redondearArriba(precioObjetivoMargen, cfg.redondeo),
        costoTotalHoy: costoTotalHoy,
        gananciaRealIpc: gananciaRealIpc,
        gananciaRealUsd: gananciaRealIpc / cfg.tipoCambio,
        fechaVenta: venta?.fecha,
        precioFinal: venta?.precioFinal,
        observaciones: v.observaciones,
      );
    }).toList();
  }

  static ResumenAgencia resumen(List<VehiculoInventario> inv) {
    final enStock = inv.where((v) => !v.vendido).toList();
    final vendidos = inv.where((v) => v.vendido).toList();

    double prom(Iterable<double> xs) {
      final l = xs.toList();
      return l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;
    }

    return ResumenAgencia(
      unidadesEnStock: enStock.length,
      unidadesVendidas: vendidos.length,
      capitalInmovilizado:
          enStock.fold<double>(0, (s, v) => s + v.capitalInmovilizado),
      gananciaPotencial:
          enStock.fold<double>(0, (s, v) => s + v.gananciaEstimada),
      gananciaRealizada: vendidos.fold<double>(
          0, (s, v) => s + ((v.precioFinal ?? 0) - v.costoTotal)),
      gananciaRealizadaIpc: vendidos.fold<double>(
          0, (s, v) => s + ((v.precioFinal ?? 0) - v.costoTotalHoy)),
      gananciaRealizadaUsd: vendidos.fold<double>(0, (s, v) => s + v.gananciaRealUsd),
      diasPromedioStock: prom(enStock.map((v) => v.diasEnStock.toDouble())),
      margenPromedio: prom(enStock.map((v) => v.margenActual)),
      criticos: inv.where((v) => v.alerta == AlertaRotacion.critico).length,
      enAtencion: inv.where((v) => v.alerta == AlertaRotacion.atencion).length,
      enObservacion: inv.where((v) => v.alerta == AlertaRotacion.observar).length,
      bajoMargenMinimo: enStock.where((v) => v.margenActual < 0.10).length,
    );
  }

  /// Redondeo hacia arriba al multiplo que use la agencia. Port de roundUp().
  static double redondearArriba(double n, double paso) =>
      paso <= 0 ? n : (n / paso).ceil() * paso;

  /// Precio necesario para alcanzar un margen dado, sobre precio de venta.
  ///
  /// El margen se mide sobre el PRECIO, no sobre el costo: por eso se divide
  /// por (1 - margen) y no se multiplica por (1 + margen). Confundirlos es el
  /// error clasico que infla la ganancia estimada.
  static double precioParaMargen(double costoTotal, double margen) =>
      margen >= 1 ? double.infinity : costoTotal / (1 - margen);

  /// Financiacion con interes directo sobre el capital total, que es como se
  /// vende en el rubro ("12 cuotas fijas de $X"), no amortizacion francesa.
  static ({double cuota, double total, double interes}) financiacion({
    required double monto,
    required int cuotas,
    required double tasaMensual,
  }) {
    if (monto <= 0 || cuotas <= 0) {
      return (cuota: 0, total: 0, interes: 0);
    }
    final interes = monto * tasaMensual * cuotas;
    final total = monto + interes;
    return (cuota: total / cuotas, total: total, interes: interes);
  }

  /// Capital inmovilizado y ganancia acumulada mes a mes, para los graficos.
  static List<({DateTime mes, double capital, double gananciaAcum})> evolucion() {
    final resultado = <({DateTime mes, double capital, double gananciaAcum})>[];
    for (final fila in DatosDemo.ipc) {
      final finMes = DateTime.utc(fila.mes.year, fila.mes.month + 1, 0);
      var capital = 0.0;
      var ganancia = 0.0;

      for (final v in DatosDemo.vehiculos) {
        if (v.fechaIngreso.isAfter(finMes)) continue;
        final venta = DatosDemo.ventas.where((x) => x.codigo == v.codigo).firstOrNull;
        final gastosHasta = DatosDemo.gastos
            .where((g) => g.codigo == v.codigo && !g.fecha.isAfter(finMes))
            .fold<double>(0, (s, g) => s + g.importe);

        if (venta != null && !venta.fecha.isAfter(finMes)) {
          final gastosTotales = DatosDemo.gastos
              .where((g) => g.codigo == v.codigo)
              .fold<double>(0, (s, g) => s + g.importe);
          ganancia += venta.precioFinal -
              (v.precioCompra + gastosTotales + venta.gastosFinales);
        } else {
          capital += v.precioCompra + gastosHasta;
        }
      }
      resultado.add((mes: fila.mes, capital: capital, gananciaAcum: ganancia));
    }
    return resultado;
  }

  /// Maximo de una lista, con piso en 1 para no dividir por cero al escalar
  /// graficos cuando todavia no hay datos.
  static double maximo(Iterable<double> xs) =>
      xs.isEmpty ? 1 : math.max(1, xs.reduce(math.max));
}
