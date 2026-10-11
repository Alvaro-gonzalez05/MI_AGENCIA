/// Un plan de pagos: la agencia financió y cobra en cuotas.
///
/// Es la parte del negocio que más duele cuando se lleva en un cuaderno: el
/// auto ya salió del salón y la plata entra de a poco durante un año. El
/// cuaderno no avisa quién se atrasó; esto sí.
class PlanPago {
  const PlanPago({
    required this.id,
    required this.clienteNombre,
    required this.montoFinanciado,
    required this.cantidadCuotas,
    this.clienteTelefono,
    this.oportunidadId,
    this.vehiculoId,
    this.sistema = 'frances',
    this.tna = 0,
    this.estado = EstadoPlan.activo,
    this.notas = '',
    this.cuotasPagas = 0,
    this.cuotasVencidas = 0,
    this.totalPlan = 0,
    this.totalPagado = 0,
    this.deuda = 0,
    this.deudaVencida = 0,
    this.peorAtraso = 0,
    this.proximoVencimiento,
  });

  final String id;
  final String clienteNombre;
  final String? clienteTelefono;
  final String? oportunidadId;
  final String? vehiculoId;

  final double montoFinanciado;
  final int cantidadCuotas;
  final String sistema;
  final double tna;
  final EstadoPlan estado;
  final String notas;

  /// Lo que calcula la base: así la app no suma cuotas a mano en cada
  /// pantalla, y el número es el mismo en todas.
  final int cuotasPagas;
  final int cuotasVencidas;
  final double totalPlan;
  final double totalPagado;
  final double deuda;
  final double deudaVencida;
  final int peorAtraso;
  final DateTime? proximoVencimiento;

  bool get alDia => cuotasVencidas == 0;
  bool get terminado => estado == EstadoPlan.terminado || deuda <= 0.01;

  /// Cuánto del plan ya entró, de 0 a 1.
  double get avance =>
      totalPlan <= 0 ? 0 : (totalPagado / totalPlan).clamp(0, 1);
}

enum EstadoPlan {
  activo('Activo', 'activo'),
  terminado('Terminado', 'terminado'),
  cancelado('Cancelado', 'cancelado');

  const EstadoPlan(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoPlan desde(String? v) =>
      EstadoPlan.values.where((e) => e.valorBd == v).firstOrNull ??
      EstadoPlan.activo;
}

/// Una cuota del plan, con lo que ya se pagó de ella.
class CuotaPlan {
  const CuotaPlan({
    required this.id,
    required this.planId,
    required this.numero,
    required this.venceEl,
    required this.importe,
    this.pagado = 0,
    this.ultimoPago,
    this.clienteNombre = '',
    this.clienteTelefono,
  });

  final String id;
  final String planId;
  final int numero;
  final DateTime venceEl;
  final double importe;
  final double pagado;
  final DateTime? ultimoPago;

  final String clienteNombre;
  final String? clienteTelefono;

  double get saldo => (importe - pagado).clamp(0, importe);
  bool get saldada => saldo <= 0.01;
  bool get parcial => pagado > 0 && !saldada;

  int get diasDeAtraso {
    if (saldada) return 0;
    final hoy = DateTime.now();
    final dias = DateTime(
      hoy.year,
      hoy.month,
      hoy.day,
    ).difference(DateTime(venceEl.year, venceEl.month, venceEl.day)).inDays;
    return dias > 0 ? dias : 0;
  }

  bool get vencida => diasDeAtraso > 0;

  /// "Vence el 05/11", "12 días de atraso", "Pagada".
  String get cuando {
    if (saldada) return 'Pagada';
    if (diasDeAtraso == 1) return '1 día de atraso';
    if (diasDeAtraso > 1) return '$diasDeAtraso días de atraso';
    return 'Al día';
  }
}

/// Un pago imputado a una cuota.
class Pago {
  const Pago({
    required this.id,
    required this.cuotaId,
    required this.fecha,
    required this.importe,
    this.medio = MedioPago.efectivo,
    this.notas = '',
  });

  final String id;
  final String cuotaId;
  final DateTime fecha;
  final double importe;
  final MedioPago medio;
  final String notas;
}

enum MedioPago {
  efectivo('Efectivo', 'efectivo'),
  transferencia('Transferencia', 'transferencia'),
  debito('Débito', 'debito'),
  credito('Crédito', 'credito'),
  cheque('Cheque', 'cheque'),
  otro('Otro', 'otro');

  const MedioPago(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static MedioPago desde(String? v) =>
      MedioPago.values.where((m) => m.valorBd == v).firstOrNull ??
      MedioPago.efectivo;
}

/// Lo que se carga al armar un plan.
class AltaPlan {
  const AltaPlan({
    required this.clienteNombre,
    required this.montoFinanciado,
    required this.cantidadCuotas,
    this.clienteTelefono,
    this.oportunidadId,
    this.vehiculoId,
    this.ventaId,
    this.sistema = 'frances',
    this.tna = 0,
    this.notas = '',
  });

  final String clienteNombre;
  final String? clienteTelefono;
  final String? oportunidadId;
  final String? vehiculoId;
  final String? ventaId;
  final double montoFinanciado;
  final int cantidadCuotas;
  final String sistema;
  final double tna;
  final String notas;

  AltaPlan copiar({
    String? clienteNombre,
    String? clienteTelefono,
    String? oportunidadId,
    String? vehiculoId,
    double? montoFinanciado,
    int? cantidadCuotas,
    String? sistema,
    double? tna,
    String? notas,
  }) => AltaPlan(
    clienteNombre: clienteNombre ?? this.clienteNombre,
    clienteTelefono: clienteTelefono ?? this.clienteTelefono,
    oportunidadId: oportunidadId ?? this.oportunidadId,
    vehiculoId: vehiculoId ?? this.vehiculoId,
    ventaId: ventaId,
    montoFinanciado: montoFinanciado ?? this.montoFinanciado,
    cantidadCuotas: cantidadCuotas ?? this.cantidadCuotas,
    sistema: sistema ?? this.sistema,
    tna: tna ?? this.tna,
    notas: notas ?? this.notas,
  );

  Map<String, String> validar() {
    final e = <String, String>{};
    if (clienteNombre.trim().isEmpty) e['cliente'] = 'Poné a nombre de quién.';
    if (montoFinanciado <= 0) e['monto'] = 'Poné cuánto se financia.';
    if (cantidadCuotas < 1 || cantidadCuotas > 120) {
      e['cuotas'] = 'Entre 1 y 120 cuotas.';
    }
    if (tna < 0) e['tna'] = 'La tasa no puede ser negativa.';
    return e;
  }
}

/// Lo que se carga al asentar un pago.
class AltaPago {
  const AltaPago({
    required this.cuotaId,
    required this.importe,
    required this.fecha,
    this.medio = MedioPago.efectivo,
    this.notas = '',
  });

  final String cuotaId;
  final double importe;
  final DateTime fecha;
  final MedioPago medio;
  final String notas;

  Map<String, String> validar({double? saldoCuota}) {
    final e = <String, String>{};
    if (importe <= 0) e['importe'] = 'Poné cuánto entró.';
    // Se permite pagar de más (redondeos, intereses de mora acordados),
    // pero se avisa: suele ser un cero de más al tipear.
    if (saldoCuota != null && importe > saldoCuota * 1.5) {
      e['importe'] = 'Es bastante más que el saldo de la cuota. ¿Está bien?';
    }
    return e;
  }
}
