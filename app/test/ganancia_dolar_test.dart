import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/datos/datos_demo.dart';
import 'package:mi_agencia/datos/dolar_demo.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';

/// Ganancia real ajustada por dólar oficial, anclada en la fecha de compra
/// (checklist del cliente, tanda 2, punto 2.1).
///
/// La fuente de verdad es la vista `v_inventario` (migración 0020, probada
/// en tests/dolar.mjs); esto verifica que el motor del modo demo diga lo
/// mismo con el ejemplo del cliente.
void main() {
  final corolla = VehiculoSemilla(
    codigo: 'X001',
    marca: 'Toyota',
    modelo: 'Corolla',
    anio: 2020,
    fechaCompra: DateTime.utc(2024, 5, 10),
    fechaIngreso: DateTime.utc(2025, 1, 15),
    precioCompra: 8500000,
    precioObjetivo: 14500000,
    estado: EstadoVehiculo.enStock,
  );
  final gasto = GastoSemilla(
    codigo: 'X001',
    fecha: DateTime.utc(2025, 1, 20),
    categoria: 'service',
    descripcion: null,
    importe: 600000,
  );
  final venta = VentaSemilla(
    codigo: 'X001',
    fecha: DateTime.utc(2026, 9, 18),
    precioFinal: 14500000,
    gastosFinales: 0,
  );

  VehiculoInventario calcular({bool vendido = true}) => Motor.inventario(
    extras: [corolla],
    gastosExtra: [gasto],
    ventasExtra: vendido ? [venta] : const [],
  ).firstWhere((v) => v.codigo == 'X001');

  test('la cotización toma el último día hábil', () {
    expect(DolarDemo.en(DateTime(2024, 5, 10)), 901.5);
    expect(DolarDemo.en(DateTime(2024, 5, 12)), 901.5); // domingo
    expect(DolarDemo.en(DateTime(2025, 1, 20)), 1066);
    expect(DolarDemo.en(DateTime(2026, 9, 18)), 1535);
  });

  test('el Corolla del cliente: ganancia real −\$837.078 (−5,8 %)', () {
    final v = calcular();
    // (8.500.000 / 901,5 + 600.000 / 1.066) × 1.535
    expect(v.costoTotalHoy, closeTo(15337078, 1));
    expect(v.gananciaRealIpc, closeTo(-837078, 1));
    expect(v.gananciaRealIpc / v.precioFinal!, closeTo(-0.0577, 0.0001));
    expect(v.gananciaRealUsd, closeTo(-837078 / 1535, 0.01));
  });

  test(
    'anclado en la fecha de ingreso habría dado +\$1.344.454 (el error)',
    () {
      // La cuenta vieja, para dejar escrito contra qué se corrigió.
      const errado = 14500000 - (8500000 / 1061.5 + 600000 / 1066) * 1535;
      expect(errado, closeTo(1344454, 1));
      expect(calcular().gananciaRealIpc, isNot(closeTo(errado, 1000)));
    },
  );

  test('los días en stock siguen contando desde el ingreso', () {
    expect(calcular().diasEnStock, 611);
  });

  test('la nominal no cambia', () {
    final v = calcular();
    expect(v.costoTotal, 9100000);
  });
}
