import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/funciones/interesados/ficha_interesado.dart';
import 'package:mi_agencia/funciones/interesados/pantalla_interesados.dart';

/// Las pantallas de interesados, dibujadas de verdad.
///
/// Flutter no avisa de un desborde al compilar: aparece como una barra a
/// rayas en pantalla, y en este proyecto ya paso tres veces (las tarjetas del
/// panel, los chips del inventario, los estados). Estos tests pintan las dos
/// pantallas en un celular angosto y en un escritorio ancho, y fallan si algo
/// no entra.
void main() {
  /// Un repositorio que devuelve lo que le pidan sin tocar red.
  ///
  /// Se implementa a mano en vez de usar RepositorioDemo porque acá hace
  /// falta controlar exactamente que consulta trae cada interesado.
  late _RepoFalso repo;

  // Fmt formatea fechas en es_AR. Sin esto, cualquier pantalla que muestre una
  // fecha explota en los tests aunque en la app ande: main.dart lo inicializa
  // al arrancar, y un test no pasa por main.dart.
  setUpAll(() async => initializeDateFormatting('es_AR'));

  setUp(() => repo = _RepoFalso());

  Widget app(Widget pantalla) => ProviderScope(
    overrides: [repositorioProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: TemaApp.oscuro(),
      home: Scaffold(body: pantalla),
    ),
  );

  /// Dibuja a un ancho dado y devuelve el tester listo para mirar.
  Future<void> pintar(
    WidgetTester tester,
    Widget pantalla, {
    required Size tamano,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(pantalla));
    await tester.pumpAndSettle();
  }

  // Celular angosto de verdad (un Moto E mide 360) y un escritorio comun.
  const celular = Size(360, 780);
  const escritorio = Size(1440, 900);

  group('Lista de interesados', () {
    for (final (nombre, tamano) in [
      ('en un celular angosto', celular),
      ('en un escritorio ancho', escritorio),
    ]) {
      testWidgets('se dibuja sin desbordes $nombre', (tester) async {
        await pintar(tester, const PantallaInteresados(), tamano: tamano);

        expect(find.text('Semáforo crediticio'), findsOneWidget);
        // Los cuatro filtros mas "Todos".
        expect(find.textContaining('Todos ('), findsOneWidget);
        expect(find.textContaining('Apto ('), findsOneWidget);
        expect(find.textContaining('Riesgo alto ('), findsOneWidget);
      });
    }

    testWidgets('el filtro deja solo a los de ese color', (tester) async {
      await pintar(tester, const PantallaInteresados(), tamano: escritorio);

      // Arranca mostrando a los tres.
      expect(find.text('Ana Verde'), findsOneWidget);
      expect(find.text('Beto Rojo'), findsOneWidget);
      expect(find.text('Caro SinCuit'), findsOneWidget);

      await tester.tap(find.textContaining('Riesgo alto ('));
      await tester.pumpAndSettle();

      expect(find.text('Beto Rojo'), findsOneWidget);
      expect(find.text('Ana Verde'), findsNothing);
      expect(find.text('Caro SinCuit'), findsNothing);
    });

    testWidgets('dice que falta el CUIT cuando falta', (tester) async {
      await pintar(tester, const PantallaInteresados(), tamano: escritorio);
      expect(find.textContaining('Falta el CUIT'), findsOneWidget);
    });
  });

  group('Ficha del interesado', () {
    for (final (nombre, tamano) in [
      ('en un celular angosto', celular),
      ('en un escritorio ancho', escritorio),
    ]) {
      testWidgets('con deuda y cheques se dibuja sin desbordes $nombre', (
        tester,
      ) async {
        await pintar(
          tester,
          FichaInteresado(interesado: _conDeuda),
          tamano: tamano,
        );

        expect(find.text('Riesgo alto'), findsWidgets);
        expect(find.text('Detalle por entidad'), findsOneWidget);
        expect(find.text('Cheques rechazados'), findsOneWidget);
        // El desglose nombra a cada entidad.
        expect(find.text('BANCO DE PRUEBA'), findsOneWidget);
      });
    }

    testWidgets('sin consultar muestra el boton de consulta', (tester) async {
      await pintar(
        tester,
        const FichaInteresado(interesado: _sinConsultar),
        tamano: escritorio,
      );

      expect(find.text('Consultar BCRA'), findsOneWidget);
      expect(find.text('Sin consultar'), findsWidgets);
      // Sin consulta no hay informe que descargar.
      expect(find.text('Descargar informe'), findsNothing);
    });

    testWidgets('un CUIT mal tipeado no llega al BCRA', (tester) async {
      await pintar(
        tester,
        const FichaInteresado(interesado: _sinConsultar),
        tamano: escritorio,
      );

      await tester.enterText(find.byType(TextFormField), '30500003194');
      await tester.tap(find.text('Consultar BCRA'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no es un CUIT/CUIL válido'), findsOneWidget);
      expect(
        repo.consultas,
        isEmpty,
        reason:
            'Un CUIT invalido le da 404 al BCRA, y un 404 significa "sin '
            'deudas". Si la app lo manda igual, un error de tipeo pinta de '
            'verde a cualquiera.',
      );
    });

    testWidgets('un CUIT corto avisa cuantos digitos faltan', (tester) async {
      await pintar(
        tester,
        const FichaInteresado(interesado: _sinConsultar),
        tamano: escritorio,
      );

      await tester.enterText(find.byType(TextFormField), '3050000');
      await tester.tap(find.text('Consultar BCRA'));
      await tester.pumpAndSettle();

      expect(find.textContaining('escribiste 7'), findsOneWidget);
      expect(repo.consultas, isEmpty);
    });

    testWidgets('un CUIT valido si consulta y pinta el semaforo', (
      tester,
    ) async {
      await pintar(
        tester,
        const FichaInteresado(interesado: _sinConsultar),
        tamano: escritorio,
      );

      await tester.enterText(find.byType(TextFormField), '30-50000319-3');
      await tester.tap(find.text('Consultar BCRA'));
      await tester.pumpAndSettle();

      expect(repo.consultas, ['30500003193']);
      // El CUIT se guarda antes de consultar, para no perderlo si el BCRA
      // esta caido.
      expect(repo.cuitsGuardados, ['30500003193']);
      // Y despues de consultar aparece el resultado y el boton del informe.
      expect(find.text('Apto'), findsWidgets);
      expect(find.text('Descargar informe'), findsOneWidget);
    });

    testWidgets('si el BCRA falla lo dice y no rompe la pantalla', (
      tester,
    ) async {
      repo.falla = 'El BCRA no responde en este momento.';
      await pintar(
        tester,
        const FichaInteresado(interesado: _sinConsultar),
        tamano: escritorio,
      );

      await tester.enterText(find.byType(TextFormField), '30500003193');
      await tester.tap(find.text('Consultar BCRA'));
      await tester.pumpAndSettle();

      expect(find.text('El BCRA no responde en este momento.'), findsOneWidget);
      expect(find.text('Consultar BCRA'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------
// Datos de prueba
// ---------------------------------------------------------------------

final _conDeuda = Interesado(
  id: 'op-1',
  clienteId: 'cl-1',
  nombre: 'Beto Rojo',
  telefono: '2615551234',
  cuit: '27230938607',
  vehiculoCodigo: 'V007',
  vehiculoTitulo: 'Toyota Hilux SRX 4x4 automática',
  vehiculoPrecio: 42000000,
  necesitaFinanciacion: true,
  fecha: DateTime(2026, 8, 14),
  consulta: ConsultaBcra(
    cuit: '27230938607',
    consultadoEl: DateTime(2026, 9, 10),
    periodo: '202607',
    situacionMaxima: 5,
    totalDeudaMiles: 8450.75,
    diasAtrasoMax: 210,
    tieneProcesoJudicial: true,
    chequesRechazados: true,
    chequesSinPagar: 1,
    entidades: const [
      EntidadBcra(
        entidad: 'BANCO DE PRUEBA',
        situacion: 5,
        montoMiles: 6350.5,
        diasAtraso: 210,
        procesoJudicial: true,
        refinanciaciones: true,
      ),
      EntidadBcra(entidad: 'OTRO BANCO', situacion: 1, montoMiles: 2100.25),
    ],
    cheques: [
      ChequeBcra(
        numero: '00012345',
        monto: 850000,
        entidad: 'BANCO DE PRUEBA',
        fechaRechazo: DateTime(2026, 6, 3),
      ),
    ],
  ),
);

final _limpio = Interesado(
  id: 'op-2',
  clienteId: 'cl-2',
  nombre: 'Ana Verde',
  cuit: '30500003193',
  consulta: ConsultaBcra(
    cuit: '30500003193',
    consultadoEl: DateTime(2026, 9, 10),
    periodo: '202607',
    situacionMaxima: 1,
    entidades: const [
      EntidadBcra(entidad: 'BANCO LIMPIO', situacion: 1, montoMiles: 500),
    ],
  ),
);

const _sinConsultar = Interesado(
  id: 'op-3',
  clienteId: 'cl-3',
  nombre: 'Caro SinCuit',
  telefono: '2615559999',
);

/// Solo implementa lo que estas pantallas usan; el resto no se llama nunca.
class _RepoFalso implements Repositorio {
  final consultas = <String>[];
  final cuitsGuardados = <String>[];
  String? falla;

  @override
  Future<List<Interesado>> interesados() async => [
    _limpio,
    _conDeuda,
    _sinConsultar,
  ];

  @override
  Future<void> guardarCuit({
    required String clienteId,
    required String cuit,
  }) async {
    cuitsGuardados.add(cuit);
  }

  @override
  Future<ConsultaBcra> consultarBcra({
    required String clienteId,
    required String cuit,
    bool forzar = false,
  }) async {
    consultas.add(cuit);
    if (falla != null) throw Exception(falla);
    return ConsultaBcra(
      cuit: cuit,
      consultadoEl: DateTime(2026, 9, 13),
      periodo: '202607',
      situacionMaxima: 1,
      entidades: const [
        EntidadBcra(entidad: 'BANCO LIMPIO', situacion: 1, montoMiles: 500),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(
    'La pantalla de interesados llamo a ${i.memberName}, que este falso no '
    'implementa. Si hace falta de verdad, agregalo.',
  );
}
