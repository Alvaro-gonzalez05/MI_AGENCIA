/// Los papeles de una unidad.
///
/// Un usado no se entrega si los papeles no están: sin título no se
/// transfiere, sin VTV vigente no se patenta en varias provincias, y una
/// deuda de patentes o una multa impaga la termina pagando la agencia si no
/// se detecta antes de comprar. Por eso son un bloque con estado propio y no
/// una nota suelta en observaciones.
class PapelesVehiculo {
  const PapelesVehiculo({
    required this.vehiculoId,
    this.titulo = false,
    this.cedula = false,
    this.informeDominio = false,
    this.vtv = false,
    this.vtvVence,
    this.patentesDeuda,
    this.multasCantidad = 0,
    this.multasMonto,
    this.notas = '',
    this.actualizadoEl,
  });

  final String vehiculoId;

  final bool titulo;
  final bool cedula;
  final bool informeDominio;

  final bool vtv;

  /// Hasta cuándo vale la verificación. Sin fecha, el tilde no dice nada.
  final DateTime? vtvVence;

  /// Cero es "no debe nada"; null es "todavía no lo miré".
  final double? patentesDeuda;
  final int multasCantidad;
  final double? multasMonto;

  final String notas;
  final DateTime? actualizadoEl;

  /// Cuántos de los seis puntos están resueltos. Es el "4 de 6" de la ficha.
  int get completos =>
      (titulo ? 1 : 0) +
      (cedula ? 1 : 0) +
      (informeDominio ? 1 : 0) +
      (vtv ? 1 : 0) +
      (patentesDeuda != null ? 1 : 0) +
      (multasMonto != null ? 1 : 0);

  static const total = 6;

  bool get completo => completos == total;

  /// Días que faltan para que venza la VTV. Negativo = ya venció.
  int? get diasParaVtv {
    final v = vtvVence;
    if (v == null) return null;
    final hoy = DateTime.now();
    return DateTime(
      v.year,
      v.month,
      v.day,
    ).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  bool get vtvVencida => (diasParaVtv ?? 1) < 0;

  /// Lo que hay que resolver antes de poder entregar la unidad.
  List<String> get pendientes => [
    if (!titulo) 'Falta el título',
    if (!cedula) 'Falta la cédula verde',
    if (!informeDominio) 'Falta el informe de dominio',
    if (!vtv) 'Falta la VTV',
    if (vtvVencida) 'La VTV está vencida',
    if ((patentesDeuda ?? 0) > 0) 'Hay deuda de patentes',
    if (multasCantidad > 0) 'Hay multas sin pagar',
  ];

  PapelesVehiculo copiar({
    bool? titulo,
    bool? cedula,
    bool? informeDominio,
    bool? vtv,
    DateTime? vtvVence,
    double? patentesDeuda,
    int? multasCantidad,
    double? multasMonto,
    String? notas,
    bool limpiarVtvVence = false,
    bool limpiarPatentes = false,
    bool limpiarMultas = false,
  }) => PapelesVehiculo(
    vehiculoId: vehiculoId,
    titulo: titulo ?? this.titulo,
    cedula: cedula ?? this.cedula,
    informeDominio: informeDominio ?? this.informeDominio,
    vtv: vtv ?? this.vtv,
    vtvVence: limpiarVtvVence ? null : (vtvVence ?? this.vtvVence),
    patentesDeuda: limpiarPatentes
        ? null
        : (patentesDeuda ?? this.patentesDeuda),
    multasCantidad: multasCantidad ?? this.multasCantidad,
    multasMonto: limpiarMultas ? null : (multasMonto ?? this.multasMonto),
    notas: notas ?? this.notas,
    actualizadoEl: actualizadoEl,
  );
}

/// Una foto de la unidad, ya subida.
class FotoVehiculo {
  const FotoVehiculo({
    required this.id,
    required this.vehiculoId,
    required this.ruta,
    required this.url,
    this.orden = 0,
    this.esPortada = false,
  });

  final String id;
  final String vehiculoId;

  /// La ruta dentro del bucket: `{agencia}/{vehiculo}/{archivo}`.
  final String ruta;

  /// URL firmada para mostrarla. Vence: se pide de nuevo al recargar.
  final String url;

  final int orden;
  final bool esPortada;
}
