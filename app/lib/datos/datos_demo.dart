// GENERADO POR tests/generar_datos_demo.mjs — NO EDITAR A MANO.
//
// Datos de ejemplo del sistema original del cliente (rotacion_1.html).
// Se usan cuando la app corre sin backend configurado (Config.modoDemo).
// Para regenerar: cd tests && node generar_datos_demo.mjs

import '../dominio/modelos.dart';

class VehiculoSemilla {
  const VehiculoSemilla({
    required this.codigo,
    required this.marca,
    required this.modelo,
    required this.anio,
    required this.fechaCompra,
    required this.fechaIngreso,
    required this.precioCompra,
    required this.precioObjetivo,
    required this.estado,
    this.version,
    this.km,
    this.observaciones,
  });
  final String codigo, marca, modelo;
  final int anio;
  final String? version;
  final int? km;
  final DateTime fechaCompra, fechaIngreso;
  final double precioCompra, precioObjetivo;
  final EstadoVehiculo estado;
  final String? observaciones;
}

class GastoSemilla {
  const GastoSemilla({
    required this.codigo,
    required this.fecha,
    required this.categoria,
    required this.descripcion,
    required this.importe,
  });
  final String codigo, categoria;
  final String? descripcion;
  final DateTime fecha;
  final double importe;
}

class PrecioSemilla {
  const PrecioSemilla({
    required this.codigo,
    required this.fecha,
    required this.precio,
    this.motivo,
  });
  final String codigo;
  final DateTime fecha;
  final double precio;
  final String? motivo;
}

class VentaSemilla {
  const VentaSemilla({
    required this.codigo,
    required this.fecha,
    required this.precioFinal,
    required this.gastosFinales,
    this.cliente,
    this.vendedor,
  });
  final String codigo;
  final DateTime fecha;
  final double precioFinal, gastosFinales;
  final String? cliente, vendedor;
}

class InteresadoSemilla {
  const InteresadoSemilla({
    required this.codigo,
    required this.nombre,
    this.telefono,
    this.fecha,
    this.notas,
  });
  final String codigo, nombre;
  final String? telefono, notas;
  final DateTime? fecha;
}

class IpcSemilla {
  const IpcSemilla({required this.mes, this.variacion});
  final DateTime mes;
  final double? variacion;
}

abstract final class DatosDemo {
  static final vehiculos = <VehiculoSemilla>[
    VehiculoSemilla(
      codigo: 'V001',
      marca: 'Toyota',
      modelo: 'Corolla',
      anio: 2021,
      version: 'XEI 1.8 CVT',
      km: 62000,
      fechaCompra: DateTime.utc(2026, 05, 28),
      fechaIngreso: DateTime.utc(2026, 05, 30),
      precioCompra: 19800000,
      precioObjetivo: 22500000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Único dueño, service oficial',
    ),
    VehiculoSemilla(
      codigo: 'V002',
      marca: 'Volkswagen',
      modelo: 'Amarok',
      anio: 2020,
      version: 'V6 Highline',
      km: 98000,
      fechaCompra: DateTime.utc(2026, 03, 10),
      fechaIngreso: DateTime.utc(2026, 03, 12),
      precioCompra: 34500000,
      precioObjetivo: 39900000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Requiere cubiertas nuevas',
    ),
    VehiculoSemilla(
      codigo: 'V003',
      marca: 'Ford',
      modelo: 'Ranger',
      anio: 2022,
      version: 'XLT 3.2 4x4',
      km: 71000,
      fechaCompra: DateTime.utc(2026, 07, 14),
      fechaIngreso: DateTime.utc(2026, 07, 16),
      precioCompra: 41000000,
      precioObjetivo: 46500000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Ingresó por parte de pago',
    ),
    VehiculoSemilla(
      codigo: 'V004',
      marca: 'Chevrolet',
      modelo: 'Cruze',
      anio: 2019,
      version: 'LTZ 1.4T',
      km: 88000,
      fechaCompra: DateTime.utc(2026, 02, 05),
      fechaIngreso: DateTime.utc(2026, 02, 08),
      precioCompra: 15200000,
      precioObjetivo: 18500000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Detalle de chapa en puerta trasera',
    ),
    VehiculoSemilla(
      codigo: 'V005',
      marca: 'Fiat',
      modelo: 'Cronos',
      anio: 2023,
      version: 'Drive 1.3 GSE',
      km: 34000,
      fechaCompra: DateTime.utc(2026, 08, 01),
      fechaIngreso: DateTime.utc(2026, 08, 03),
      precioCompra: 16900000,
      precioObjetivo: 19200000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Muy bajo kilometraje',
    ),
    VehiculoSemilla(
      codigo: 'V006',
      marca: 'Peugeot',
      modelo: '208',
      anio: 2022,
      version: 'Allure 1.6',
      km: 41000,
      fechaCompra: DateTime.utc(2026, 06, 18),
      fechaIngreso: DateTime.utc(2026, 06, 20),
      precioCompra: 17400000,
      precioObjetivo: 20000000,
      estado: EstadoVehiculo.enStock,
      observaciones: '',
    ),
    VehiculoSemilla(
      codigo: 'V007',
      marca: 'Renault',
      modelo: 'Duster',
      anio: 2021,
      version: 'Iconic 1.3T',
      km: 66000,
      fechaCompra: DateTime.utc(2026, 04, 22),
      fechaIngreso: DateTime.utc(2026, 04, 25),
      precioCompra: 21000000,
      precioObjetivo: 24500000,
      estado: EstadoVehiculo.enPreparacion,
      observaciones: 'En taller por chapa y pintura',
    ),
    VehiculoSemilla(
      codigo: 'V008',
      marca: 'Honda',
      modelo: 'HR-V',
      anio: 2020,
      version: 'EXL CVT',
      km: 79000,
      fechaCompra: DateTime.utc(2026, 01, 15),
      fechaIngreso: DateTime.utc(2026, 01, 18),
      precioCompra: 24800000,
      precioObjetivo: 29000000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Difícil rotación, revisar precio',
    ),
    VehiculoSemilla(
      codigo: 'V009',
      marca: 'Toyota',
      modelo: 'Hilux',
      anio: 2019,
      version: 'SRV 4x4 AT',
      km: 132000,
      fechaCompra: DateTime.utc(2026, 05, 05),
      fechaIngreso: DateTime.utc(2026, 05, 07),
      precioCompra: 32000000,
      precioObjetivo: 37500000,
      estado: EstadoVehiculo.reservado,
      observaciones: 'Seña recibida',
    ),
    VehiculoSemilla(
      codigo: 'V010',
      marca: 'Nissan',
      modelo: 'Kicks',
      anio: 2021,
      version: 'Advance CVT',
      km: 58000,
      fechaCompra: DateTime.utc(2026, 07, 28),
      fechaIngreso: DateTime.utc(2026, 07, 30),
      precioCompra: 20500000,
      precioObjetivo: 23500000,
      estado: EstadoVehiculo.enStock,
      observaciones: '',
    ),
    VehiculoSemilla(
      codigo: 'V011',
      marca: 'Volkswagen',
      modelo: 'Gol Trend',
      anio: 2018,
      version: 'Trendline 1.6',
      km: 105000,
      fechaCompra: DateTime.utc(2026, 02, 20),
      fechaIngreso: DateTime.utc(2026, 02, 22),
      precioCompra: 9800000,
      precioObjetivo: 12500000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Unidad de entrada, alta demanda',
    ),
    VehiculoSemilla(
      codigo: 'V012',
      marca: 'Chevrolet',
      modelo: 'Tracker',
      anio: 2022,
      version: 'Premier 1.2T',
      km: 45000,
      fechaCompra: DateTime.utc(2026, 06, 02),
      fechaIngreso: DateTime.utc(2026, 06, 04),
      precioCompra: 26500000,
      precioObjetivo: 30500000,
      estado: EstadoVehiculo.enStock,
      observaciones: '',
    ),
    VehiculoSemilla(
      codigo: 'V013',
      marca: 'Ford',
      modelo: 'EcoSport',
      anio: 2019,
      version: 'SE 1.5',
      km: 92000,
      fechaCompra: DateTime.utc(2026, 03, 01),
      fechaIngreso: DateTime.utc(2026, 03, 04),
      precioCompra: 13500000,
      precioObjetivo: 16500000,
      estado: EstadoVehiculo.enStock,
      observaciones: 'Vendida a cliente recurrente',
    ),
  ];

  static final gastos = <GastoSemilla>[
    GastoSemilla(
      codigo: 'V001',
      fecha: DateTime.utc(2026, 06, 02),
      categoria: 'Service',
      descripcion: 'Service completo 60.000 km',
      importe: 320000,
    ),
    GastoSemilla(
      codigo: 'V001',
      fecha: DateTime.utc(2026, 06, 05),
      categoria: 'Lavado/Detallado',
      descripcion: 'Detallado interior y pulido',
      importe: 85000,
    ),
    GastoSemilla(
      codigo: 'V001',
      fecha: DateTime.utc(2026, 06, 10),
      categoria: 'Transferencia',
      descripcion: 'Gastos de transferencia',
      importe: 210000,
    ),
    GastoSemilla(
      codigo: 'V002',
      fecha: DateTime.utc(2026, 03, 20),
      categoria: 'Cubiertas',
      descripcion: '4 cubiertas 255/60 R18',
      importe: 1450000,
    ),
    GastoSemilla(
      codigo: 'V002',
      fecha: DateTime.utc(2026, 04, 02),
      categoria: 'Service',
      descripcion: 'Service mayor V6',
      importe: 480000,
    ),
    GastoSemilla(
      codigo: 'V002',
      fecha: DateTime.utc(2026, 05, 15),
      categoria: 'Reparaciones',
      descripcion: 'Reparación tren delantero',
      importe: 620000,
    ),
    GastoSemilla(
      codigo: 'V002',
      fecha: DateTime.utc(2026, 06, 20),
      categoria: 'Almacenamiento',
      descripcion: 'Cochera 3 meses',
      importe: 180000,
    ),
    GastoSemilla(
      codigo: 'V003',
      fecha: DateTime.utc(2026, 07, 20),
      categoria: 'Lavado/Detallado',
      descripcion: 'Lavado y detallado',
      importe: 70000,
    ),
    GastoSemilla(
      codigo: 'V003',
      fecha: DateTime.utc(2026, 07, 25),
      categoria: 'Gestoría',
      descripcion: 'Gestoría documentación',
      importe: 150000,
    ),
    GastoSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 02, 15),
      categoria: 'Chapa y pintura',
      descripcion: 'Chapa y pintura puerta trasera',
      importe: 540000,
    ),
    GastoSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 03, 10),
      categoria: 'Service',
      descripcion: 'Service de mantenimiento',
      importe: 240000,
    ),
    GastoSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 05, 05),
      categoria: 'Almacenamiento',
      descripcion: 'Cochera 3 meses',
      importe: 180000,
    ),
    GastoSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 07, 01),
      categoria: 'Reparaciones',
      descripcion: 'Cambio de embrague',
      importe: 710000,
    ),
    GastoSemilla(
      codigo: 'V005',
      fecha: DateTime.utc(2026, 08, 05),
      categoria: 'Lavado/Detallado',
      descripcion: 'Lavado de entrega',
      importe: 45000,
    ),
    GastoSemilla(
      codigo: 'V006',
      fecha: DateTime.utc(2026, 06, 25),
      categoria: 'Service',
      descripcion: 'Service 40.000 km',
      importe: 260000,
    ),
    GastoSemilla(
      codigo: 'V006',
      fecha: DateTime.utc(2026, 07, 08),
      categoria: 'Cubiertas',
      descripcion: '2 cubiertas delanteras',
      importe: 380000,
    ),
    GastoSemilla(
      codigo: 'V007',
      fecha: DateTime.utc(2026, 05, 02),
      categoria: 'Chapa y pintura',
      descripcion: 'Reparación lateral completo',
      importe: 980000,
    ),
    GastoSemilla(
      codigo: 'V007',
      fecha: DateTime.utc(2026, 05, 20),
      categoria: 'Service',
      descripcion: 'Service + correa',
      importe: 410000,
    ),
    GastoSemilla(
      codigo: 'V007',
      fecha: DateTime.utc(2026, 06, 15),
      categoria: 'Reparaciones',
      descripcion: 'Suspensión trasera',
      importe: 350000,
    ),
    GastoSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 01, 25),
      categoria: 'Service',
      descripcion: 'Service CVT',
      importe: 390000,
    ),
    GastoSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 02, 18),
      categoria: 'Cubiertas',
      descripcion: '4 cubiertas 215/55 R17',
      importe: 1120000,
    ),
    GastoSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 04, 10),
      categoria: 'Almacenamiento',
      descripcion: 'Cochera 3 meses',
      importe: 180000,
    ),
    GastoSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 06, 05),
      categoria: 'Reparaciones',
      descripcion: 'Aire acondicionado',
      importe: 290000,
    ),
    GastoSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 07, 12),
      categoria: 'Almacenamiento',
      descripcion: 'Cochera 2 meses',
      importe: 120000,
    ),
    GastoSemilla(
      codigo: 'V009',
      fecha: DateTime.utc(2026, 05, 15),
      categoria: 'Service',
      descripcion: 'Service 130.000 km',
      importe: 520000,
    ),
    GastoSemilla(
      codigo: 'V009',
      fecha: DateTime.utc(2026, 05, 28),
      categoria: 'Patentamiento',
      descripcion: 'Trámite patentamiento',
      importe: 340000,
    ),
    GastoSemilla(
      codigo: 'V010',
      fecha: DateTime.utc(2026, 08, 02),
      categoria: 'Lavado/Detallado',
      descripcion: 'Detallado completo',
      importe: 90000,
    ),
    GastoSemilla(
      codigo: 'V010',
      fecha: DateTime.utc(2026, 08, 08),
      categoria: 'Transferencia',
      descripcion: 'Gastos de transferencia',
      importe: 230000,
    ),
    GastoSemilla(
      codigo: 'V011',
      fecha: DateTime.utc(2026, 03, 01),
      categoria: 'Reparaciones',
      descripcion: 'Motor de arranque',
      importe: 180000,
    ),
    GastoSemilla(
      codigo: 'V011',
      fecha: DateTime.utc(2026, 03, 15),
      categoria: 'Chapa y pintura',
      descripcion: 'Retoque de pintura general',
      importe: 420000,
    ),
    GastoSemilla(
      codigo: 'V011',
      fecha: DateTime.utc(2026, 06, 01),
      categoria: 'Almacenamiento',
      descripcion: 'Cochera 4 meses',
      importe: 240000,
    ),
    GastoSemilla(
      codigo: 'V012',
      fecha: DateTime.utc(2026, 06, 10),
      categoria: 'Service',
      descripcion: 'Service completo',
      importe: 300000,
    ),
    GastoSemilla(
      codigo: 'V012',
      fecha: DateTime.utc(2026, 06, 18),
      categoria: 'Lavado/Detallado',
      descripcion: 'Detallado de entrega',
      importe: 80000,
    ),
    GastoSemilla(
      codigo: 'V013',
      fecha: DateTime.utc(2026, 03, 12),
      categoria: 'Reparaciones',
      descripcion: 'Caja de dirección',
      importe: 450000,
    ),
    GastoSemilla(
      codigo: 'V013',
      fecha: DateTime.utc(2026, 03, 25),
      categoria: 'Service',
      descripcion: 'Service general',
      importe: 230000,
    ),
    GastoSemilla(
      codigo: 'V013',
      fecha: DateTime.utc(2026, 04, 05),
      categoria: 'Transferencia',
      descripcion: 'Gastos de transferencia',
      importe: 190000,
    ),
  ];

  static final precios = <PrecioSemilla>[
    PrecioSemilla(
      codigo: 'V001',
      fecha: DateTime.utc(2026, 08, 10),
      precio: 22100000,
      motivo: 'Ajuste por baja de consultas',
    ),
    PrecioSemilla(
      codigo: 'V002',
      fecha: DateTime.utc(2026, 06, 05),
      precio: 38500000,
      motivo: 'Reducción para acelerar rotación',
    ),
    PrecioSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 05, 10),
      precio: 17800000,
      motivo: 'Ajuste de mercado',
    ),
    PrecioSemilla(
      codigo: 'V004',
      fecha: DateTime.utc(2026, 07, 15),
      precio: 17200000,
      motivo: 'Sigue sin venderse',
    ),
    PrecioSemilla(
      codigo: 'V007',
      fecha: DateTime.utc(2026, 06, 20),
      precio: 25200000,
      motivo: 'Suba por reparaciones realizadas',
    ),
    PrecioSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 04, 05),
      precio: 27500000,
      motivo: 'Baja rotación',
    ),
    PrecioSemilla(
      codigo: 'V008',
      fecha: DateTime.utc(2026, 06, 20),
      precio: 26200000,
      motivo: 'Segunda baja de precio',
    ),
    PrecioSemilla(
      codigo: 'V009',
      fecha: DateTime.utc(2026, 07, 01),
      precio: 36800000,
      motivo: 'Negociación con cliente',
    ),
    PrecioSemilla(
      codigo: 'V011',
      fecha: DateTime.utc(2026, 05, 01),
      precio: 12900000,
      motivo: 'Alta demanda del segmento',
    ),
    PrecioSemilla(
      codigo: 'V012',
      fecha: DateTime.utc(2026, 07, 05),
      precio: 29800000,
      motivo: 'Cierre de operación',
    ),
    PrecioSemilla(
      codigo: 'V013',
      fecha: DateTime.utc(2026, 05, 10),
      precio: 15900000,
      motivo: 'Ajuste para cerrar venta',
    ),
  ];

  static final ventas = <VentaSemilla>[
    VentaSemilla(
      codigo: 'V012',
      fecha: DateTime.utc(2026, 07, 18),
      precioFinal: 29500000,
      gastosFinales: 120000,
      cliente: 'M. Fernández',
      vendedor: 'Laura G.',
    ),
    VentaSemilla(
      codigo: 'V013',
      fecha: DateTime.utc(2026, 05, 22),
      precioFinal: 15700000,
      gastosFinales: 90000,
      cliente: 'J. Sosa',
      vendedor: 'Diego R.',
    ),
  ];

  static final interesados = <InteresadoSemilla>[
    InteresadoSemilla(
      codigo: 'V003',
      nombre: 'L. Benítez',
      telefono: '11-4455-2200',
      fecha: DateTime.utc(2026, 08, 10),
      notas: 'Preguntó por financiación a 12 cuotas',
    ),
    InteresadoSemilla(
      codigo: 'V008',
      nombre: 'R. Ibarra',
      telefono: '11-6677-8899',
      fecha: DateTime.utc(2026, 08, 14),
      notas: 'Va a volver con su pareja a ver la unidad',
    ),
    InteresadoSemilla(
      codigo: 'V012',
      nombre: 'C. Domínguez',
      telefono: '11-2233-4455',
      fecha: DateTime.utc(2026, 08, 18),
      notas: 'Pidió que le avisen si baja el precio',
    ),
  ];

  /// Serie IPC del INDEC. El primer mes es la base (indice 100).
  static final ipc = <IpcSemilla>[
    IpcSemilla(mes: DateTime.utc(2025, 07, 1), variacion: null),
    IpcSemilla(mes: DateTime.utc(2025, 08, 1), variacion: 0.019),
    IpcSemilla(mes: DateTime.utc(2025, 09, 1), variacion: 0.021),
    IpcSemilla(mes: DateTime.utc(2025, 10, 1), variacion: 0.023),
    IpcSemilla(mes: DateTime.utc(2025, 11, 1), variacion: 0.025),
    IpcSemilla(mes: DateTime.utc(2025, 12, 1), variacion: 0.028),
    IpcSemilla(mes: DateTime.utc(2026, 01, 1), variacion: 0.029),
    IpcSemilla(mes: DateTime.utc(2026, 02, 1), variacion: 0.029),
    IpcSemilla(mes: DateTime.utc(2026, 03, 1), variacion: 0.034),
    IpcSemilla(mes: DateTime.utc(2026, 04, 1), variacion: 0.026),
    IpcSemilla(mes: DateTime.utc(2026, 05, 1), variacion: 0.021),
    IpcSemilla(mes: DateTime.utc(2026, 06, 1), variacion: 0.019),
    IpcSemilla(mes: DateTime.utc(2026, 07, 1), variacion: 0.021),
    IpcSemilla(mes: DateTime.utc(2026, 08, 1), variacion: 0.021),
  ];
}
