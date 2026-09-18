import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/gastos.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/funciones/gastos/pantalla_gastos.dart';
import 'package:mi_agencia/funciones/vehiculos/pantalla_vehiculos.dart';

void main() {
  late _RepoEliminaciones repo;

  setUpAll(() async => initializeDateFormatting('es_AR'));
  setUp(() => repo = _RepoEliminaciones());

  Widget app(Widget pantalla) => ProviderScope(
    overrides: [repositorioProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: TemaApp.oscuro(), home: pantalla),
  );

  testWidgets('dar de baja una unidad siempre exige confirmacion', (
    tester,
  ) async {
    await tester.pumpWidget(app(const PantallaVehiculos()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vehiculo-menu-v-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();

    expect(find.text('Dar de baja V001'), findsOneWidget);
    expect(repo.vehiculosEliminados, isEmpty);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.vehiculosEliminados, isEmpty);

    await tester.tap(find.byKey(const Key('vehiculo-menu-v-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar-accion')));
    await tester.pumpAndSettle();

    expect(repo.vehiculosEliminados, ['v-1']);
    expect(find.text('V001 fue dado de baja'), findsOneWidget);
  });

  testWidgets('eliminar un gasto permite cancelar y confirma al terminar', (
    tester,
  ) async {
    await tester.pumpWidget(app(const PantallaGastos()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Eliminar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminar este gasto'), findsOneWidget);
    expect(find.textContaining('125.000'), findsWidgets);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.gastosEliminados, isEmpty);

    await tester.tap(find.byTooltip('Eliminar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar-accion')));
    await tester.pumpAndSettle();

    expect(repo.gastosEliminados, ['g-1']);
    expect(find.text('Gasto eliminado'), findsOneWidget);
  });
}

class _RepoEliminaciones implements Repositorio {
  final vehiculosEliminados = <String>[];
  final gastosEliminados = <String>[];

  final _vehiculos = <VehiculoInventario>[_vehiculo];
  final _gastos = <Gasto>[_gasto];

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => _vehiculos;

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async => _gastos;

  @override
  Future<void> eliminarVehiculo(String id) async {
    vehiculosEliminados.add(id);
    _vehiculos.removeWhere((v) => v.id == id);
  }

  @override
  Future<void> eliminarGasto(String id) async {
    gastosEliminados.add(id);
    _gastos.removeWhere((g) => g.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'La prueba llamo a ${invocation.memberName} sin implementarlo.',
  );
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
  precioCompra: 18000000,
  precioObjetivo: 22000000,
  costoTotal: 18125000,
  gastosAcum: 125000,
  cantidadGastos: 1,
  diasEnStock: 15,
  precioActual: 22000000,
  capitalInmovilizado: 18125000,
  gananciaEstimada: 3875000,
  margenActual: .176,
  margenEsperado: .18,
  precioParaMargenObjetivo: 22103658,
  precioSugerido: 22103658,
  costoTotalHoy: 18125000,
  gananciaRealIpc: 3875000,
  gananciaRealUsd: 2500,
);

final _gasto = Gasto(
  id: 'g-1',
  vehiculoId: 'v-1',
  fecha: DateTime(2026, 9, 10),
  categoria: CategoriaGasto.service,
  importe: 125000,
  descripcion: 'Cambio de aceite',
  vehiculoCodigo: 'V001',
  vehiculoTitulo: 'Toyota Corolla',
);
