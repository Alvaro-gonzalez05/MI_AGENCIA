/// Una venta cerrada.
class Venta {
  const Venta({
    required this.id,
    required this.vehiculoId,
    required this.fechaVenta,
    required this.precioFinal,
    required this.gastosFinales,
    this.formaPago,
    this.cuotas,
    this.observaciones,
    this.vehiculoCodigo,
    this.vehiculoTitulo,
    this.costoTotal,
    this.costoTotalHoy,
    this.diasEnStock,
    this.tipoCambio,
  });

  final String id;
  final String vehiculoId;
  final DateTime fechaVenta;
  final double precioFinal;

  /// Gastos de cierre: comisiones, gestoria de la transferencia, lo que
  /// aparece recien al firmar.
  final double gastosFinales;

  final String? formaPago;
  final int? cuotas;
  final String? observaciones;
  final String? vehiculoCodigo;
  final String? vehiculoTitulo;

  /// Vienen del motor de calculo. Sin ellos la venta es solo un numero.
  final double? costoTotal;
  final double? costoTotalHoy;
  final int? diasEnStock;
  final double? tipoCambio;

  double? get ganancia => costoTotal == null ? null : precioFinal - costoTotal!;

  double? get margenReal => costoTotal == null || precioFinal <= 0
      ? null
      : (precioFinal - costoTotal!) / precioFinal;

  /// Lo que quedo de verdad, descontada la inflacion del periodo.
  double? get gananciaReal =>
      costoTotalHoy == null ? null : precioFinal - costoTotalHoy!;

  double? get gananciaRealUsd {
    final g = gananciaReal, tc = tipoCambio;
    if (g == null || tc == null || tc <= 0) return null;
    return g / tc;
  }
}

/// Formas de pago habituales en una agencia.
enum FormaPago {
  contado('Contado'),
  financiacionPropia('Financiación propia'),
  prendario('Crédito prendario'),
  parteDePago('Parte de pago'),
  mixto('Mixto'),
  otra('Otra');

  const FormaPago(this.etiqueta);
  final String etiqueta;

  static FormaPago desde(String? s) => FormaPago.values.firstWhere(
    (f) => f.etiqueta == s,
    orElse: () => FormaPago.contado,
  );
}

/// Lo que se carga al cerrar una venta.
class AltaVenta {
  const AltaVenta({
    this.vehiculoId,
    this.fechaVenta,
    this.precioFinal,
    this.gastosFinales = 0,
    this.formaPago = FormaPago.contado,
    this.cuotas,
    this.observaciones = '',
  });

  final String? vehiculoId;
  final DateTime? fechaVenta;
  final double? precioFinal;
  final double gastosFinales;
  final FormaPago formaPago;
  final int? cuotas;
  final String observaciones;

  bool get pideCuotas =>
      formaPago == FormaPago.financiacionPropia ||
      formaPago == FormaPago.prendario;

  AltaVenta copiar({
    String? vehiculoId,
    DateTime? fechaVenta,
    double? precioFinal,
    double? gastosFinales,
    FormaPago? formaPago,
    int? cuotas,
    String? observaciones,
  }) => AltaVenta(
    vehiculoId: vehiculoId ?? this.vehiculoId,
    fechaVenta: fechaVenta ?? this.fechaVenta,
    precioFinal: precioFinal ?? this.precioFinal,
    gastosFinales: gastosFinales ?? this.gastosFinales,
    formaPago: formaPago ?? this.formaPago,
    cuotas: cuotas ?? this.cuotas,
    observaciones: observaciones ?? this.observaciones,
  );

  Map<String, String> validar({DateTime? fechaIngreso}) {
    final e = <String, String>{};
    final hoy = DateTime.now();

    if (vehiculoId == null || vehiculoId!.isEmpty) {
      e['vehiculo'] = 'Elegí qué unidad se vendió.';
    }

    if (fechaVenta == null) {
      e['fecha'] = 'Poné la fecha de la venta.';
    } else if (fechaVenta!.isAfter(hoy)) {
      e['fecha'] = 'La fecha no puede ser futura.';
    } else if (fechaIngreso != null &&
        fechaVenta!.isBefore(
          DateTime(fechaIngreso.year, fechaIngreso.month, fechaIngreso.day),
        )) {
      e['fecha'] = 'No se puede vender antes de que la unidad ingresara.';
    }

    if (precioFinal == null) {
      e['precioFinal'] = 'Poné a cuánto se cerró.';
    } else if (precioFinal! <= 0) {
      e['precioFinal'] = 'Tiene que ser mayor a cero.';
    }

    if (gastosFinales < 0) {
      e['gastosFinales'] = 'No puede ser negativo.';
    }

    if (pideCuotas && (cuotas == null || cuotas! < 1)) {
      e['cuotas'] = 'Poné en cuántas cuotas.';
    }

    return e;
  }
}

/// El resultado real de la operacion, que es lo unico que importa al cerrarla.
class ResultadoVenta {
  const ResultadoVenta({
    required this.costoTotal,
    required this.costoTotalHoy,
    required this.precioFinal,
    required this.gastosFinales,
    required this.tipoCambio,
  });

  final double costoTotal;

  /// Costo llevado a moneda de hoy con el IPC del INDEC.
  final double costoTotalHoy;

  final double precioFinal;
  final double gastosFinales;
  final double tipoCambio;

  double get costoConCierre => costoTotal + gastosFinales;
  double get costoConCierreHoy => costoTotalHoy + gastosFinales;

  double get ganancia => precioFinal - costoConCierre;

  double get margen =>
      precioFinal > 0 ? (precioFinal - costoConCierre) / precioFinal : 0;

  /// La cifra que suele sorprender: lo mismo, descontada la inflacion.
  double get gananciaReal => precioFinal - costoConCierreHoy;

  double get margenReal =>
      precioFinal > 0 ? (precioFinal - costoConCierreHoy) / precioFinal : 0;

  double get gananciaRealUsd => tipoCambio > 0 ? gananciaReal / tipoCambio : 0;

  /// Cuanto se llevo la inflacion de la ganancia nominal.
  double get erosion => ganancia - gananciaReal;

  bool get perdioPlata => ganancia < 0;
  bool get perdioContraInflacion => gananciaReal < 0 && ganancia >= 0;
}
