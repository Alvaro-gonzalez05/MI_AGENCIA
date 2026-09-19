import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/alta_interesado.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/funciones/interesados/alta_interesado.dart';
import 'package:mi_agencia/funciones/interesados/informe_pdf.dart';
import 'package:mi_agencia/funciones/interesados/pantalla_interesados.dart';
import 'package:mi_agencia/funciones/vehiculos/pantalla_vehiculos.dart';

class RepoPrueba extends RepositorioDemo {
  int altas = 0, consultas = 0, pdfs = 0;
  bool fallaBcra = false, fallaPdf = false;
  final List<Interesado> clientes = [];
  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async => [];
  @override
  Future<List<Interesado>> interesados() async => clientes;
  @override
  Future<Interesado> crearInteresado(AltaInteresado alta) async {
    altas++;
    final i = await super.crearInteresado(alta);
    clientes.add(i);
    return i;
  }

  @override
  Future<ConsultaBcra> consultarBcra({
    required String clienteId,
    required String cuit,
    bool forzar = false,
  }) async {
    consultas++;
    if (fallaBcra) throw Exception('BCRA temporalmente sin respuesta');
    return ConsultaBcra(
      cuit: cuit,
      consultadoEl: DateTime.now(),
      periodo: '202608',
      situacionMaxima: 1,
      entidades: const [
        EntidadBcra(
          entidad: 'ENTIDAD DE PRUEBA',
          situacion: 1,
          montoMiles: 500,
        ),
      ],
    );
  }

  @override
  Future<void> guardarInforme(Interesado interesado, List<int> bytes) async {
    if (fallaPdf) throw Exception('No se pudo guardar el PDF');
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    pdfs++;
    return super.guardarInforme(interesado, bytes);
  }
}

void main() {
  group('Consentimiento para mails (checklist 4.1)', () {
    AltaInteresado alta({String? email, bool acepta = false}) => AltaInteresado(
      solicitud: 'solicitud-de-prueba',
      nombre: 'Ana',
      cuit: '27230938607',
      email: email,
      aceptaMarketing: acepta,
    );

    test('si lo marcó y hay email, se guarda que acepta', () {
      expect(
        alta(email: 'a@b.com', acepta: true).json['acepta_marketing'],
        isTrue,
      );
    });

    test('si no lo marcó, no acepta: se pregunta, no se asume', () {
      expect(alta(email: 'a@b.com').json['acepta_marketing'], isFalse);
    });

    test('sin email no hay consentimiento que valga', () {
      expect(alta(acepta: true).json['acepta_marketing'], isFalse);
    });
  });

  setUpAll(() => initializeDateFormatting('es_AR'));
  Future<void> pintar(
    WidgetTester tester,
    RepoPrueba repo,
    Widget home,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositorioProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: TemaApp.oscuro(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, String texto) async {
    final f = find.text(texto);
    // En un celular el botón puede quedar debajo de lo que la lista llegó a
    // dibujar (una ListView solo construye lo que está cerca de la pantalla):
    // se baja hasta encontrarlo, como haría una persona. Sin esto, cada campo
    // nuevo del formulario rompía el test a 360 px sin que la pantalla
    // tuviera nada mal.
    if (f.evaluate().isEmpty) {
      // La del formulario: abajo sigue montada la lista de interesados, que
      // también se puede desplazar y no tiene el botón.
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .descendant(
              of: find.byType(FormularioInteresado),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> datos(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Cliente de Prueba',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '30-50000319-3');
    await tocar(tester, 'Continuar');
  }

  for (final size in [const Size(360, 780), const Size(1440, 900)]) {
    testWidgets('alta accesible y validación a ${size.width}', (tester) async {
      final repo = RepoPrueba();
      await pintar(tester, repo, const PantallaInteresados(), size);
      await tocar(tester, 'Nuevo interesado');
      await tocar(tester, 'Continuar');
      expect(find.text('Ingresá el nombre y apellido.'), findsOneWidget);
      expect(repo.altas, 0);
      await datos(tester);
      expect(find.text('¿Qué está buscando?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('vehículos tiene un solo botón de alta a ${size.width}', (
      tester,
    ) async {
      await pintar(tester, RepoPrueba(), const PantallaVehiculos(), size);
      expect(find.text('Cargar un vehículo'), findsOneWidget);
      expect(find.text('Nueva unidad'), findsNothing);
    });
  }
  testWidgets(
    'fallo del BCRA conserva alta y reintento de PDF no repite consulta',
    (tester) async {
      final repo = RepoPrueba()..fallaBcra = true;
      await pintar(
        tester,
        repo,
        const FormularioInteresado(),
        const Size(1440, 900),
      );
      await datos(tester);
      await tocar(tester, 'Guardar y evaluar');
      expect(repo.altas, 1);
      expect(repo.consultas, 1);
      expect(find.textContaining('Tus datos están guardados.'), findsOneWidget);
      repo.fallaBcra = false;
      repo.fallaPdf = true;
      await tocar(tester, 'Reintentar consulta');
      // La generación usa fuentes empaquetadas y compresión asíncrona real.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(repo.altas, 1);
      expect(repo.consultas, 2);
      expect(find.text('Reintentar guardar PDF'), findsOneWidget);
      repo.fallaPdf = false;
      await tocar(tester, 'Reintentar guardar PDF');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(repo.pdfs, 1);
      expect(repo.altas, 1);
      expect(repo.consultas, 2);
      expect(
        find.text('La ficha y el informe ya están en tu agencia.'),
        findsOneWidget,
      );
    },
  );

  test('PDF real incluye datos y genera documento imprimible', () async {
    final bytes = await InformeCrediticio.generar(
      interesado: Interesado(
        id: 'qa',
        clienteId: 'qa',
        nombre: 'Cliente de Prueba',
        cuit: '30500003193',
        email: 'cliente@example.test',
        telefono: '011 5555-0100',
        localidad: 'Buenos Aires',
        notas: 'Busca un vehículo familiar. Datos ficticios para validar el diseño.',
        presupuestoMax: 18000000,
        necesitaFinanciacion: true,
        consulta: ConsultaBcra(
          cuit: '30500003193',
          consultadoEl: DateTime.now(),
          periodo: '202608',
          situacionMaxima: 2,
          totalDeudaMiles: 2500,
          entidades: const [
            EntidadBcra(
              entidad: 'ENTIDAD DE PRUEBA',
              situacion: 2,
              montoMiles: 2500,
            ),
          ],
        ),
      ),
      agencia: 'Mi Agencia · Prueba de diseño',
      generadoPor: 'Control de calidad',
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final dir = Directory('build/qa')..createSync(recursive: true);
    File('${dir.path}/informe-prueba.pdf').writeAsBytesSync(bytes);
  });

  test('cambiar CUIT descarta consulta anterior; vencida no evalúa', () {
    final i = Interesado(
      id: 'x',
      clienteId: 'x',
      nombre: 'Prueba',
      cuit: '30500003193',
      consulta: ConsultaBcra(
        cuit: '30500003193',
        consultadoEl: DateTime.now(),
        entidades: const [],
        situacionMaxima: 1,
        vencida: true,
      ),
    );
    expect(i.semaforo, SemaforoCrediticio.sinDatos);
    expect(i.copiar(cuit: '33693450239').consulta, isNull);
  });
}
