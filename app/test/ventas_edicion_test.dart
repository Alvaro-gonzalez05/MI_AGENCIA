import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/ventas.dart';
import 'package:mi_agencia/funciones/ventas/formulario_venta.dart';
import 'package:mi_agencia/funciones/ventas/pantalla_ventas.dart';

/// Corregir y anular una venta (checklist del cliente, punto 1.2).
///
/// Antes una venta cargada con un dato mal puesto quedaba así para siempre y
/// arrastraba el error a la ganancia real y a los históricos, y una venta que
/// se caía no tenía cómo deshacerse.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  late _Repo repo;
  setUp(() => repo = _Repo());

  Future<void> pintar(
    WidgetTester tester, {
    Size tamano = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositorioProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: TemaApp.oscuro(),
          home: const Scaffold(body: PantallaVentas()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> abrirMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Acciones de la venta'));
    await tester.pumpAndSettle();
  }

  group('Modelo', () {
    test('una venta cargada se precarga entera para corregirla', () {
      final a = AltaVenta.desde(_venta);
      expect(a.esEdicion, isTrue);
      expect(a.id, 'venta-1');
      expect(a.precioFinal, 25000000);
      expect(a.gastosFinales, 300000);
      expect(a.formaPago, FormaPago.financiacionPropia);
      expect(a.cuotas, 12);
      expect(a.observaciones, 'Cliente de prueba');
    });

    test('corregir un campo conserva el id de la venta', () {
      final a = AltaVenta.desde(_venta).copiar(precioFinal: 24000000);
      expect(a.id, 'venta-1');
      expect(a.precioFinal, 24000000);
    });

    test('una venta nueva no es edición', () {
      expect(const AltaVenta().esEdicion, isFalse);
    });
  });

  group('Pantalla', () {
    for (final (nombre, tamano) in [
      ('en un celular', const Size(360, 780)),
      ('en un escritorio', const Size(1440, 900)),
    ]) {
      testWidgets('la venta tiene sus dos acciones $nombre', (tester) async {
        await pintar(tester, tamano: tamano);
        await abrirMenu(tester);
        expect(find.text('Corregir datos'), findsOneWidget);
        expect(find.text('Anular venta'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'corregir abre el formulario precargado y guarda sobre la misma venta',
      (tester) async {
        await pintar(tester);
        await abrirMenu(tester);
        await tester.tap(find.text('Corregir datos'));
        await tester.pumpAndSettle();

        expect(find.text('Corregir venta'), findsOneWidget);
        // El precio viene cargado: no hay que reescribir la venta entera.
        expect(find.widgetWithText(TextFormField, '25000000'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, '25000000'),
          '24500000',
        );
        // Como quien toca "listo" en el teclado. Sin esto el campo del precio
        // queda enfocado, y Flutter vuelve a subir la lista para mantenerlo a
        // la vista: el scroll de abajo se deshacía solo.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        // El botón está al fondo del formulario. Se baja la lista del
        // formulario hasta el final: scrollUntilVisible no sirve acá, porque
        // el botón ya está construido (aunque fuera de pantalla) y da el
        // trabajo por hecho sin mover nada.
        final lista = find
            .descendant(
              of: find.byType(FormularioVenta),
              matching: find.byType(Scrollable),
            )
            .first;
        final posicion = tester.state<ScrollableState>(lista).position;
        posicion.jumpTo(posicion.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar corrección'));
        await tester.pumpAndSettle();

        expect(
          repo.creadas,
          0,
          reason: 'Corregir no puede crear una venta nueva.',
        );
        expect(repo.corregidas.single.id, 'venta-1');
        expect(repo.corregidas.single.precioFinal, 24500000);
        // Lo que no se tocó queda como estaba.
        expect(repo.corregidas.single.cuotas, 12);
      },
    );

    testWidgets('anular pide confirmación y, si se cancela, no toca nada', (
      tester,
    ) async {
      await pintar(tester);
      await abrirMenu(tester);
      await tester.tap(find.text('Anular venta'));
      await tester.pumpAndSettle();

      expect(find.text('Anular la venta'), findsOneWidget);
      expect(find.textContaining('vuelve al inventario'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.anuladas, isEmpty);
    });

    testWidgets('anular confirmado borra la venta', (tester) async {
      await pintar(tester);
      await abrirMenu(tester);
      await tester.tap(find.text('Anular venta'));
      await tester.pumpAndSettle();

      // El botón del diálogo, no el ítem del menú (que ya se cerró).
      await tester.tap(find.widgetWithText(FilledButton, 'Anular venta'));
      await tester.pumpAndSettle();

      expect(repo.anuladas, ['venta-1']);
    });

    testWidgets('si no tiene permiso para anular, lo dice y no finge', (
      tester,
    ) async {
      repo.sinPermiso = true;
      await pintar(tester);
      await abrirMenu(tester);
      await tester.tap(find.text('Anular venta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Anular venta'));
      await tester.pumpAndSettle();

      expect(find.textContaining('administrador'), findsOneWidget);
      expect(find.textContaining('volvió al stock'), findsNothing);
    });
  });
}

final _venta = Venta(
  id: 'venta-1',
  vehiculoId: 'v-1',
  fechaVenta: DateTime(2026, 9, 10),
  precioFinal: 25000000,
  gastosFinales: 300000,
  formaPago: FormaPago.financiacionPropia.etiqueta,
  cuotas: 12,
  observaciones: 'Cliente de prueba',
  vehiculoCodigo: 'V001',
  vehiculoTitulo: 'Toyota Corolla',
  costoTotal: 18125000,
  costoTotalHoy: 18500000,
  diasEnStock: 9,
  tipoCambio: 1500,
);

final _vendido = VehiculoInventario(
  id: 'v-1',
  codigo: 'V001',
  marca: 'Toyota',
  modelo: 'Corolla',
  anio: 2022,
  estado: EstadoVehiculo.vendido,
  alerta: AlertaRotacion.vendido,
  fechaIngreso: DateTime(2026, 9, 1),
  fechaCompra: DateTime(2026, 9, 1),
  precioCompra: 18000000,
  precioObjetivo: 22000000,
  costoTotal: 18125000,
  gastosAcum: 125000,
  cantidadGastos: 1,
  diasEnStock: 9,
  precioActual: 22000000,
  capitalInmovilizado: 0,
  gananciaEstimada: 3875000,
  margenActual: .176,
  margenEsperado: .18,
  precioParaMargenObjetivo: 22103658,
  precioSugerido: 22103658,
  costoTotalHoy: 18500000,
  gananciaRealIpc: 6500000,
  gananciaRealUsd: 4333,
  fechaVenta: DateTime(2026, 9, 10),
  precioFinal: 25000000,
);

class _Repo implements Repositorio {
  final corregidas = <AltaVenta>[];
  final anuladas = <String>[];
  var creadas = 0;
  var sinPermiso = false;

  @override
  Future<List<Venta>> ventas() async =>
      anuladas.contains('venta-1') ? const [] : [_venta];

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => [_vendido];

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<void> crearVenta(AltaVenta v) async => creadas++;

  @override
  Future<void> actualizarVenta(AltaVenta v) async => corregidas.add(v);

  @override
  Future<void> anularVenta(String id) async {
    if (sinPermiso) {
      throw Exception(
        'Solo el dueño o un administrador de la agencia pueden anular una venta.',
      );
    }
    anuladas.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'Ventas llamó a ${i.memberName}: agregalo a este falso si hace falta.',
  );
}
