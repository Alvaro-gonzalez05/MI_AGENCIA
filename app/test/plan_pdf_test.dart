import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';
import 'package:mi_agencia/funciones/simulador/plan_pdf.dart';

/// El plan de cuotas en PDF: lo que el vendedor le deja al cliente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  test('el PDF sale con el detalle cuota por cuota', () async {
    final bytes = await PlanPdf.generar(
      sistema: SistemaAmortizacion.frances,
      monto: 10000000,
      cuotas: 12,
      tna: 0.36,
      agencia: 'Agencia del Oeste',
    );

    expect(bytes.length, greaterThan(12000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('los cuatro sistemas generan un PDF', () async {
    for (final s in SistemaAmortizacion.values) {
      final bytes = await PlanPdf.generar(
        sistema: s,
        monto: 5000000,
        cuotas: 6,
        tna: 0.72,
      );
      expect(bytes.length, greaterThan(8000), reason: s.name);
    }
  });

  test('sin monto no rompe', () async {
    final bytes = await PlanPdf.generar(
      sistema: SistemaAmortizacion.aleman,
      monto: 0,
      cuotas: 12,
      tna: 0.5,
    );
    expect(bytes.length, greaterThan(4000));
  });
}
