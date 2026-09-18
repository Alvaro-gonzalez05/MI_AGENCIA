import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/agencias.dart';
import 'package:mi_agencia/dominio/campanas.dart';
import 'package:mi_agencia/dominio/gastos.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/motor_calculo.dart';
import 'package:mi_agencia/dominio/precios.dart';
import 'package:mi_agencia/dominio/ventas.dart';
import 'package:mi_agencia/funciones/campanas/pantalla_campanas.dart';
import 'package:mi_agencia/funciones/configuracion/pantalla_configuracion.dart';
import 'package:mi_agencia/funciones/gastos/pantalla_gastos.dart';
import 'package:mi_agencia/funciones/interesados/pantalla_interesados.dart';
import 'package:mi_agencia/funciones/inventario/pantalla_inventario.dart';
import 'package:mi_agencia/funciones/panel/pantalla_panel.dart';
import 'package:mi_agencia/funciones/precios/pantalla_precios.dart';
import 'package:mi_agencia/funciones/ventas/pantalla_ventas.dart';

/// La app con la cuenta recién abierta: cero unidades, cero de todo.
///
/// Es el primer estado que ve un cliente nuevo, y es el que más fácil se
/// rompe: los promedios dividen por cero, las barras de progreso reciben
/// NaN, las listas vacías dejan huecos raros. Y como en desarrollo siempre
/// hay datos de prueba cargados, es también el estado que menos se mira.
///
/// Estos tests abren cada pantalla sin un solo dato, en un celular angosto y
/// en un escritorio, y fallan si alguna explota o desborda.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Widget app(Widget pantalla) => ProviderScope(
    overrides: [repositorioProvider.overrideWithValue(_RepoVacio())],
    child: MaterialApp(
      theme: TemaApp.oscuro(),
      home: Scaffold(body: pantalla),
    ),
  );

  Future<void> pintar(WidgetTester tester, Widget pantalla, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(pantalla));
    await tester.pumpAndSettle();
  }

  const celular = Size(360, 780);
  const escritorio = Size(1440, 900);

  final pantallas = <String, Widget>{
    'Panel': const PantallaPanel(),
    'Inventario': const PantallaInventario(),
    'Interesados': const PantallaInteresados(),
    'Gastos': const PantallaGastos(),
    'Precios': const PantallaPrecios(),
    'Ventas': const PantallaVentas(),
    'Campañas': const PantallaCampanas(),
    'Configuración': const PantallaConfiguracion(),
  };

  for (final entrada in pantallas.entries) {
    for (final (donde, tamano) in [
      ('en un celular', celular),
      ('en un escritorio', escritorio),
    ]) {
      testWidgets('${entrada.key} se abre sin datos $donde', (tester) async {
        await pintar(tester, entrada.value, tamano);
        // pumpAndSettle ya habria tirado la excepcion; llegar hasta aca con
        // algo dibujado es la afirmacion.
        expect(tester.takeException(), isNull);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('los totales de una agencia vacía son cero, no NaN', (
    tester,
  ) async {
    final r = Motor.resumen(const []);

    expect(r.unidadesEnStock, 0);
    expect(r.capitalInmovilizado, 0);
    // Un promedio sobre cero unidades es 0/0. Si eso llegara a la pantalla,
    // el usuario veria "NaN%" el primer dia.
    expect(r.diasPromedioStock, 0);
    expect(r.margenPromedio, 0);
    expect(r.margenPromedio.isNaN, isFalse);
    expect(r.diasPromedioStock.isNaN, isFalse);
  });

  testWidgets('Configuración deja poner el nombre de la agencia', (
    tester,
  ) async {
    await pintar(tester, const PantallaConfiguracion(), escritorio);

    expect(find.text('Datos de la agencia'), findsOneWidget);
    // Es lo primero que hay que cargar en una cuenta nueva: sin esto, la app
    // y los informes salen con el nombre que puso quien creo la cuenta.
    expect(find.text('Nombre'), findsOneWidget);
  });

  for (final (nombre, pantalla, accion) in [
    ('Gastos', const PantallaGastos(), 'Cargar un gasto'),
    ('Precios', const PantallaPrecios(), 'Cambiar un precio'),
    ('Ventas', const PantallaVentas(), 'Registrar una venta'),
    ('Campañas', const PantallaCampanas(), 'Armar una campaña'),
  ]) {
    testWidgets('$nombre vacío ofrece una sola acción de alta', (tester) async {
      await pintar(tester, pantalla, escritorio);

      expect(find.widgetWithText(FilledButton, accion), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  }
}

/// Todo vacío, como una cuenta recién creada.
class _RepoVacio implements Repositorio {
  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => const [];

  @override
  Future<List<Interesado>> interesados() async => const [];

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async => const [];

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async =>
      const [];

  @override
  Future<List<Venta>> ventas() async => const [];

  @override
  Future<List<Campana>> campanas() async => const [];

  @override
  Future<int> destinatariosPosibles() async => 0;

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<String> siguienteCodigo() async => 'V001';

  @override
  Future<Agencia?> miAgencia() async => Agencia(
    id: 'a1',
    nombre: 'Mi Agencia',
    slug: 'mi-agencia',
    activa: true,
    plan: 'basico',
    creadaEl: DateTime(2026, 9, 13),
  );

  @override
  Future<List<Agencia>> agencias() async => const [];

  @override
  Future<List<Invitacion>> invitacionesPendientes() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'Una pantalla vacia llamo a ${i.memberName}. Si de verdad lo necesita '
    'para dibujarse sin datos, agregalo a este falso.',
  );
}
