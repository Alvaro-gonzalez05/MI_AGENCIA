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

/// La reserva de una unidad: alguien dejó una seña y el auto se guarda.
///
/// Tiene fecha de vencimiento porque una reserva sin plazo es una unidad
/// parada por tiempo indefinido, que es justo lo que hace perder plata.
class Reserva {
  const Reserva({
    required this.id,
    required this.vehiculoId,
    required this.clienteNombre,
    required this.senia,
    required this.fechaReserva,
    required this.venceEl,
    this.clienteTelefono,
    this.oportunidadId,
    this.estado = EstadoReserva.activa,
    this.notas = '',
    this.vehiculoTitulo,
    this.vehiculoPatente,
  });

  final String id;
  final String vehiculoId;
  final String clienteNombre;
  final String? clienteTelefono;
  final String? oportunidadId;
  final double senia;
  final DateTime fechaReserva;
  final DateTime venceEl;
  final EstadoReserva estado;
  final String notas;

  /// Para mostrarla fuera de la ficha (el Inicio la nombra).
  final String? vehiculoTitulo;
  final String? vehiculoPatente;

  /// Días que faltan. Negativo = ya venció.
  int get diasParaVencer {
    final hoy = DateTime.now();
    return DateTime(
      venceEl.year,
      venceEl.month,
      venceEl.day,
    ).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  bool get activa => estado == EstadoReserva.activa;
  bool get vencida => activa && diasParaVencer < 0;

  /// "Vence mañana", "Vence en 3 días", "Venció ayer".
  String get cuandoVence {
    final d = diasParaVencer;
    if (d == 0) return 'Vence hoy';
    if (d == 1) return 'Vence mañana';
    if (d == -1) return 'Venció ayer';
    if (d > 1) return 'Vence en $d días';
    return 'Venció hace ${-d} días';
  }
}

enum EstadoReserva {
  activa('Activa', 'activa'),
  cancelada('Cancelada', 'cancelada'),
  concretada('Se concretó', 'concretada'),
  vencida('Vencida', 'vencida');

  const EstadoReserva(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoReserva desde(String? v) =>
      EstadoReserva.values.where((e) => e.valorBd == v).firstOrNull ??
      EstadoReserva.activa;
}

/// Lo que se carga al reservar.
class AltaReserva {
  const AltaReserva({
    required this.vehiculoId,
    required this.clienteNombre,
    required this.venceEl,
    this.clienteTelefono,
    this.oportunidadId,
    this.senia = 0,
    this.notas = '',
  });

  final String vehiculoId;
  final String clienteNombre;
  final String? clienteTelefono;
  final String? oportunidadId;
  final double senia;
  final DateTime venceEl;
  final String notas;

  Map<String, String> validar() {
    final e = <String, String>{};
    if (clienteNombre.trim().isEmpty) e['cliente'] = 'Poné a nombre de quién.';
    final hoy = DateTime.now();
    if (venceEl.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) {
      e['vence'] = 'La reserva no puede vencer antes de hoy.';
    }
    if (senia < 0) e['senia'] = 'La seña no puede ser negativa.';
    return e;
  }
}

/// Cómo está el auto, a ojo de quien lo recibió.
enum EstadoGeneral {
  excelente('Excelente', 'excelente'),
  muyBueno('Muy bueno', 'muy_bueno'),
  bueno('Bueno', 'bueno'),
  regular('Regular', 'regular');

  const EstadoGeneral(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoGeneral? desde(String? v) => v == null
      ? null
      : EstadoGeneral.values.where((e) => e.valorBd == v).firstOrNull;
}

/// Un detalle concreto de la unidad: un rayón, una abolladura, el aire que
/// no enfría.
///
/// De esta lista salen dos cosas: antes de publicar, qué conviene arreglar;
/// y al entregar, qué se le avisó al comprador, que es lo que evita el
/// reclamo de la semana siguiente.
class DetalleVehiculo {
  const DetalleVehiculo({
    required this.id,
    required this.vehiculoId,
    required this.titulo,
    this.descripcion = '',
    this.categoria = CategoriaDetalle.otro,
    this.estado = EstadoDetalle.pendiente,
    this.costoEstimado,
    this.fotoUrl,
  });

  final String id;
  final String vehiculoId;
  final String titulo;
  final String descripcion;
  final CategoriaDetalle categoria;
  final EstadoDetalle estado;
  final double? costoEstimado;
  final String? fotoUrl;

  bool get pendiente => estado == EstadoDetalle.pendiente;
}

enum EstadoDetalle {
  pendiente('Pendiente de arreglar', 'pendiente'),
  arreglado('Arreglado', 'arreglado'),
  seVendeAsi('Se vende así', 'se_vende_asi');

  const EstadoDetalle(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoDetalle desde(String? v) =>
      EstadoDetalle.values.where((e) => e.valorBd == v).firstOrNull ??
      EstadoDetalle.pendiente;
}

enum CategoriaDetalle {
  estetica('Estética', 'estetica'),
  mecanica('Mecánica', 'mecanica'),
  tapizado('Tapizado', 'tapizado'),
  neumaticos('Neumáticos', 'neumaticos'),
  papeles('Papeles', 'papeles'),
  otro('Otro', 'otro');

  const CategoriaDetalle(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static CategoriaDetalle desde(String? v) =>
      CategoriaDetalle.values.where((c) => c.valorBd == v).firstOrNull ??
      CategoriaDetalle.otro;
}

/// Lo que se carga al anotar un detalle.
class AltaDetalle {
  const AltaDetalle({
    required this.vehiculoId,
    required this.titulo,
    this.id,
    this.descripcion = '',
    this.categoria = CategoriaDetalle.otro,
    this.estado = EstadoDetalle.pendiente,
    this.costoEstimado,
  });

  final String? id;
  final String vehiculoId;
  final String titulo;
  final String descripcion;
  final CategoriaDetalle categoria;
  final EstadoDetalle estado;
  final double? costoEstimado;

  bool get esEdicion => id != null;

  AltaDetalle copiar({
    String? titulo,
    String? descripcion,
    CategoriaDetalle? categoria,
    EstadoDetalle? estado,
    double? costoEstimado,
  }) => AltaDetalle(
    id: id,
    vehiculoId: vehiculoId,
    titulo: titulo ?? this.titulo,
    descripcion: descripcion ?? this.descripcion,
    categoria: categoria ?? this.categoria,
    estado: estado ?? this.estado,
    costoEstimado: costoEstimado ?? this.costoEstimado,
  );

  Map<String, String> validar() {
    final e = <String, String>{};
    if (titulo.trim().isEmpty) e['titulo'] = 'Poné qué es lo que tiene.';
    if ((costoEstimado ?? 0) < 0) {
      e['costo'] = 'El costo no puede ser negativo.';
    }
    return e;
  }
}
