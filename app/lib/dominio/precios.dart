/// Un cambio de precio ya registrado.
class CambioPrecio {
  const CambioPrecio({
    required this.id,
    required this.vehiculoId,
    required this.fecha,
    required this.precioNuevo,
    this.precioAnterior,
    this.motivo,
    this.vehiculoCodigo,
    this.vehiculoTitulo,
  });

  final String id;
  final String vehiculoId;
  final DateTime fecha;
  final double precioNuevo;

  /// Lo completa un trigger de la base al insertar: el usuario solo escribe
  /// el precio nuevo y el sistema recuerda de donde venia.
  final double? precioAnterior;

  final String? motivo;
  final String? vehiculoCodigo;
  final String? vehiculoTitulo;

  /// Variacion contra el precio anterior. null en el primer registro.
  double? get variacion {
    final a = precioAnterior;
    if (a == null || a <= 0) return null;
    return precioNuevo / a - 1;
  }

  bool get esBaja => (variacion ?? 0) < 0;
}

/// Lo que se carga al cambiar el precio publicado de una unidad.
class AltaPrecio {
  const AltaPrecio({
    this.vehiculoId,
    this.fecha,
    this.precioNuevo,
    this.motivo = '',
  });

  final String? vehiculoId;
  final DateTime? fecha;
  final double? precioNuevo;
  final String motivo;

  AltaPrecio copiar({
    String? vehiculoId,
    DateTime? fecha,
    double? precioNuevo,
    String? motivo,
  }) => AltaPrecio(
    vehiculoId: vehiculoId ?? this.vehiculoId,
    fecha: fecha ?? this.fecha,
    precioNuevo: precioNuevo ?? this.precioNuevo,
    motivo: motivo ?? this.motivo,
  );

  Map<String, String> validar({DateTime? fechaIngreso, double? precioActual}) {
    final e = <String, String>{};
    final hoy = DateTime.now();

    if (vehiculoId == null || vehiculoId!.isEmpty) {
      e['vehiculo'] = 'Elegí a qué unidad le cambiás el precio.';
    }

    if (fecha == null) {
      e['fecha'] = 'Poné la fecha del cambio.';
    } else if (fecha!.isAfter(hoy)) {
      e['fecha'] = 'La fecha no puede ser futura.';
    } else if (fechaIngreso != null &&
        fecha!.isBefore(
          DateTime(fechaIngreso.year, fechaIngreso.month, fechaIngreso.day),
        )) {
      e['fecha'] = 'Es anterior al ingreso de la unidad al predio.';
    }

    if (precioNuevo == null) {
      e['precio'] = 'Poné el precio nuevo.';
    } else if (precioNuevo! <= 0) {
      e['precio'] = 'Tiene que ser mayor a cero.';
    } else if (precioActual != null && precioNuevo == precioActual) {
      // Guardar un cambio que no cambia nada ensucia el historial y falsea
      // la lectura de "cuantas veces hubo que bajarle el precio".
      e['precio'] = 'Es el mismo precio que ya tiene publicado.';
    }

    return e;
  }
}

/// Que deja este precio, una vez descontado todo lo invertido en la unidad.
class ImpactoPrecio {
  const ImpactoPrecio({
    required this.costoTotal,
    required this.precioAnterior,
    required this.precioNuevo,
    required this.margenAnterior,
    required this.margenNuevo,
    required this.gananciaNueva,
  });

  final double costoTotal;
  final double precioAnterior;
  final double precioNuevo;
  final double margenAnterior;
  final double margenNuevo;
  final double gananciaNueva;

  double get variacion =>
      precioAnterior > 0 ? precioNuevo / precioAnterior - 1 : 0;

  bool get quedaEnPerdida => gananciaNueva < 0;

  static ImpactoPrecio calcular({
    required double costoTotal,
    required double precioActual,
    required double precioNuevo,
  }) => ImpactoPrecio(
    costoTotal: costoTotal,
    precioAnterior: precioActual,
    precioNuevo: precioNuevo,
    margenAnterior: precioActual > 0
        ? (precioActual - costoTotal) / precioActual
        : 0,
    margenNuevo: precioNuevo > 0 ? (precioNuevo - costoTotal) / precioNuevo : 0,
    gananciaNueva: precioNuevo - costoTotal,
  );
}
