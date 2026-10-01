import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/dominio/tareas.dart';
import 'package:mi_agencia/funciones/panel/nueva_tarea.dart';

/// La agenda: "Nueva tarea" y cómo se lee cada tarea en el Inicio.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Tarea tareaPara(int dias) => Tarea(
    id: 't1',
    titulo: 'Llamar a Juan',
    tipo: TipoTarea.llamar,
    venceEl: DateTime.now().add(Duration(days: dias)),
  );

  group('Cuándo', () {
    test('se lee en castellano', () {
      expect(tareaPara(0).cuando, 'Para hoy');
      expect(tareaPara(1).cuando, 'Para mañana');
      expect(tareaPara(5).cuando, 'En 5 días');
      expect(tareaPara(-1).cuando, 'Era ayer');
      expect(tareaPara(-4).cuando, 'Hace 4 días');
    });

    test('vencida solo si sigue pendiente', () {
      expect(tareaPara(-2).vencida, isTrue);
      expect(tareaPara(2).vencida, isFalse);
      expect(
        Tarea(
          id: 't2',
          titulo: 'Ya la hice',
          venceEl: DateTime.now().subtract(const Duration(days: 3)),
          estado: EstadoTarea.hecha,
        ).vencida,
        isFalse,
      );
    });
  });

  group('Validación', () {
    test('sin título no se guarda', () {
      final e = AltaTarea(titulo: '  ', venceEl: DateTime.now()).validar();
      expect(e['titulo'], isNotNull);
    });

    test('con título alcanza: el resto es opcional', () {
      final e = AltaTarea(
        titulo: 'Pasar por la gestoría',
        venceEl: DateTime.now(),
      ).validar();
      expect(e, isEmpty);
    });
  });

  group('Hoja de nueva tarea', () {
    Future<void> pintar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(620, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositorioProvider.overrideWithValue(_Repo())],
          child: MaterialApp(
            theme: TemaApp.claro(),
            home: const Scaffold(body: HojaNuevaTarea()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tiene las cinco preguntas del diseño', (tester) async {
      await pintar(tester);

      expect(find.text('Nueva tarea'), findsOneWidget);
      expect(find.text('1. ¿Qué tenés que hacer?'), findsOneWidget);
      expect(find.text('2. ¿Con quién?'), findsOneWidget);
      expect(find.text('3. ¿Sobre qué auto?'), findsOneWidget);
      expect(find.text('4. ¿Cuándo?'), findsOneWidget);
      expect(find.text('5. ¿Se repite?'), findsOneWidget);

      // Los seis tipos de tarea.
      for (final t in TipoTarea.values) {
        expect(find.text(t.etiqueta), findsWidgets, reason: t.name);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin título avisa y no guarda', (tester) async {
      await pintar(tester);

      await tester.tap(find.text('Guardar tarea'));
      await tester.pumpAndSettle();

      expect(find.text('Poné qué hay que hacer.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('al elegir que se repite, lo explica', (tester) async {
      await pintar(tester);

      await tester.ensureVisible(find.text('Cada mes'));
      await tester.tap(find.text('Cada mes'));
      await tester.pumpAndSettle();

      expect(
        find.text('Al marcarla hecha se crea sola la siguiente.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _Repo implements Repositorio {
  @override
  Future<List<Interesado>> interesados() async => const [];

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('La hoja llamó a ${i.memberName}.');
}
