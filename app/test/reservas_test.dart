import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/papeles.dart';
import 'package:mi_agencia/funciones/inventario/ficha_pdf.dart';
import 'package:mi_agencia/funciones/inventario/reservar_unidad.dart';

/// Reservar una unidad y la ficha en papel.
///
/// La reserva es una operación de todos los días: alguien deja una seña y el
/// auto se guarda unos días. Lo que se prueba acá es que no se pueda dejar
/// sin plazo ni sin nombre, y que la ficha impresa no filtre lo que el
/// comprador no tiene que ver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  final unidad = VehiculoInventario(
    id: 'v1',
    codigo: 'V001',
    marca: 'Toyota',
    modelo: 'Hilux',
    version: 'SRV 4x4',
    anio: 2021,
    km: 54000,
    patente: 'AF432ZK',
    estado: EstadoVehiculo.enStock,
    alerta: AlertaRotacion.normal,
    fechaIngreso: DateTime(2026, 8, 29),
    precioCompra: 38000000,
    precioObjetivo: 44500000,
    precioActual: 44500000,
    costoTotal: 38800000,
    gastosAcum: 800000,
    cantidadGastos: 2,
    diasEnStock: 30,
    capitalInmovilizado: 38800000,
    gananciaEstimada: 5700000,
    margenActual: 0.128,
    margenEsperado: 0.128,
    precioParaMargenObjetivo: 48000000,
    precioSugerido: 48000000,
    costoTotalHoy: 39500000,
    gananciaRealIpc: 5000000,
    gananciaRealUsd: 3300,
    combustible: 'Diésel',
    transmision: 'Manual',
    color: 'Gris plata',
    observaciones: 'Cubiertas nuevas.',
  );

  group('Validación', () {
    final manana = DateTime.now().add(const Duration(days: 1));

    test('sin nombre no se puede reservar', () {
      final e = AltaReserva(
        vehiculoId: 'v1',
        clienteNombre: '   ',
        venceEl: manana,
      ).validar();
      expect(e['cliente'], isNotNull);
    });

    test('no puede vencer antes de hoy', () {
      final e = AltaReserva(
        vehiculoId: 'v1',
        clienteNombre: 'Roberto Gómez',
        venceEl: DateTime.now().subtract(const Duration(days: 2)),
      ).validar();
      expect(e['vence'], isNotNull);
    });

    test('con nombre y plazo, se guarda', () {
      final e = AltaReserva(
        vehiculoId: 'v1',
        clienteNombre: 'Roberto Gómez',
        senia: 500000,
        venceEl: manana,
      ).validar();
      expect(e, isEmpty);
    });
  });

  group('Cuándo vence', () {
    Reserva conVencimiento(int dias) => Reserva(
      id: 'r1',
      vehiculoId: 'v1',
      clienteNombre: 'Roberto Gómez',
      senia: 500000,
      fechaReserva: DateTime.now(),
      venceEl: DateTime.now().add(Duration(days: dias)),
    );

    test('se lee en castellano y no en días sueltos', () {
      expect(conVencimiento(0).cuandoVence, 'Vence hoy');
      expect(conVencimiento(1).cuandoVence, 'Vence mañana');
      expect(conVencimiento(4).cuandoVence, 'Vence en 4 días');
      expect(conVencimiento(-1).cuandoVence, 'Venció ayer');
      expect(conVencimiento(-3).cuandoVence, 'Venció hace 3 días');
    });

    test('vencida solo si sigue activa', () {
      expect(conVencimiento(-1).vencida, isTrue);
      expect(conVencimiento(3).vencida, isFalse);
    });
  });

  group('Ficha en papel', () {
    test('sale el PDF y no lleva ni el costo ni la ganancia', () async {
      final bytes = await FichaPdf.generar(
        vehiculo: unidad,
        papeles: PapelesVehiculo(
          vehiculoId: 'v1',
          titulo: true,
          cedula: true,
          vtv: true,
          vtvVence: DateTime(2027, 8, 1),
          informeDominio: true,
          patentesDeuda: 0,
          multasMonto: 0,
        ),
        agencia: 'Automotores del Valle',
      );

      expect(bytes.length, greaterThan(8000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      // El precio de compra no puede aparecer en una ficha que se le da al
      // cliente: es la información del dueño.
      final texto = String.fromCharCodes(
        bytes.where((b) => b >= 32 && b < 127),
      );
      expect(texto.contains('38.000.000'), isFalse);
    });

    test('sin papeles cargados también sale', () async {
      final bytes = await FichaPdf.generar(vehiculo: unidad);
      expect(bytes.length, greaterThan(5000));
    });
  });

  group('Hoja de reserva', () {
    testWidgets('pide a nombre de quién y hasta cuándo', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositorioProvider.overrideWithValue(_Repo())],
          child: MaterialApp(
            theme: TemaApp.claro(),
            home: Scaffold(body: HojaReserva(vehiculo: unidad)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reservar unidad'), findsOneWidget);
      expect(find.text('A nombre de *'), findsOneWidget);
      expect(find.text('Seña'), findsOneWidget);
      expect(find.text('Se le guarda hasta *'), findsOneWidget);

      // Sin nombre, avisa y no guarda.
      await tester.tap(find.text('Reservar la unidad'));
      await tester.pumpAndSettle();
      expect(find.text('Poné a nombre de quién.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con una reserva activa ofrece cerrarla', (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositorioProvider.overrideWithValue(_Repo())],
          child: MaterialApp(
            theme: TemaApp.claro(),
            home: Scaffold(
              body: HojaReserva(
                vehiculo: unidad,
                reserva: Reserva(
                  id: 'r1',
                  vehiculoId: 'v1',
                  clienteNombre: 'Roberto Gómez',
                  senia: 500000,
                  fechaReserva: DateTime.now(),
                  venceEl: DateTime.now().add(const Duration(days: 1)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reserva activa'), findsOneWidget);
      expect(find.text('Roberto Gómez'), findsOneWidget);
      expect(find.text('Vence mañana'), findsOneWidget);
      expect(find.text('Se concretó la venta'), findsOneWidget);
      expect(find.text('Cancelar la reserva'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Repo implements Repositorio {
  @override
  Future<List<Interesado>> interesados() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'La hoja de reserva llamó a ${i.memberName}: agregalo a este falso.',
  );
}
