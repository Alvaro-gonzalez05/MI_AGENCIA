import 'modelos.dart';

/// Qué informa una entidad financiera sobre una persona.
class EntidadBcra {
  const EntidadBcra({
    required this.entidad,
    required this.situacion,
    required this.montoMiles,
    this.diasAtraso = 0,
    this.refinanciaciones = false,
    this.situacionJuridica = false,
    this.enRevision = false,
    this.procesoJudicial = false,
  });

  final String entidad;
  final int situacion;

  /// El BCRA informa los montos en MILES de pesos. Multiplicar acá y no en la
  /// pantalla evita que alguien muestre mil veces menos deuda de la real.
  final double montoMiles;

  final int diasAtraso;
  final bool refinanciaciones;
  final bool situacionJuridica;
  final bool enRevision;
  final bool procesoJudicial;

  double get monto => montoMiles * 1000;

  /// Las seis situaciones del BCRA, en castellano de persona.
  String get descripcionSituacion => switch (situacion) {
    1 => 'Normal',
    2 => 'Riesgo bajo',
    3 => 'Riesgo medio',
    4 => 'Riesgo alto',
    5 => 'Irrecuperable',
    6 => 'Irrecuperable por disposición técnica',
    _ => 'Sin clasificar',
  };

  /// Lo que significa en la práctica para quien evalúa financiar.
  String get queSignifica => switch (situacion) {
    1 => 'Paga en término.',
    2 => 'Atrasos de hasta 90 días.',
    3 => 'Atrasos de hasta 180 días.',
    4 => 'Atrasos de más de 180 días, con baja probabilidad de cobro.',
    5 => 'Se da por incobrable.',
    6 => 'Deuda con una entidad liquidada.',
    _ => '',
  };

  factory EntidadBcra.desdeJson(Map<String, dynamic> j) => EntidadBcra(
    entidad: (j['entidad'] as String?)?.trim() ?? 'Sin identificar',
    situacion: (j['situacion'] as num?)?.toInt() ?? 1,
    montoMiles: (j['monto'] as num?)?.toDouble() ?? 0,
    diasAtraso: (j['diasAtrasoPago'] as num?)?.toInt() ?? 0,
    refinanciaciones: j['refinanciaciones'] == true,
    situacionJuridica: j['situacionJuridica'] == true,
    enRevision: j['enRevision'] == true,
    procesoJudicial: j['procesoJud'] == true,
  );
}

/// Un cheque rechazado.
///
/// El BCRA los devuelve anidados en tres niveles (causal → entidad →
/// detalle). Acá quedan aplanados, con la causal y la entidad repetidas en
/// cada uno: para mostrarlos en una lista y para contarlos, el anidamiento
/// solo estorba.
class ChequeBcra {
  const ChequeBcra({
    required this.numero,
    required this.monto,
    this.causal,
    this.entidad,
    this.fechaRechazo,
    this.fechaPago,
    this.procesoJudicial = false,
    this.enRevision = false,
  });

  final String numero;
  final double monto;
  final String? causal;
  final String? entidad;
  final DateTime? fechaRechazo;

  /// Sin fecha de pago el cheque sigue impago, que es lo que importa.
  final DateTime? fechaPago;

  final bool procesoJudicial;
  final bool enRevision;

  bool get pagado => fechaPago != null;

  /// Aplana la respuesta del BCRA (o la copia guardada en `cheques`).
  static List<ChequeBcra> desdeCausales(List<dynamic> causales) {
    final salida = <ChequeBcra>[];
    for (final c in causales.whereType<Map>()) {
      final causal = c['causal'] as String?;
      for (final e
          in ((c['entidades'] as List?) ?? const []).whereType<Map>()) {
        final entidad = e['entidad']?.toString();
        for (final d
            in ((e['detalle'] as List?) ?? const []).whereType<Map>()) {
          salida.add(
            ChequeBcra(
              numero: d['nroCheque']?.toString() ?? '',
              monto: ConsultaBcra._num(d['monto']),
              causal: causal,
              entidad: entidad,
              fechaRechazo: DateTime.tryParse(
                d['fechaRechazo']?.toString() ?? '',
              ),
              fechaPago: DateTime.tryParse(d['fechaPago']?.toString() ?? ''),
              procesoJudicial: d['procesoJud'] == true,
              enRevision: d['enRevision'] == true,
            ),
          );
        }
      }
    }
    // Los impagos primero, y dentro de cada grupo el más reciente arriba.
    salida.sort((a, b) {
      if (a.pagado != b.pagado) return a.pagado ? 1 : -1;
      final fa = a.fechaRechazo, fb = b.fechaRechazo;
      if (fa == null || fb == null) return 0;
      return fb.compareTo(fa);
    });
    return salida;
  }
}

/// El resultado completo de una consulta al BCRA.
class ConsultaBcra {
  const ConsultaBcra({
    required this.cuit,
    required this.consultadoEl,
    required this.entidades,
    this.denominacion,
    this.periodo,
    this.situacionMaxima,
    this.totalDeudaMiles = 0,
    this.diasAtrasoMax = 0,
    this.tieneProcesoJudicial = false,
    this.tieneRefinanciaciones = false,
    this.enRevision = false,
    this.chequesRechazados = false,
    this.chequesSinPagar = 0,
    this.cacheada = false,
    this.vencida = false,
    this.cheques = const [],
  });

  final String cuit;
  final DateTime consultadoEl;
  final List<EntidadBcra> entidades;
  final String? denominacion;

  /// Mes informado por el BCRA, formato "202607".
  final String? periodo;

  final int? situacionMaxima;
  final double totalDeudaMiles;
  final int diasAtrasoMax;
  final bool tieneProcesoJudicial;
  final bool tieneRefinanciaciones;
  final bool enRevision;
  final bool chequesRechazados;
  final int chequesSinPagar;

  /// Se devolvió la consulta guardada en vez de volver al BCRA.
  final bool cacheada;

  /// Pasaron más de 30 días: el BCRA ya publicó al menos un período nuevo y
  /// esto puede no reflejar la situación de hoy.
  final bool vencida;

  /// Cheques rechazados, agrupados por causal tal como los informa el BCRA.
  final List<ChequeBcra> cheques;

  double get totalDeuda => totalDeudaMiles * 1000;

  /// Nadie informó nada sobre esta persona.
  ///
  /// No es lo mismo que "situación 1": puede no tener historial crediticio.
  /// La ausencia de deudas no acredita solvencia ni confirma la identidad.
  bool get sinDeudasInformadas => entidades.isEmpty;

  /// El período legible: "202607" -> "julio 2026".
  String get periodoLegible {
    final p = periodo;
    if (p == null || p.length != 6) return '';
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final m = int.tryParse(p.substring(4));
    if (m == null || m < 1 || m > 12) return '';
    return '${meses[m - 1]} ${p.substring(0, 4)}';
  }

  /// El semáforo. Replica exactamente `semaforo_de_situacion` del SQL: si se
  /// cambia uno hay que cambiar el otro, y por eso hay un test que los ata.
  SemaforoCrediticio get semaforo {
    if (vencida) return SemaforoCrediticio.sinDatos;
    if ((situacionMaxima ?? 0) >= 4 ||
        chequesSinPagar > 0 ||
        tieneProcesoJudicial) {
      return SemaforoCrediticio.rojo;
    }
    if (situacionMaxima == 2 ||
        situacionMaxima == 3 ||
        chequesRechazados ||
        diasAtrasoMax > 30) {
      return SemaforoCrediticio.amarillo;
    }
    return situacionMaxima == 1
        ? SemaforoCrediticio.verde
        : SemaforoCrediticio.sinDatos;
  }

  /// Por qué dio ese color. Es lo que el vendedor le explica al cliente.
  List<String> get motivos {
    final m = <String>[];
    if (sinDeudasInformadas) {
      m.add('Ninguna entidad informó deudas a su nombre.');
    }
    if (vencida) {
      m.add('Consulta vencida: actualizá los datos antes de evaluar.');
    }
    if (situacionMaxima == 2) {
      m.add('Situación 2: requiere revisar el detalle informado.');
    }
    if (situacionMaxima != null && situacionMaxima! >= 4) {
      m.add('Está en situación $situacionMaxima en al menos una entidad.');
    }
    if (chequesSinPagar > 0) {
      m.add(
        'Tiene $chequesSinPagar cheque${chequesSinPagar == 1 ? '' : 's'} '
        'rechazado${chequesSinPagar == 1 ? '' : 's'} sin pagar.',
      );
    }
    if (tieneProcesoJudicial) m.add('Hay un proceso judicial informado.');
    if (situacionMaxima == 3) m.add('Situación 3: atrasos de hasta 180 días.');
    if (chequesRechazados && chequesSinPagar == 0) {
      m.add('Tuvo cheques rechazados, pero ya los pagó.');
    }
    if (diasAtrasoMax > 30) m.add('Registra $diasAtrasoMax días de atraso.');
    if (tieneRefinanciaciones) m.add('Tiene deuda refinanciada.');
    if (enRevision) m.add('Hay una clasificación en revisión.');
    if (m.isEmpty) {
      m.add('Todas las entidades lo informan en situación normal.');
    }
    return m;
  }

  /// La recomendación concreta: financiar o no.
  String get recomendacion => switch (semaforo) {
    SemaforoCrediticio.verde => 'Situación normal informada. El semáforo es orientativo: la agencia debe evaluar ingresos y capacidad de pago antes de aprobar financiación.',
    SemaforoCrediticio.amarillo => 'Hay observaciones que requieren revisión. Consultá el detalle por entidad y la documentación del cliente.',
    SemaforoCrediticio.rojo => 'Hay antecedentes de riesgo alto. Requiere evaluación de la agencia; este resultado no aprueba ni rechaza una operación.',
    SemaforoCrediticio.sinDatos =>
      vencida ? 'La consulta venció. Actualizala para evaluar la situación.' : 'No hay información suficiente para evaluar el historial crediticio. La ausencia de deudas no acredita solvencia ni confirma la identidad.',
  };

  /// Sirve para las dos fuentes: lo que devuelve la Edge Function y la fila
  /// de `v_clientes_semaforo`. Las columnas se llaman igual en las dos, y
  /// mantenerlo así evita tener dos parsers que se desincronizan.
  factory ConsultaBcra.desdeJson(
    Map<String, dynamic> j, {
    bool cacheada = false,
  }) {
    final crudas = (j['entidades'] as List?) ?? const [];
    return ConsultaBcra(
      cuit: j['cuit'] as String? ?? '',
      consultadoEl:
          DateTime.tryParse(j['consultado_at'] as String? ?? '') ??
          DateTime.now(),
      denominacion: j['denominacion'] as String?,
      periodo: j['periodo'] as String?,
      situacionMaxima: (j['situacion_maxima'] as num?)?.toInt(),
      totalDeudaMiles: _num(j['total_deuda_miles']),
      diasAtrasoMax: (j['dias_atraso_max'] as num?)?.toInt() ?? 0,
      tieneProcesoJudicial: j['tiene_proceso_judicial'] == true,
      tieneRefinanciaciones: j['tiene_refinanciaciones'] == true,
      enRevision: j['en_revision'] == true,
      chequesRechazados: j['tiene_cheques_rechazados'] == true,
      chequesSinPagar: (j['cheques_sin_pagar'] as num?)?.toInt() ?? 0,
      entidades:
          crudas
              .whereType<Map>()
              .map((e) => EntidadBcra.desdeJson(e.cast<String, dynamic>()))
              .toList()
            // Lo peor primero: es lo que hay que mirar.
            ..sort((a, b) => b.situacion.compareTo(a.situacion)),
      cheques: ChequeBcra.desdeCausales((j['cheques'] as List?) ?? const []),
      cacheada: cacheada,
      vencida: j['consulta_vencida'] == true,
    );
  }

  /// Postgres manda los numeric como string para no perder precisión.
  static double _num(dynamic v) => switch (v) {
    null => 0,
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };
}

/// Valida el CUIT/CUIL con su dígito verificador.
///
/// Mismo algoritmo que la Edge Function: acá evita un viaje al servidor, allá
/// evita guardar como "sin deudas" a alguien cuyo número estaba mal tipeado.
bool cuitValido(String cuit) {
  final d = cuit.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  final digitos = d.split('').map(int.parse).toList();
  var suma = 0;
  for (var i = 0; i < 10; i++) {
    suma += pesos[i] * digitos[i];
  }
  final resto = suma % 11;
  final verificador = resto == 0 ? 0 : (resto == 1 ? 9 : 11 - resto);
  return verificador == digitos[10];
}

/// Formatea 20123456789 como 20-12345678-9.
String formatearCuit(String cuit) {
  final d = cuit.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return cuit;
  return '${d.substring(0, 2)}-${d.substring(2, 10)}-${d.substring(10)}';
}
