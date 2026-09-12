// Genera app/lib/datos/datos_demo.dart a partir de la semilla del HTML
// original del cliente. Se transcribe con codigo, no a mano, para que los
// datos de demo sean exactamente los suyos y no una version aproximada.
//
//   node generar_datos_demo.mjs
import { DATA_SEED } from './motor_original.mjs';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const SALIDA = fileURLToPath(new URL('../app/lib/datos/datos_demo.dart', import.meta.url));

const txt = (s) => s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "\\'").replace(/\$/g, "\\\$")}'`;
const num = (n) => n === null || n === undefined ? 'null' : String(n);

const ESTADO = {
  'En stock': 'EstadoVehiculo.enStock',
  'En preparación': 'EstadoVehiculo.enPreparacion',
  'Reservado': 'EstadoVehiculo.reservado',
};

const vehiculos = DATA_SEED.vehiculos.map(v => `  VehiculoSemilla(
    codigo: ${txt(v.id)}, marca: ${txt(v.marca)}, modelo: ${txt(v.modelo)},
    anio: ${v.anio}, version: ${txt(v.version)}, km: ${num(v.km)},
    fechaCompra: DateTime.utc(${v.fechaCompra.split('-').join(', ')}),
    fechaIngreso: DateTime.utc(${v.fechaIngreso.split('-').join(', ')}),
    precioCompra: ${v.precioCompra}, precioObjetivo: ${v.precioObjetivo},
    estado: ${ESTADO[v.estado]}, observaciones: ${txt(v.obs)},
  ),`).join('\n');

// La categoria se guarda con el MISMO valor que usa el enum de Postgres.
// Guardar la etiqueta en castellano hacia que la app no la reconociera y
// mostrara todos los gastos como 'Otros'.
const CAT_BD = {
  'Service': 'service', 'Reparaciones': 'reparaciones', 'Cubiertas': 'cubiertas',
  'Chapa y pintura': 'chapa_y_pintura', 'Lavado/Detallado': 'lavado_detallado',
  'Transferencia': 'transferencia', 'Patentamiento': 'patentamiento',
  'Gestoría': 'gestoria', 'Almacenamiento': 'almacenamiento', 'Otros': 'otros',
};
const gastos = DATA_SEED.gastos.map(g => `  GastoSemilla(codigo: ${txt(g.idVehiculo)}, fecha: DateTime.utc(${g.fecha.split('-').join(', ')}), categoria: ${txt(CAT_BD[g.categoria] || 'otros')}, descripcion: ${txt(g.desc)}, importe: ${g.importe}),`).join('\n');

const precios = DATA_SEED.precios.map(p => `  PrecioSemilla(codigo: ${txt(p.idVehiculo)}, fecha: DateTime.utc(${p.fecha.split('-').join(', ')}), precio: ${p.nuevoPrecio}, motivo: ${txt(p.motivo)}),`).join('\n');

const ventas = DATA_SEED.ventas.map(s => `  VentaSemilla(codigo: ${txt(s.idVehiculo)}, fecha: DateTime.utc(${s.fechaVenta.split('-').join(', ')}), precioFinal: ${s.precioFinal}, gastosFinales: ${s.gastosFinales}, cliente: ${txt(s.cliente)}, vendedor: ${txt(s.vendedor)}),`).join('\n');

const interesados = DATA_SEED.interesados.map(i => `  InteresadoSemilla(codigo: ${txt(i.idVehiculo)}, nombre: ${txt(i.nombre)}, telefono: ${txt(i.telefono)}, fecha: DateTime.utc(${i.fecha.split('-').join(', ')}), notas: ${txt(i.obs)}),`).join('\n');

const ipc = DATA_SEED.config.ipcSerie.map(r => {
  const [y, m] = r.mes.split('-');
  return `  IpcSemilla(mes: DateTime.utc(${y}, ${m}, 1), variacion: ${num(r.variacion)}),`;
}).join('\n');

const dart = `// GENERADO POR tests/generar_datos_demo.mjs — NO EDITAR A MANO.
//
// Datos de ejemplo del sistema original del cliente (rotacion_1.html).
// Se usan cuando la app corre sin backend configurado (Config.modoDemo).
// Para regenerar: cd tests && node generar_datos_demo.mjs

import '../dominio/modelos.dart';

class VehiculoSemilla {
  const VehiculoSemilla({
    required this.codigo, required this.marca, required this.modelo,
    required this.anio, required this.fechaCompra, required this.fechaIngreso,
    required this.precioCompra, required this.precioObjetivo, required this.estado,
    this.version, this.km, this.observaciones,
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
  const GastoSemilla({required this.codigo, required this.fecha, required this.categoria, required this.descripcion, required this.importe});
  final String codigo, categoria;
  final String? descripcion;
  final DateTime fecha;
  final double importe;
}

class PrecioSemilla {
  const PrecioSemilla({required this.codigo, required this.fecha, required this.precio, this.motivo});
  final String codigo;
  final DateTime fecha;
  final double precio;
  final String? motivo;
}

class VentaSemilla {
  const VentaSemilla({required this.codigo, required this.fecha, required this.precioFinal, required this.gastosFinales, this.cliente, this.vendedor});
  final String codigo;
  final DateTime fecha;
  final double precioFinal, gastosFinales;
  final String? cliente, vendedor;
}

class InteresadoSemilla {
  const InteresadoSemilla({required this.codigo, required this.nombre, this.telefono, this.fecha, this.notas});
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
${vehiculos}
  ];

  static final gastos = <GastoSemilla>[
${gastos}
  ];

  static final precios = <PrecioSemilla>[
${precios}
  ];

  static final ventas = <VentaSemilla>[
${ventas}
  ];

  static final interesados = <InteresadoSemilla>[
${interesados}
  ];

  /// Serie IPC del INDEC. El primer mes es la base (indice 100).
  static final ipc = <IpcSemilla>[
${ipc}
  ];
}
`;

fs.mkdirSync(fileURLToPath(new URL('../app/lib/datos/', import.meta.url)), { recursive: true });
fs.writeFileSync(SALIDA, dart);
console.log(`Generado: ${SALIDA}`);
console.log(`  ${DATA_SEED.vehiculos.length} vehiculos, ${DATA_SEED.gastos.length} gastos, ${DATA_SEED.precios.length} cambios de precio, ${DATA_SEED.ventas.length} ventas, ${DATA_SEED.interesados.length} interesados, ${DATA_SEED.config.ipcSerie.length} meses de IPC`);
