import 'modelos.dart';

/// Los datos que se cargan al dar de alta o editar un vehiculo.
///
/// Existe separado de [VehiculoInventario] a proposito: aquel tiene 25 campos
/// que la base CALCULA (costo total, margenes, dias en stock, ganancia real).
/// Mezclar lo que se escribe con lo que se deriva es como se terminan
/// guardando totales desactualizados en la tabla.
class AltaVehiculo {
  const AltaVehiculo({
    this.id,
    this.codigo,
    this.marca = '',
    this.modelo = '',
    this.anio,
    this.version = '',
    this.km,
    this.patente = '',
    this.fechaCompra,
    this.fechaIngreso,
    this.precioCompra,
    this.precioObjetivo,
    this.estado = EstadoVehiculo.enStock,
    this.observaciones = '',
  });

  /// null en un alta; con valor al editar.
  final String? id;
  final String? codigo;

  final String marca;
  final String modelo;
  final int? anio;
  final String version;
  final int? km;
  final String patente;
  final DateTime? fechaCompra;
  final DateTime? fechaIngreso;
  final double? precioCompra;
  final double? precioObjetivo;
  final EstadoVehiculo estado;
  final String observaciones;

  bool get esEdicion => id != null;

  AltaVehiculo copiar({
    String? marca,
    String? modelo,
    int? anio,
    String? version,
    int? km,
    String? patente,
    DateTime? fechaCompra,
    DateTime? fechaIngreso,
    double? precioCompra,
    double? precioObjetivo,
    EstadoVehiculo? estado,
    String? observaciones,
  }) => AltaVehiculo(
    id: id,
    codigo: codigo,
    marca: marca ?? this.marca,
    modelo: modelo ?? this.modelo,
    anio: anio ?? this.anio,
    version: version ?? this.version,
    km: km ?? this.km,
    patente: patente ?? this.patente,
    fechaCompra: fechaCompra ?? this.fechaCompra,
    fechaIngreso: fechaIngreso ?? this.fechaIngreso,
    precioCompra: precioCompra ?? this.precioCompra,
    precioObjetivo: precioObjetivo ?? this.precioObjetivo,
    estado: estado ?? this.estado,
    observaciones: observaciones ?? this.observaciones,
  );

  /// Margen que dejaria la unidad si se vendiera al precio objetivo, ANTES de
  /// cualquier gasto. Sirve para avisar en el momento de la carga, cuando
  /// todavia se puede negociar el precio de compra.
  ///
  /// Se mide sobre el precio de venta, no sobre el costo: (venta - costo) / venta.
  double? get margenInicial {
    final c = precioCompra, o = precioObjetivo;
    if (c == null || o == null || o <= 0) return null;
    return (o - c) / o;
  }

  /// Errores de validacion, por campo. Vacio = se puede guardar.
  ///
  /// Replica las restricciones que ya tiene la base (fechas coherentes,
  /// precios no negativos) para avisar ANTES de viajar al servidor. La base
  /// sigue siendo la que manda: esto es cortesia, no seguridad.
  Map<String, String> validar() {
    final e = <String, String>{};
    final hoy = DateTime.now();

    if (marca.trim().isEmpty) e['marca'] = 'Poné la marca.';
    if (modelo.trim().isEmpty) e['modelo'] = 'Poné el modelo.';

    if (anio == null) {
      e['anio'] = 'Poné el año.';
    } else if (anio! < 1950 || anio! > hoy.year + 1) {
      e['anio'] = 'El año tiene que estar entre 1950 y ${hoy.year + 1}.';
    }

    if (km != null && km! < 0) {
      e['km'] = 'El kilometraje no puede ser negativo.';
    }

    if (fechaCompra == null) {
      e['fechaCompra'] = 'Poné la fecha de compra.';
    } else if (fechaCompra!.isAfter(hoy)) {
      e['fechaCompra'] = 'La fecha de compra no puede ser futura.';
    }

    if (fechaIngreso == null) {
      e['fechaIngreso'] = 'Poné la fecha de ingreso.';
    } else if (fechaIngreso!.isAfter(hoy)) {
      e['fechaIngreso'] = 'La fecha de ingreso no puede ser futura.';
    } else if (fechaCompra != null && fechaIngreso!.isBefore(fechaCompra!)) {
      // Misma regla que el check de la base: no se puede ingresar al predio
      // una unidad antes de haberla comprado.
      e['fechaIngreso'] = 'No puede ser anterior a la compra.';
    }

    if (precioCompra == null) {
      e['precioCompra'] = 'Poné el precio de compra.';
    } else if (precioCompra! <= 0) {
      e['precioCompra'] = 'Tiene que ser mayor a cero.';
    }

    if (precioObjetivo == null) {
      e['precioObjetivo'] = 'Poné el precio de venta al que apuntás.';
    } else if (precioObjetivo! <= 0) {
      e['precioObjetivo'] = 'Tiene que ser mayor a cero.';
    } else if (precioCompra != null && precioObjetivo! <= precioCompra!) {
      e['precioObjetivo'] = 'Tiene que ser mayor al precio de compra.';
    }

    return e;
  }
}
