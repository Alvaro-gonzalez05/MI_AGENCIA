import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/sesion.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/funciones/vehiculos/formulario_vehiculo.dart';

/// Cómo se empieza a cargar un auto.
///
/// La agencia llega con una lista en la mano más veces de las que llega con
/// un auto solo. Si el botón de "nueva unidad" abre derecho el formulario de
/// a uno, nadie carga treinta autos: se cansan en el quinto. Por eso antes
/// de empezar se pregunta, igual que en la sección "Cargar".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Future<void> abrir(WidgetTester t, Widget pantalla) async {
    t.view.physicalSize = const Size(1280, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          repositorioProvider.overrideWithValue(RepositorioDemo()),
          usuarioProvider.overrideWithValue(
            const Usuario(
              id: 'u1',
              email: 'duena@agencia.test',
              nombre: 'Marcela',
              esDesarrollador: false,
              agenciaId: 'a1',
              rol: 'owner',
            ),
          ),
        ],
        child: MaterialApp(theme: TemaApp.claro(), home: pantalla),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('entrando por "nueva unidad" primero pregunta cómo', (t) async {
    await abrir(t, const FormularioVehiculo(preguntarModo: true));

    expect(find.text('¿Cómo lo vas a cargar?'), findsOneWidget);
    expect(find.text('Un auto solo'), findsOneWidget);
    expect(find.text('Varios autos de una vez'), findsOneWidget);
    // Todavía no empezó: no se ve ningún campo del auto.
    expect(find.text('Marca *'), findsNothing);
  });

  testWidgets('eligiendo "un auto solo" arranca el paso a paso', (t) async {
    await abrir(t, const FormularioVehiculo(preguntarModo: true));

    await t.tap(find.text('Comenzar ahora'));
    await t.pumpAndSettle();

    expect(find.text('¿Cómo lo vas a cargar?'), findsNothing);
    expect(find.text('Marca *'), findsWidgets);
  });

  testWidgets('el que ya eligió no vuelve a elegir', (t) async {
    // Es el caso de la sección "Cargar" y el de corregir una fila importada.
    await abrir(t, const FormularioVehiculo());

    expect(find.text('¿Cómo lo vas a cargar?'), findsNothing);
    expect(find.text('Marca *'), findsWidgets);
  });
}
