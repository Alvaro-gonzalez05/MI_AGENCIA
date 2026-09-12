import 'package:flutter/material.dart';

/// Las diez categorias del sistema original del cliente.
///
/// El orden no es alfabetico: esta puesto por frecuencia de uso real en una
/// agencia. Service y reparaciones son el pan de cada dia; comision y otros
/// aparecen poco y van al final.
enum CategoriaGasto {
  service('Service', 'service', Icons.build_outlined),
  reparaciones('Reparaciones', 'reparaciones', Icons.handyman_outlined),
  chapaYPintura(
    'Chapa y pintura',
    'chapa_y_pintura',
    Icons.format_paint_outlined,
  ),
  cubiertas('Cubiertas', 'cubiertas', Icons.trip_origin),
  lavadoDetallado(
    'Lavado / Detallado',
    'lavado_detallado',
    Icons.local_car_wash_outlined,
  ),
  transferencia('Transferencia', 'transferencia', Icons.swap_horiz),
  patentamiento('Patentamiento', 'patentamiento', Icons.badge_outlined),
  gestoria('Gestoría', 'gestoria', Icons.description_outlined),
  almacenamiento('Almacenamiento', 'almacenamiento', Icons.warehouse_outlined),
  comision('Comisión', 'comision', Icons.percent),
  otros('Otros', 'otros', Icons.more_horiz);

  const CategoriaGasto(this.etiqueta, this.valorBd, this.icono);

  final String etiqueta;

  /// El valor del enum `categoria_gasto` en Postgres.
  final String valorBd;

  final IconData icono;

  static CategoriaGasto desde(String? s) => CategoriaGasto.values.firstWhere(
    (c) => c.valorBd == s,
    orElse: () => CategoriaGasto.otros,
  );
}

/// Un gasto ya cargado.
class Gasto {
  const Gasto({
    required this.id,
    required this.vehiculoId,
    required this.fecha,
    required this.categoria,
    required this.importe,
    this.descripcion,
    this.proveedor,
    this.vehiculoCodigo,
    this.vehiculoTitulo,
  });

  final String id;
  final String vehiculoId;
  final DateTime fecha;
  final CategoriaGasto categoria;
  final double importe;
  final String? descripcion;
  final String? proveedor;

  /// Solo vienen cuando el gasto se lista fuera de la ficha de su vehiculo.
  final String? vehiculoCodigo;
  final String? vehiculoTitulo;
}

/// Lo que se carga al imputar un gasto a una unidad.
class AltaGasto {
  const AltaGasto({
    this.id,
    this.vehiculoId,
    this.fecha,
    this.categoria = CategoriaGasto.service,
    this.importe,
    this.descripcion = '',
    this.proveedor = '',
  });

  final String? id;
  final String? vehiculoId;
  final DateTime? fecha;
  final CategoriaGasto categoria;
  final double? importe;
  final String descripcion;
  final String proveedor;

  bool get esEdicion => id != null;

  AltaGasto copiar({
    String? vehiculoId,
    DateTime? fecha,
    CategoriaGasto? categoria,
    double? importe,
    String? descripcion,
    String? proveedor,
  }) => AltaGasto(
    id: id,
    vehiculoId: vehiculoId ?? this.vehiculoId,
    fecha: fecha ?? this.fecha,
    categoria: categoria ?? this.categoria,
    importe: importe ?? this.importe,
    descripcion: descripcion ?? this.descripcion,
    proveedor: proveedor ?? this.proveedor,
  );

  /// Errores por campo. Vacio = se puede guardar.
  ///
  /// `fechaIngreso` es la de la unidad: un gasto anterior a que el auto
  /// entrara al predio casi siempre es un error de tipeo, y si no lo es,
  /// igual no corresponde imputarlo a esta unidad.
  Map<String, String> validar({DateTime? fechaIngreso}) {
    final e = <String, String>{};
    final hoy = DateTime.now();

    if (vehiculoId == null || vehiculoId!.isEmpty) {
      e['vehiculo'] = 'Elegí a qué unidad se le imputa.';
    }

    if (fecha == null) {
      e['fecha'] = 'Poné la fecha del gasto.';
    } else if (fecha!.isAfter(hoy)) {
      e['fecha'] = 'La fecha no puede ser futura.';
    } else if (fechaIngreso != null &&
        fecha!.isBefore(_soloDia(fechaIngreso))) {
      e['fecha'] = 'Es anterior al ingreso de la unidad al predio.';
    }

    if (importe == null) {
      e['importe'] = 'Poné el importe.';
    } else if (importe! <= 0) {
      e['importe'] = 'Tiene que ser mayor a cero.';
    }

    return e;
  }

  static DateTime _soloDia(DateTime f) => DateTime(f.year, f.month, f.day);
}

/// Cuanto mueve la aguja este gasto en la unidad.
///
/// Se calcula ANTES de guardar, mientras se escribe el importe. Un service de
/// $400.000 sobre un auto con poco margen puede dejarlo en rojo, y eso hay que
/// verlo en el momento de cargarlo, no al fin de mes.
class ImpactoGasto {
  const ImpactoGasto({
    required this.costoAntes,
    required this.costoDespues,
    required this.margenAntes,
    required this.margenDespues,
    required this.precioActual,
  });

  final double costoAntes;
  final double costoDespues;
  final double margenAntes;
  final double margenDespues;
  final double precioActual;

  double get caidaDeMargen => margenAntes - margenDespues;

  /// Calculado sobre el precio publicado, que es contra lo que se mide el
  /// margen: (precio - costo) / precio.
  static ImpactoGasto calcular({
    required double costoTotal,
    required double precioActual,
    required double importe,
  }) {
    final despues = costoTotal + importe;
    return ImpactoGasto(
      costoAntes: costoTotal,
      costoDespues: despues,
      margenAntes: precioActual > 0
          ? (precioActual - costoTotal) / precioActual
          : 0,
      margenDespues: precioActual > 0
          ? (precioActual - despues) / precioActual
          : 0,
      precioActual: precioActual,
    );
  }
}
