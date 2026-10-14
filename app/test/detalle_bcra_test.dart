import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/funciones/interesados/detalle_bcra.dart';

/// El detalle del Banco Central dentro de la ficha del cliente.
///
/// La agencia pidió ver "la mayor cantidad de datos del BCRA", y lo que
/// faltaba era esto: la historia de 24 meses abierta por entidad, como la
/// publica el Banco Central. Un 5 de hace dos años ya pagado no se negocia
/// igual que un 5 de este mes, y con el semáforo solo no se distingue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  ConsultaBcra conHistoria() => ConsultaBcra(
    cuit: '27230938607',
    consultadoEl: DateTime(2026, 9, 10),
    entidades: const [],
    situacionMax24m: 5,
    ultimoPeriodoIrregular: '202503',
    historico: [
      for (final p in const ['202607', '202606', '202605'])
        MesBcra(
          periodo: p,
          situacion: 1,
          entidades: const [
            EntidadMes(
              entidad: 'CREDITO RAPIDO S.A.',
              situacion: 1,
              montoMiles: 120,
            ),
          ],
        ),
      const MesBcra(
        periodo: '202503',
        situacion: 5,
        entidades: [
          EntidadMes(
            entidad: 'CREDITO RAPIDO S.A.',
            situacion: 5,
            montoMiles: 640,
            procesoJudicial: true,
          ),
        ],
      ),
      const MesBcra(
        periodo: '202502',
        situacion: 5,
        entidades: [
          EntidadMes(
            entidad: 'CREDITO RAPIDO S.A.',
            situacion: 5,
            montoMiles: 580,
          ),
        ],
      ),
    ],
  );

  Future<void> abrir(WidgetTester t, ConsultaBcra c) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: TemaApp.claro(),
        home: Scaffold(
          body: SingleChildScrollView(child: DetalleBcra(consulta: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('cuenta con quién fue, cuándo y por cuánto', (t) async {
    await abrir(t, conHistoria());

    expect(find.text('Historia de 24 meses'), findsOneWidget);
    expect(find.text('Situación 5'), findsOneWidget);
    expect(find.textContaining('Credito Rapido'), findsNothing);
    expect(find.textContaining('CREDITO RAPIDO S.A.'), findsWidgets);
    // Dos meses en 5, y el último fue en marzo de 2025.
    expect(find.textContaining('2 meses'), findsOneWidget);
    expect(find.textContaining('Con proceso judicial'), findsOneWidget);
    // Hoy ya no le debe: eso cambia por completo cómo se lee el rojo.
    expect(
      find.textContaining('Sin deuda con esta entidad desde abril 2025'),
      findsOneWidget,
    );
  });

  testWidgets('cada entidad abre su tabla mes por mes', (t) async {
    await abrir(t, conHistoria());

    // Arranca cerrada: cinco meses por entidad serían mucho ruido de entrada.
    expect(find.text('Período'), findsNothing);
    expect(find.textContaining('5 meses informados'), findsOneWidget);

    await t.tap(find.textContaining('5 meses informados'));
    await t.pumpAndSettle();

    expect(find.text('Período'), findsOneWidget);
    expect(find.text('mar 2025'), findsOneWidget);
    expect(find.textContaining('5 · irrecuperable'), findsWidgets);
    expect(find.text('Juicio'), findsOneWidget);
  });

  testWidgets('sin historia no dibuja nada', (t) async {
    await abrir(
      t,
      ConsultaBcra(
        cuit: '27230938607',
        consultadoEl: DateTime(2026, 9, 10),
        entidades: const [],
      ),
    );
    expect(find.text('Historia de 24 meses'), findsNothing);
  });
}
