import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/dominio/cobranzas.dart';

/// Cuotas y cobranzas: lo que decide si un cliente está al día o debe.
///
/// Los números de esta parte se los lee la agencia por teléfono al cliente
/// ("te falta la cuota 4, son $350.000"), así que tienen que cerrar exacto.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  CuotaPlan cuota({
    double importe = 100000,
    double pagado = 0,
    int diasDesdeVencimiento = 0,
  }) {
    final hoy = DateTime.now();
    return CuotaPlan(
      id: 'c1',
      planId: 'p1',
      numero: 4,
      venceEl: DateTime(
        hoy.year,
        hoy.month,
        hoy.day,
      ).subtract(Duration(days: diasDesdeVencimiento)),
      importe: importe,
      pagado: pagado,
    );
  }

  group('Una cuota', () {
    test('sin pagos, debe todo', () {
      final c = cuota();
      expect(c.saldo, 100000);
      expect(c.saldada, isFalse);
      expect(c.parcial, isFalse);
    });

    test('con un pago parcial, debe la diferencia', () {
      final c = cuota(pagado: 40000);
      expect(c.saldo, 60000);
      expect(c.parcial, isTrue);
      expect(c.saldada, isFalse);
    });

    test('pagada de más, el saldo no se va a negativo', () {
      // Pasa con los redondeos y con los intereses de mora acordados.
      final c = cuota(pagado: 105000);
      expect(c.saldo, 0);
      expect(c.saldada, isTrue);
    });

    test('vencida solo si todavía debe', () {
      expect(cuota(diasDesdeVencimiento: 12).vencida, isTrue);
      expect(cuota(diasDesdeVencimiento: 12).diasDeAtraso, 12);
      // La misma cuota, pagada, no está vencida: ya no se le reclama nada.
      expect(
        cuota(diasDesdeVencimiento: 12, pagado: 100000).vencida,
        isFalse,
      );
      expect(
        cuota(diasDesdeVencimiento: 12, pagado: 100000).diasDeAtraso,
        0,
      );
    });

    test('lo dice en castellano', () {
      expect(cuota(diasDesdeVencimiento: 1).cuando, '1 día de atraso');
      expect(cuota(diasDesdeVencimiento: 12).cuando, '12 días de atraso');
      expect(cuota(diasDesdeVencimiento: -5).cuando, 'Al día');
      expect(cuota(pagado: 100000).cuando, 'Pagada');
    });
  });

  group('El plan', () {
    PlanPago plan({
      double total = 1200000,
      double pagado = 0,
      int vencidas = 0,
    }) => PlanPago(
      id: 'p1',
      clienteNombre: 'Juan Pérez',
      montoFinanciado: 1000000,
      cantidadCuotas: 12,
      totalPlan: total,
      totalPagado: pagado,
      deuda: total - pagado,
      cuotasVencidas: vencidas,
    );

    test('el avance va de cero a uno', () {
      expect(plan().avance, 0);
      expect(plan(pagado: 600000).avance, closeTo(0.5, 0.001));
      expect(plan(pagado: 1200000).avance, 1);
      // Si entró de más, no pasa de uno: la barra no se sale.
      expect(plan(pagado: 1500000).avance, 1);
    });

    test('al día es no tener ninguna vencida', () {
      expect(plan().alDia, isTrue);
      expect(plan(vencidas: 2).alDia, isFalse);
    });

    test('se da por terminado cuando no queda deuda', () {
      expect(plan(pagado: 1200000).terminado, isTrue);
      expect(plan(pagado: 1199999.995).terminado, isTrue); // redondeo
      expect(plan(pagado: 1000000).terminado, isFalse);
    });
  });

  group('Validaciones', () {
    test('un plan necesita a quién, cuánto y en cuántas', () {
      expect(
        const AltaPlan(
          clienteNombre: '  ',
          montoFinanciado: 0,
          cantidadCuotas: 0,
        ).validar().keys,
        containsAll(['cliente', 'monto', 'cuotas']),
      );

      expect(
        const AltaPlan(
          clienteNombre: 'Juan Pérez',
          montoFinanciado: 1000000,
          cantidadCuotas: 12,
        ).validar(),
        isEmpty,
      );
    });

    test('un pago sin importe no se asienta', () {
      final e = AltaPago(
        cuotaId: 'c1',
        importe: 0,
        fecha: DateTime.now(),
      ).validar();
      expect(e['importe'], isNotNull);
    });

    test('un importe muy por encima del saldo pide confirmación', () {
      // El caso real es un cero de más: 1.000.000 en vez de 100.000.
      final e = AltaPago(
        cuotaId: 'c1',
        importe: 1000000,
        fecha: DateTime.now(),
      ).validar(saldoCuota: 100000);
      expect(e['importe'], isNotNull);
    });

    test('pagar un poco de más está bien (intereses, redondeo)', () {
      final e = AltaPago(
        cuotaId: 'c1',
        importe: 105000,
        fecha: DateTime.now(),
      ).validar(saldoCuota: 100000);
      expect(e, isEmpty);
    });
  });
}
