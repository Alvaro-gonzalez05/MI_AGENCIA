import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/core/formato.dart';
import 'package:mi_agencia/core/tema/colores.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';

void main() {
  group('Motor de cálculo', () {
    test('el margen se mide sobre el precio, no sobre el costo', () {
      // Costo 100, margen 20% => precio 125 (no 120).
      // Confundirlos es el error clásico que infla la ganancia estimada.
      expect(Motor.precioParaMargen(100, 0.20), closeTo(125, 0.001));
      expect(Motor.precioParaMargen(100, 0.50), closeTo(200, 0.001));
      expect(Motor.precioParaMargen(100, 0), closeTo(100, 0.001));
    });

    test('el redondeo siempre va hacia arriba', () {
      expect(Motor.redondearArriba(1234567, 50000), 1250000);
      expect(Motor.redondearArriba(1250000, 50000), 1250000);
      expect(Motor.redondearArriba(1250001, 50000), 1300000);
      // Paso cero no debe romper ni dividir por cero.
      expect(Motor.redondearArriba(1234, 0), 1234);
    });

    test('la financiación usa interés directo, no amortización francesa', () {
      // 1.000.000 a 12 cuotas al 6% mensual:
      // interés = 1.000.000 * 0,06 * 12 = 720.000 sobre el capital completo.
      final r = Motor.financiacion(
        monto: 1000000,
        cuotas: 12,
        tasaMensual: 0.06,
      );
      expect(r.interes, closeTo(720000, 0.01));
      expect(r.total, closeTo(1720000, 0.01));
      expect(r.cuota, closeTo(143333.33, 0.01));
    });

    test('financiación con valores inválidos devuelve cero, no NaN', () {
      expect(
        Motor.financiacion(monto: 0, cuotas: 12, tasaMensual: 0.06).cuota,
        0,
      );
      expect(
        Motor.financiacion(monto: 1000, cuotas: 0, tasaMensual: 0.06).cuota,
        0,
      );
    });

    test('el inventario de demo carga las 13 unidades del cliente', () {
      final inv = Motor.inventario();
      expect(inv.length, 13);
      expect(inv.where((v) => v.vendido).length, 2);
    });

    test('una unidad vendida no inmoviliza capital', () {
      final inv = Motor.inventario();
      for (final v in inv.where((v) => v.vendido)) {
        expect(v.capitalInmovilizado, 0);
      }
    });

    test('la ganancia real es precio menos costo ajustado por dólar', () {
      // El costo ajustado puede quedar por debajo del nominal si el dólar
      // bajó desde la compra; lo que no puede fallar es la resta.
      for (final v in Motor.inventario()) {
        final precio = v.vendido ? v.precioFinal! : v.precioActual;
        expect(v.gananciaRealIpc, closeTo(precio - v.costoTotalHoy, 0.01));
      }
    });
  });

  group('Formato', () {
    test('los montos van sin decimales', () {
      expect(Fmt.pesos(1234567.89), r'$1.234.568');
    });

    test('ausencia de dato se muestra con guion, no con cero', () {
      expect(Fmt.pesos(null), Fmt.sinDato);
      expect(Fmt.porcentaje(null), Fmt.sinDato);
      expect(Fmt.dias(null), Fmt.sinDato);
    });

    test('los porcentajes usan coma decimal', () {
      expect(Fmt.porcentaje(0.256), '25,6%');
      expect(Fmt.porcentajeConSigno(0.05), '+5,0%');
      expect(Fmt.porcentajeConSigno(-0.05), '-5,0%');
    });

    test('el formato compacto abrevia millones', () {
      expect(Fmt.pesosCompacto(264680000), r'$264,7 M');
      expect(Fmt.pesosCompacto(1500), r'$1,5 K');
    });

    test('singular y plural de días', () {
      expect(Fmt.dias(1), '1 día');
      expect(Fmt.dias(2), '2 días');
    });
  });

  group('Semáforos', () {
    test('rotación y crédito son escalas distintas', () {
      // Un descuido clásico sería reusar el mismo enum para las dos cosas.
      expect(AlertaRotacion.values.length, 5);
      expect(SemaforoCrediticio.values.length, 4);
    });

    test('cada alerta tiene color en las dos paletas', () {
      for (final a in AlertaRotacion.values) {
        expect(a.color(Paleta.oscura), isA<Color>());
        expect(a.color(Paleta.clara), isA<Color>());
      }
    });
  });
}
