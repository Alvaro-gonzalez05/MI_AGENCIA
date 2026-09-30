@Tags(['capturas'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/dominio/agencias.dart';
import 'package:mi_agencia/dominio/gastos.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/precios.dart';
import 'package:mi_agencia/dominio/ventas.dart';
import 'package:mi_agencia/funciones/interesados/pantalla_interesados.dart';
import 'package:mi_agencia/funciones/inventario/pantalla_inventario.dart';
import 'package:mi_agencia/funciones/inventario/pantalla_ficha.dart';
import 'package:mi_agencia/funciones/panel/pantalla_panel.dart';
import 'package:mi_agencia/funciones/estadisticas/pantalla_estadisticas.dart';
import 'package:mi_agencia/main.dart';
import 'package:mi_agencia/funciones/simulador/pantalla_simulador.dart';

/// Capturas para revisar el diseno a ojo. No es una prueba: se corre a mano
/// con `flutter test --update-goldens test/capturas_tmp_test.dart`.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_AR');
    for (final familia in {
      'Atkinson': [
        'AtkinsonHyperlegibleNext-Regular.ttf',
        'AtkinsonHyperlegibleNext-SemiBold.ttf',
        'AtkinsonHyperlegibleNext-Bold.ttf',
      ],
      'WorkSans': [
        'WorkSans-Regular.ttf',
        'WorkSans-SemiBold.ttf',
        'WorkSans-Bold.ttf',
      ],
      'IBMPlexMono': [
        'IBMPlexMono-Regular.ttf',
        'IBMPlexMono-Medium.ttf',
        'IBMPlexMono-SemiBold.ttf',
      ],
    }.entries) {
      final cargador = FontLoader(familia.key);
      for (final archivo in familia.value) {
        cargador.addFont(
          File('assets/fuentes/$archivo')
              .readAsBytes()
              .then((b) => ByteData.view(b.buffer)),
        );
      }
      await cargador.load();
    }
  });

  Future<void> capturar(
    WidgetTester tester,
    String nombre,
    Widget pantalla, {
    Size tamano = const Size(1280, 1000),
    bool oscuro = false,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositorioProvider.overrideWithValue(_Repo())],
        child: MaterialApp(
          theme: oscuro ? TemaApp.oscuro() : TemaApp.claro(),
          home: Scaffold(body: pantalla),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('capturas/$nombre.png'),
    );
  }

  /// La app entera (con su shell), para las capturas que necesitan la barra
  /// de abajo o las hojas que suben desde ella.
  Future<void> capturarApp(
    WidgetTester tester,
    String nombre,
    Size tamano,
    Future<void> Function(WidgetTester) accion,
  ) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MiAgencia()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.enterText(find.byType(TextFormField).last, 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await accion(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('capturas/$nombre.png'),
    );
  }

  testWidgets('mas opciones', (t) async {
    await capturarApp(t, 'mas-opciones', const Size(430, 1400), (t) async {
      await t.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await t.pumpAndSettle();
    });
  });

  testWidgets('hoja cargar', (t) async {
    await capturarApp(t, 'hoja-cargar', const Size(430, 900), (t) async {
      await t.tap(find.byIcon(Icons.add_circle_outline_rounded).first);
      await t.pumpAndSettle();
    });
  });

  testWidgets('clientes escritorio', (t) async {
    await capturar(t, 'clientes-escritorio', const PantallaInteresados());
  });
  testWidgets('clientes celular', (t) async {
    await capturar(
      t,
      'clientes-celular',
      const PantallaInteresados(),
      tamano: const Size(390, 844),
    );
  });
  testWidgets('clientes oscuro', (t) async {
    await capturar(
      t,
      'clientes-oscuro',
      const PantallaInteresados(),
      tamano: const Size(390, 844),
      oscuro: true,
    );
  });
  testWidgets('inventario', (t) async {
    await capturar(t, 'inventario', const PantallaInventario());
  });
  testWidgets('panel', (t) async {
    await capturar(
      t,
      'panel',
      const PantallaPanel(),
      tamano: const Size(1280, 1800),
    );
  });
  testWidgets('panel celular', (t) async {
    await capturar(
      t,
      'panel-celular',
      const PantallaPanel(),
      tamano: const Size(390, 1600),
    );
  });
  testWidgets('ficha', (t) async {
    await capturar(
      t,
      'ficha',
      const PantallaFicha(id: 'v0'),
      tamano: const Size(1280, 1800),
    );
  });
  testWidgets('ficha celular', (t) async {
    await capturar(
      t,
      'ficha-celular',
      const PantallaFicha(id: 'v0'),
      tamano: const Size(390, 1500),
    );
  });
  testWidgets('simulador', (t) async {
    await capturar(t, 'simulador', const PantallaSimulador());
  });
  testWidgets('estadisticas', (t) async {
    await capturar(
      t,
      'estadisticas',
      const PantallaEstadisticas(),
      tamano: const Size(1280, 1600),
    );
  });
}

final _hoy = DateTime(2026, 9, 28);

Interesado _persona({
  required String id,
  required String nombre,
  required SemaforoCrediticio semaforo,
  String? estado,
  String? telefono,
  String? localidad,
  String? auto,
}) => Interesado(
  id: id,
  clienteId: 'c-$id',
  nombre: nombre,
  telefono: telefono,
  localidad: localidad,
  cuit: '20-30123456-7',
  estadoOportunidad: estado ?? 'negociacion',
  vehiculoCodigo: auto == null ? null : 'V00$id',
  vehiculoTitulo: auto,
  fecha: _hoy.subtract(Duration(days: int.parse(id) * 9)),
  consulta: semaforo == SemaforoCrediticio.sinDatos
      ? null
      : ConsultaBcra(
          cuit: '20301234567',
          consultadoEl: _hoy,
          entidades: semaforo == SemaforoCrediticio.verde
              ? const []
              : const [
                  EntidadBcra(
                    entidad: 'BANCO DE PRUEBA',
                    situacion: 4,
                    montoMiles: 3200,
                  ),
                ],
          situacionMaxima: semaforo == SemaforoCrediticio.verde ? 1 : 4,
          totalDeudaMiles: semaforo == SemaforoCrediticio.verde ? 0 : 3200,
        ),
);

class _Repo implements Repositorio {
  @override
  Future<List<Interesado>> interesados() async => [
    _persona(
      id: '1',
      nombre: 'Juan Pérez',
      semaforo: SemaforoCrediticio.verde,
      estado: 'ganado',
      telefono: '261 555-1234',
      localidad: 'Godoy Cruz',
      auto: 'Toyota Hilux SRV 2021',
    ),
    _persona(
      id: '2',
      nombre: 'Laura Giménez',
      semaforo: SemaforoCrediticio.rojo,
      telefono: '261 444-9876',
      localidad: 'Maipú',
      auto: 'Ford Ranger XLT 2019',
    ),
    _persona(
      id: '3',
      nombre: 'Carlos Vallejos',
      semaforo: SemaforoCrediticio.sinDatos,
      telefono: '261 300-1122',
      localidad: 'Luján de Cuyo',
    ),
  ];

  @override
  Future<ConfigAgencia> config() async => const ConfigAgencia();

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => [
    for (final (i, datos) in [
      (
        'Toyota',
        'Hilux SRV 4x4',
        2021,
        38000000.0,
        44500000.0,
        AlertaRotacion.normal,
      ),
      (
        'Ford',
        'Ranger XLT',
        2019,
        26000000.0,
        31000000.0,
        AlertaRotacion.atencion,
      ),
      (
        'Volkswagen',
        'Amarok Comfortline',
        2018,
        22000000.0,
        24500000.0,
        AlertaRotacion.critico,
      ),
    ].indexed)
      VehiculoInventario(
        id: 'v$i',
        codigo: 'V00${i + 1}',
        marca: datos.$1,
        modelo: datos.$2,
        anio: datos.$3,
        estado: EstadoVehiculo.enStock,
        alerta: datos.$6,
        fechaIngreso: _hoy.subtract(Duration(days: 30 * (i + 1))),
        fechaCompra: _hoy.subtract(Duration(days: 40 * (i + 1))),
        precioCompra: datos.$4,
        precioObjetivo: datos.$5,
        costoTotal: datos.$4 + 800000,
        gastosAcum: 800000,
        cantidadGastos: 2,
        diasEnStock: 30 * (i + 1),
        precioActual: datos.$5,
        capitalInmovilizado: datos.$4 + 800000,
        gananciaEstimada: datos.$5 - datos.$4 - 800000,
        margenActual: (datos.$5 - datos.$4 - 800000) / datos.$5,
        margenEsperado: 0.2,
        precioParaMargenObjetivo: datos.$5 * 1.1,
        precioSugerido: datos.$5 * 1.1,
        costoTotalHoy: datos.$4 + 1500000,
        gananciaRealIpc: datos.$5 - datos.$4 - 1500000,
        gananciaRealUsd: (datos.$5 - datos.$4 - 1500000) / 1535,
      ),
  ];

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async => const [];

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async =>
      const [];

  @override
  Future<List<Venta>> ventas() async => [
    Venta(
      id: 'vt1',
      vehiculoId: 'v9',
      fechaVenta: _hoy.subtract(const Duration(days: 12)),
      precioFinal: 28000000,
      gastosFinales: 250000,
      vehiculoCodigo: 'V009',
      vehiculoTitulo: 'Toyota Etios XLS',
      costoTotal: 24000000,
      costoTotalHoy: 24500000,
      diasEnStock: 45,
      tipoCambio: 1535,
    ),
    Venta(
      id: 'vt2',
      vehiculoId: 'v8',
      fechaVenta: _hoy.subtract(const Duration(days: 47)),
      precioFinal: 19500000,
      gastosFinales: 120000,
      vehiculoCodigo: 'V008',
      vehiculoTitulo: 'Fiat Cronos Drive',
      costoTotal: 17000000,
      costoTotalHoy: 17800000,
      diasEnStock: 62,
      tipoCambio: 1510,
    ),
  ];

  @override
  Future<Agencia?> miAgencia() async => const Agencia(
    id: 'ag',
    nombre: 'Automotores del Valle',
    slug: 'del-valle',
    activa: true,
    plan: 'pro',
  );

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}
