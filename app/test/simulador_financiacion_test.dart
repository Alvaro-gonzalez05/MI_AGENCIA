import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/gastos.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';
import 'package:mi_agencia/dominio/precios.dart';
import 'package:mi_agencia/funciones/inventario/pantalla_ficha.dart';

/// El simulador de financiación con anticipo (checklist del cliente, 2.2).
///
/// Antes calculaba siempre sobre el 100% del precio publicado, y casi nadie
/// financia el auto entero: lo normal es que el comprador entregue algo.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Future<void> pintar(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositorioProvider.overrideWithValue(_Repo())],
        child: MaterialApp(
          theme: TemaApp.oscuro(),
          home: const Scaffold(body: PantallaFicha(id: 'v-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Deja algo a la vista. La ficha tiene varias listas (las tarjetas, y los
  /// chips en horizontal), asi que no sirve pedir "la" scrollable.
  Future<void> mostrar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  /// Baja hasta el simulador y devuelve su campo de monto.
  Future<Finder> montoDelSimulador(WidgetTester tester) async {
    await mostrar(tester, find.text('Monto a financiar'));
    return find.widgetWithText(TextFormField, '20000000');
  }

  group('Cálculo', () {
    test('financiar menos baja la cuota', () {
      final entero = Motor.financiacion(
        monto: 20000000,
        cuotas: 12,
        tasaMensual: 0.06,
      );
      final conAnticipo = Motor.financiacion(
        monto: 14000000,
        cuotas: 12,
        tasaMensual: 0.06,
      );
      expect(conAnticipo.cuota, lessThan(entero.cuota));
      // 30% menos financiado, 30% menos de cuota: el interés es directo.
      expect(conAnticipo.cuota, closeTo(entero.cuota * 0.7, 1));
    });

    test('sin monto no divide por cero', () {
      final r = Motor.financiacion(monto: 0, cuotas: 12, tasaMensual: 0.06);
      expect(r.cuota, 0);
      expect(r.cuota.isNaN, isFalse);
    });
  });

  group('Pantalla', () {
    for (final (donde, tamano) in [
      ('en un celular', const Size(360, 780)),
      ('en un escritorio', const Size(1440, 900)),
    ]) {
      testWidgets('el simulador tiene monto y anticipo $donde', (tester) async {
        await pintar(tester, tamano);
        await montoDelSimulador(tester);

        expect(find.text('Monto a financiar'), findsOneWidget);
        expect(find.text('Anticipo del comprador'), findsOneWidget);
        expect(find.text('Sin anticipo'), findsOneWidget);
        expect(find.text('30% de anticipo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('arranca financiando el precio publicado, sin anticipo', (
      tester,
    ) async {
      await pintar(tester, const Size(1440, 900));
      final campo = await montoDelSimulador(tester);
      expect(campo, findsOneWidget);
      // Anticipo en cero.
      expect(find.text(r'$0'), findsWidgets);
    });

    testWidgets('el atajo de 30% deja el anticipo y el monto que corresponde', (
      tester,
    ) async {
      await pintar(tester, const Size(1440, 900));
      await montoDelSimulador(tester);

      await mostrar(tester, find.text('30% de anticipo'));
      await tester.tap(find.text('30% de anticipo'));
      await tester.pumpAndSettle();

      // 30% de 20.000.000 = 6.000.000 de anticipo; se financian 14.000.000.
      expect(find.widgetWithText(TextFormField, '14000000'), findsOneWidget);
      expect(find.text(r'$6.000.000'), findsWidgets);
      // Y aparece el total con anticipo, que es lo que paga el comprador.
      expect(find.text('Total con anticipo'), findsOneWidget);
    });

    testWidgets('no deja financiar más que el precio publicado', (
      tester,
    ) async {
      await pintar(tester, const Size(1440, 900));
      final campo = await montoDelSimulador(tester);

      await tester.enterText(campo, '99000000');
      await tester.pumpAndSettle();

      // Queda acotado al precio: el anticipo nunca puede ser negativo.
      expect(find.text(r'$0'), findsWidgets);
      expect(find.textContaining('-'), findsNothing);
    });
  });
}

final _vehiculo = VehiculoInventario(
  id: 'v-1',
  codigo: 'V001',
  marca: 'Toyota',
  modelo: 'Corolla',
  anio: 2022,
  estado: EstadoVehiculo.enStock,
  alerta: AlertaRotacion.normal,
  fechaIngreso: DateTime(2026, 9, 1),
  fechaCompra: DateTime(2026, 9, 1),
  precioCompra: 16000000,
  precioObjetivo: 20000000,
  costoTotal: 16000000,
  gastosAcum: 0,
  cantidadGastos: 0,
  diasEnStock: 18,
  precioActual: 20000000,
  capitalInmovilizado: 16000000,
  gananciaEstimada: 4000000,
  margenActual: .2,
  margenEsperado: .2,
  precioParaMargenObjetivo: 22857142,
  precioSugerido: 22857142,
  costoTotalHoy: 16000000,
  gananciaRealIpc: 4000000,
  gananciaRealUsd: 2666,
);

class _Repo implements Repositorio {
  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => [_vehiculo];

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async => const [];

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'La ficha llamó a ${i.memberName}: agregalo a este falso si hace falta.',
  );
}
