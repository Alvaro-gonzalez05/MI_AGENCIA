import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/sesion.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/agencias.dart';
import 'package:mi_agencia/funciones/estadisticas/pantalla_estadisticas.dart';
import 'package:mi_agencia/funciones/inventario/pantalla_ficha.dart';
import 'package:mi_agencia/funciones/panel/pantalla_panel.dart';
import 'package:mi_agencia/funciones/ventas/pantalla_ventas.dart';

/// Quién ve la plata.
///
/// Es la pregunta que más cuesta en una agencia: el dueño no quiere que el
/// precio de compra circule por el salón, y el vendedor negocia mejor sin
/// saber cuál es el piso. Acá se prueba que la app respete eso en las cuatro
/// pantallas donde aparecen números: Inicio, la ficha, Ventas y
/// Estadísticas.
///
/// Esconderlo en la pantalla no reemplaza al RLS de la base; es la mitad que
/// se ve.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Usuario quien(RolMembresia rol) => Usuario(
    id: 'u1',
    email: 'quien@agencia.test',
    nombre: 'Quien Mira',
    esDesarrollador: false,
    agenciaId: 'a1',
    agenciaNombre: 'Agencia Demo',
    rol: rol.valorBd,
  );

  Future<void> abrir(
    WidgetTester tester,
    Widget pantalla,
    RolMembresia rol, {
    Size tamano = const Size(1280, 1800),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositorioProvider.overrideWithValue(RepositorioDemo()),
          usuarioProvider.overrideWithValue(quien(rol)),
        ],
        child: MaterialApp(
          theme: TemaApp.claro(),
          home: Scaffold(body: pantalla),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('El rol', () {
    test('dice quién ve la plata', () {
      expect(RolMembresia.owner.vePlata, isTrue);
      expect(RolMembresia.admin.vePlata, isTrue);
      expect(RolMembresia.vendedor.vePlata, isFalse);
      expect(RolMembresia.soloLectura.vePlata, isFalse);
    });

    test('dice quién puede tocar', () {
      expect(RolMembresia.vendedor.puedeEditar, isTrue);
      expect(RolMembresia.soloLectura.puedeEditar, isFalse);
    });

    test('un rol que no existe no da permisos de más', () {
      // Si mañana la base devuelve un rol nuevo, el que mira no se convierte
      // en dueño por accidente.
      expect(RolMembresia.desde('contador'), RolMembresia.vendedor);
      expect(RolMembresia.desde(null).vePlata, isFalse);
    });
  });

  group('Inicio', () {
    testWidgets('al dueño le muestra la ganancia del mes', (t) async {
      await abrir(t, const PantallaPanel(), RolMembresia.owner);
      expect(find.text('GANANCIA DEL MES'), findsOneWidget);
      expect(find.text('FACTURADO ESTE MES'), findsNothing);
    });

    testWidgets('al vendedor, lo facturado', (t) async {
      await abrir(t, const PantallaPanel(), RolMembresia.vendedor);
      expect(find.text('GANANCIA DEL MES'), findsNothing);
      expect(find.text('FACTURADO ESTE MES'), findsOneWidget);
    });
  });

  group('La ficha de una unidad', () {
    testWidgets('al dueño le muestra lo invertido y la ganancia', (t) async {
      await abrir(t, const PantallaFicha(id: 'V001'), RolMembresia.owner);
      expect(find.text('Precio de compra'), findsWidgets);
      expect(find.textContaining('Ganancia'), findsWidgets);
    });

    testWidgets('al vendedor no, pero la ficha sigue sirviendo', (t) async {
      await abrir(t, const PantallaFicha(id: 'V001'), RolMembresia.vendedor);
      expect(find.text('Precio de compra'), findsNothing);
      expect(find.textContaining('Ganancia'), findsNothing);
      // Lo que necesita para vender sigue estando.
      expect(find.text('Valuación comercial y precio'), findsOneWidget);
    });
  });

  group('Ventas', () {
    testWidgets('al vendedor le muestra lo facturado, no el margen', (t) async {
      await abrir(t, const PantallaVentas(), RolMembresia.vendedor);
      expect(find.text('Facturado'), findsOneWidget);
      expect(find.text('Ganancia nominal'), findsNothing);
      expect(find.text('Margen'), findsNothing);
    });
  });

  group('Estadísticas', () {
    testWidgets('no se abren escribiendo la dirección a mano', (t) async {
      await abrir(t, const PantallaEstadisticas(), RolMembresia.vendedor);
      expect(find.text('Esto lo ve el dueño de la agencia'), findsOneWidget);
    });

    testWidgets('el dueño las ve', (t) async {
      await abrir(t, const PantallaEstadisticas(), RolMembresia.owner);
      expect(find.text('Esto lo ve el dueño de la agencia'), findsNothing);
    });
  });
}
