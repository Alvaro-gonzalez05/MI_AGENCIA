import 'package:flutter/widgets.dart';

import '../core/tema/colores.dart';

/// Semaforo de ROTACION: cuanto lleva la unidad en el predio contra los
/// umbrales de la agencia. No confundir con [SemaforoCrediticio], que mide
/// al cliente y no al vehiculo.
enum AlertaRotacion {
  normal('Normal'),
  observar('Observar'),
  atencion('Atención'),
  critico('Crítico'),
  vendido('Vendido');

  const AlertaRotacion(this.etiqueta);
  final String etiqueta;

  static AlertaRotacion desde(String s) => AlertaRotacion.values.firstWhere(
    (e) => e.name == s,
    orElse: () => AlertaRotacion.normal,
  );

  Color color(Paleta p) => switch (this) {
    AlertaRotacion.normal => p.bien,
    AlertaRotacion.observar => p.observar,
    AlertaRotacion.atencion => p.atencion,
    AlertaRotacion.critico => p.critico,
    AlertaRotacion.vendido => p.neutro,
  };

  Color lavado(Paleta p) => switch (this) {
    AlertaRotacion.normal => p.bienLavado,
    AlertaRotacion.observar => p.observarLavado,
    AlertaRotacion.atencion => p.atencionLavado,
    AlertaRotacion.critico => p.criticoLavado,
    AlertaRotacion.vendido => p.neutroLavado,
  };
}

/// Semaforo CREDITICIO: situacion del interesado en la Central de Deudores
/// del BCRA. Es lo que responde "¿le puedo financiar la compra?".
enum SemaforoCrediticio {
  verde('Apto'),
  amarillo('Con reparos'),
  rojo('Riesgo alto'),
  sinDatos('Sin consultar');

  const SemaforoCrediticio(this.etiqueta);
  final String etiqueta;

  Color color(Paleta p) => switch (this) {
    SemaforoCrediticio.verde => p.bien,
    SemaforoCrediticio.amarillo => p.observar,
    SemaforoCrediticio.rojo => p.critico,
    SemaforoCrediticio.sinDatos => p.neutro,
  };

  Color lavado(Paleta p) => switch (this) {
    SemaforoCrediticio.verde => p.bienLavado,
    SemaforoCrediticio.amarillo => p.observarLavado,
    SemaforoCrediticio.rojo => p.criticoLavado,
    SemaforoCrediticio.sinDatos => p.neutroLavado,
  };
}

enum EstadoVehiculo {
  enStock('En stock'),
  enPreparacion('En preparación'),
  reservado('Reservado'),
  vendido('Vendido'),
  dadoDeBaja('Dado de baja');

  const EstadoVehiculo(this.etiqueta);
  final String etiqueta;
}

/// Un vehiculo con TODO ya calculado.
///
/// Espeja fila por fila la vista `v_inventario` de la base. Cuando Supabase
/// este conectado, esto se hidrata directo del select; en modo demo lo llena
/// el motor de calculo en Dart.
class VehiculoInventario {
  const VehiculoInventario({
    required this.id,
    required this.codigo,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.estado,
    required this.alerta,
    required this.fechaIngreso,
    required this.precioCompra,
    required this.precioObjetivo,
    required this.costoTotal,
    required this.gastosAcum,
    required this.cantidadGastos,
    required this.diasEnStock,
    required this.precioActual,
    required this.capitalInmovilizado,
    required this.gananciaEstimada,
    required this.margenActual,
    required this.margenEsperado,
    required this.precioParaMargenObjetivo,
    required this.precioSugerido,
    required this.costoTotalHoy,
    required this.gananciaRealIpc,
    required this.gananciaRealUsd,
    this.version,
    this.km,
    this.fechaCompra,
    this.patente,
    this.margenReal,
    this.fechaVenta,
    this.precioFinal,
    this.observaciones,
    this.revistaArs,
  });

  final String id;
  final String codigo;
  final String marca;
  final String modelo;
  final int anio;
  final String? version;
  final int? km;
  final EstadoVehiculo estado;
  final AlertaRotacion alerta;
  final DateTime fechaIngreso;

  /// Necesarias para poder editar la unidad sin inventar valores.
  final DateTime? fechaCompra;
  final String? patente;

  final double precioCompra;

  /// El precio al que se apunto al darla de alta. No confundir con
  /// [precioActual], que es el ultimo publicado y cambia con el tiempo.
  final double precioObjetivo;
  final double gastosAcum;
  final int cantidadGastos;
  final double costoTotal;
  final int diasEnStock;
  final double precioActual;
  final double capitalInmovilizado;
  final double gananciaEstimada;
  final double margenActual;
  final double margenEsperado;
  final double? margenReal;
  final double precioParaMargenObjetivo;
  final double precioSugerido;

  /// Costo llevado a moneda de hoy con el IPC del INDEC.
  final double costoTotalHoy;
  final double gananciaRealIpc;
  final double gananciaRealUsd;

  final DateTime? fechaVenta;
  final double? precioFinal;
  final String? observaciones;
  final double? revistaArs;

  bool get vendido => estado == EstadoVehiculo.vendido;

  String get titulo => '$marca $modelo';
  String get subtitulo => [
    anio.toString(),
    if (version != null && version!.isNotEmpty) version!,
  ].join(' · ');
}

/// Totales de la agencia. Espeja la vista `v_dashboard`.
class ResumenAgencia {
  const ResumenAgencia({
    required this.unidadesEnStock,
    required this.unidadesVendidas,
    required this.capitalInmovilizado,
    required this.gananciaPotencial,
    required this.gananciaRealizada,
    required this.gananciaRealizadaIpc,
    required this.gananciaRealizadaUsd,
    required this.diasPromedioStock,
    required this.margenPromedio,
    required this.criticos,
    required this.enAtencion,
    required this.enObservacion,
    required this.bajoMargenMinimo,
  });

  final int unidadesEnStock;
  final int unidadesVendidas;
  final double capitalInmovilizado;
  final double gananciaPotencial;
  final double gananciaRealizada;
  final double gananciaRealizadaIpc;
  final double gananciaRealizadaUsd;
  final double diasPromedioStock;
  final double margenPromedio;
  final int criticos;
  final int enAtencion;
  final int enObservacion;
  final int bajoMargenMinimo;
}

class Interesado {
  const Interesado({
    required this.id,
    required this.nombre,
    required this.semaforo,
    this.telefono,
    this.email,
    this.cuit,
    this.vehiculoCodigo,
    this.vehiculoTitulo,
    this.situacionBcra,
    this.notas,
    this.fecha,
  });

  final String id;
  final String nombre;
  final SemaforoCrediticio semaforo;
  final String? telefono;
  final String? email;
  final String? cuit;
  final String? vehiculoCodigo;
  final String? vehiculoTitulo;
  final int? situacionBcra;
  final String? notas;
  final DateTime? fecha;
}

/// Parametros de la agencia. Espeja `agencia_config`.
class ConfigAgencia {
  const ConfigAgencia({
    this.diasVerde = 30,
    this.diasAmarillo = 60,
    this.diasRojo = 90,
    this.margenMinimo = 0.10,
    this.margenObjetivo = 0.30,
    this.toleranciaCaidaMargen = 0.005,
    this.toleranciaDesvioPrecio = 0.02,
    this.umbralGastosAltos = 1000000,
    this.redondeo = 50000,
    this.capacidad = 60,
    this.tasaFinanciacionMensual = 0.06,
    this.tipoCambio = 1515,
  });

  final int diasVerde;
  final int diasAmarillo;
  final int diasRojo;
  final double margenMinimo;
  final double margenObjetivo;
  final double toleranciaCaidaMargen;
  final double toleranciaDesvioPrecio;
  final double umbralGastosAltos;
  final double redondeo;
  final int capacidad;
  final double tasaFinanciacionMensual;
  final double tipoCambio;
}
