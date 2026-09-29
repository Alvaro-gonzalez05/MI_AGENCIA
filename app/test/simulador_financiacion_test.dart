import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';
import 'package:mi_agencia/funciones/simulador/pantalla_simulador.dart';
import 'package:mi_agencia/ui/componentes.dart';

/// El simulador de financiamiento.
///
/// Historia: tanda 1 (2.2) pidió poder cambiar el monto; tanda 2 (2.2) sacar
/// el anticipo. El diseño nuevo lo saca de la ficha del auto, lo pone como
/// pantalla propia y le agrega los cuatro sistemas de amortización con los
/// que trabajan las financieras.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  group('Cálculo', () {
    // Caso de control: $10.000.000 a 12 meses con TNA 36 % (3 % mensual).
    const monto = 10000000.0;

    test('francés: cuota fija, y es la del diseño', () {
      final r = Motor.financiacionPor(
        sistema: SistemaAmortizacion.frances,
        monto: monto,
        cuotas: 12,
        tna: 0.36,
      );
      expect(r.primera, closeTo(1004621, 1));
      expect(r.ultima, closeTo(r.primera, 0.01));
      expect(r.total, closeTo(12055451, 10));
      expect(r.interes, closeTo(2055451, 10));
    });

    test('alemán: arranca más alta, termina más baja y sale más barato', () {
      final a = Motor.financiacionPor(
        sistema: SistemaAmortizacion.aleman,
        monto: monto,
        cuotas: 12,
        tna: 0.36,
      );
      final f = Motor.financiacionPor(
        sistema: SistemaAmortizacion.frances,
        monto: monto,
        cuotas: 12,
        tna: 0.36,
      );
      // Capital 833.333 + interés del primer mes (300.000).
      expect(a.primera, closeTo(1133333, 1));
      expect(a.ultima, lessThan(a.primera));
      expect(a.interes, lessThan(f.interes));
    });

    test('directo: el interés se cobra sobre el capital entero', () {
      final r = Motor.financiacionPor(
        sistema: SistemaAmortizacion.directo,
        monto: monto,
        cuotas: 12,
        tna: 0.36,
      );
      // 10.000.000 × 3 % × 12 = 3.600.000 de interés.
      expect(r.interes, closeTo(3600000, 1));
      expect(r.primera, closeTo(13600000 / 12, 1));
      expect(r.primera, equals(r.ultima));
    });

    test('global: un solo pago al final', () {
      final r = Motor.financiacionPor(
        sistema: SistemaAmortizacion.global,
        monto: monto,
        cuotas: 12,
        tna: 0.36,
      );
      expect(r.primera, 0);
      expect(r.ultima, closeTo(monto * 1.03 * 1.03, 1e9)); // crece compuesto
      expect(r.total, greaterThan(monto));
      expect(r.interes, closeTo(r.total - monto, 0.01));
    });

    test('sin tasa, la cuota es el capital dividido por los meses', () {
      for (final s in SistemaAmortizacion.values) {
        final r = Motor.financiacionPor(
          sistema: s,
          monto: monto,
          cuotas: 10,
          tna: 0,
        );
        expect(r.total, closeTo(monto, 1), reason: s.name);
        expect(r.interes, closeTo(0, 1), reason: s.name);
      }
    });

    test('sin monto no divide por cero', () {
      for (final s in SistemaAmortizacion.values) {
        final r = Motor.financiacionPor(
          sistema: s,
          monto: 0,
          cuotas: 12,
          tna: 0.36,
        );
        expect(r.primera, 0);
        expect(r.total, 0);
        expect(r.primera.isNaN, isFalse);
      }
    });
  });

  group('Pantalla', () {
    Future<void> pintar(WidgetTester tester, Size tamano) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositorioProvider.overrideWithValue(_Repo())],
          child: MaterialApp(
            theme: TemaApp.claro(),
            home: const Scaffold(body: PantallaSimulador()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (donde, tamano) in [
      ('en un celular', const Size(390, 844)),
      ('en un escritorio', const Size(1440, 900)),
    ]) {
      testWidgets('tiene monto, sistemas, tasa y cuotas $donde', (
        tester,
      ) async {
        await pintar(tester, tamano);

        expect(find.text('Monto a financiar'), findsOneWidget);
        expect(find.text('Sistema de amortización'), findsOneWidget);
        for (final s in SistemaAmortizacion.values) {
          expect(find.widgetWithText(ChipSeleccion, s.etiqueta), findsOneWidget);
        }
        expect(find.text('Tasa anual (TNA)'), findsOneWidget);
        expect(find.text('Cuotas'), findsOneWidget);
        // Sin anticipo: el cliente lo pidió expresamente (tanda 2, 2.2).
        expect(find.textContaining('nticipo'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('cambiar de sistema cambia lo que se muestra', (tester) async {
      await pintar(tester, const Size(1440, 900));

      expect(find.text('Cuota mensual'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChipSeleccion, 'Alemán'));
      await tester.pumpAndSettle();

      // Con cuotas que bajan, el encabezado lo dice y aparece la última.
      expect(find.text('Primera cuota (van bajando)'), findsOneWidget);
      expect(find.textContaining('Última cuota:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el contador de cuotas no baja de una', (tester) async {
      await pintar(tester, const Size(1440, 900));

      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byTooltip('Una cuota menos'));
        await tester.pumpAndSettle();
      }
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Repo implements Repositorio {
  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'El simulador llamó a ${i.memberName}: agregalo a este falso si hace falta.',
  );
}
