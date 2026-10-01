import 'package:flutter/material.dart';

/// Una tarea de la agenda: lo que hay que hacer y cuándo.
///
/// "Para atender hoy" junta dos cosas distintas: lo que el sistema deduce
/// solo (una unidad parada, una consulta vencida) y lo que alguien se
/// comprometió a hacer. Esto es lo segundo, y es lo que antes vivía en una
/// hoja suelta arriba del mostrador.
class Tarea {
  const Tarea({
    required this.id,
    required this.titulo,
    required this.venceEl,
    this.tipo = TipoTarea.otro,
    this.detalle = '',
    this.hora,
    this.repeticion = RepeticionTarea.unaVez,
    this.estado = EstadoTarea.pendiente,
    this.oportunidadId,
    this.vehiculoId,
    this.clienteNombre,
    this.clienteTelefono,
    this.vehiculoTitulo,
    this.vehiculoPatente,
  });

  final String id;
  final String titulo;
  final String detalle;
  final TipoTarea tipo;
  final DateTime venceEl;

  /// La hora, si se puso. La mayoría de las tareas no la necesitan.
  final TimeOfDay? hora;

  final RepeticionTarea repeticion;
  final EstadoTarea estado;

  final String? oportunidadId;
  final String? vehiculoId;

  /// Datos de contexto que trae la vista, para no pedirlos de a uno.
  final String? clienteNombre;
  final String? clienteTelefono;
  final String? vehiculoTitulo;
  final String? vehiculoPatente;

  bool get pendiente => estado == EstadoTarea.pendiente;

  int get diasParaVencer {
    final hoy = DateTime.now();
    return DateTime(
      venceEl.year,
      venceEl.month,
      venceEl.day,
    ).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  bool get vencida => pendiente && diasParaVencer < 0;
  bool get esDeHoy => diasParaVencer == 0;

  /// "Para hoy", "Mañana", "Hace 3 días".
  String get cuando {
    final d = diasParaVencer;
    if (d == 0) return 'Para hoy';
    if (d == 1) return 'Para mañana';
    if (d == -1) return 'Era ayer';
    if (d > 1) return 'En $d días';
    return 'Hace ${-d} días';
  }
}

enum TipoTarea {
  llamar('Llamar', 'llamar', Icons.call_outlined),
  cobrar('Cobrar', 'cobrar', Icons.payments_outlined),
  taller('Taller', 'taller', Icons.build_outlined),
  banco('Banco', 'banco', Icons.account_balance_outlined),
  tramite('Trámite o papeles', 'tramite', Icons.description_outlined),
  otro('Otra cosa', 'otro', Icons.edit_outlined);

  const TipoTarea(this.etiqueta, this.valorBd, this.icono);
  final String etiqueta;
  final String valorBd;
  final IconData icono;

  static TipoTarea desde(String? v) =>
      TipoTarea.values.where((t) => t.valorBd == v).firstOrNull ??
      TipoTarea.otro;
}

enum RepeticionTarea {
  unaVez('Una sola vez', 'una_vez'),
  diaria('Todos los días', 'diaria'),
  semanal('Cada semana', 'semanal'),
  mensual('Cada mes', 'mensual');

  const RepeticionTarea(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static RepeticionTarea desde(String? v) =>
      RepeticionTarea.values.where((r) => r.valorBd == v).firstOrNull ??
      RepeticionTarea.unaVez;
}

enum EstadoTarea {
  pendiente('Pendiente', 'pendiente'),
  hecha('Hecha', 'hecha'),
  cancelada('Cancelada', 'cancelada');

  const EstadoTarea(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoTarea desde(String? v) =>
      EstadoTarea.values.where((e) => e.valorBd == v).firstOrNull ??
      EstadoTarea.pendiente;
}

/// Lo que se carga en "Nueva tarea".
class AltaTarea {
  const AltaTarea({
    required this.titulo,
    required this.venceEl,
    this.id,
    this.tipo = TipoTarea.otro,
    this.detalle = '',
    this.hora,
    this.repeticion = RepeticionTarea.unaVez,
    this.oportunidadId,
    this.vehiculoId,
  });

  final String? id;
  final String titulo;
  final String detalle;
  final TipoTarea tipo;
  final DateTime venceEl;
  final TimeOfDay? hora;
  final RepeticionTarea repeticion;
  final String? oportunidadId;
  final String? vehiculoId;

  bool get esEdicion => id != null;

  AltaTarea copiar({
    String? titulo,
    String? detalle,
    TipoTarea? tipo,
    DateTime? venceEl,
    TimeOfDay? hora,
    RepeticionTarea? repeticion,
    String? oportunidadId,
    String? vehiculoId,
    bool limpiarCliente = false,
    bool limpiarVehiculo = false,
    bool limpiarHora = false,
  }) => AltaTarea(
    id: id,
    titulo: titulo ?? this.titulo,
    detalle: detalle ?? this.detalle,
    tipo: tipo ?? this.tipo,
    venceEl: venceEl ?? this.venceEl,
    hora: limpiarHora ? null : (hora ?? this.hora),
    repeticion: repeticion ?? this.repeticion,
    oportunidadId: limpiarCliente
        ? null
        : (oportunidadId ?? this.oportunidadId),
    vehiculoId: limpiarVehiculo ? null : (vehiculoId ?? this.vehiculoId),
  );

  Map<String, String> validar() {
    final e = <String, String>{};
    if (titulo.trim().isEmpty) e['titulo'] = 'Poné qué hay que hacer.';
    return e;
  }
}
