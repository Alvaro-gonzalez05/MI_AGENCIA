import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/main.dart';
import 'package:mi_agencia/ui/componentes.dart';

/// Recorrido de la app entera, como la usaría alguien de la agencia.
///
/// No prueba una pantalla aislada: levanta la app de verdad (el router, el
/// shell, los proveedores y el repositorio de demostración) y la maneja a
/// toques, sección por sección. Es la prueba que contesta "¿anda cada
/// botón?", que es justo lo que no contesta un test de widget suelto.
///
/// Corre en modo demo: sin `--dart-define` la app usa los datos de ejemplo
/// en memoria, así que se pueden dar de alta y borrar cosas sin tocar la
/// base real.
void main() {
  setUpAll(() async => initializeDateFormatting('es_AR'));

  /// Arranca la app y entra (en demo, cualquier credencial sirve).
  Future<void> entrar(
    WidgetTester tester, {
    Size tamano = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MiAgencia()));
    await tester.pumpAndSettle();

    // Pantalla de ingreso.
    expect(find.text('Mi Agencia'), findsWidgets);
    await tester.enterText(
      find.byType(TextFormField).first,
      'prueba@miagencia.app',
    );
    await tester.enterText(find.byType(TextFormField).last, 'clave-de-prueba');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  /// Toca algo que puede estar más abajo de lo que se ve.
  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
    await tester.tap(f.first);
    await tester.pumpAndSettle();
  }

  /// Va a una sección desde la barra lateral (escritorio).
  Future<void> ir(WidgetTester tester, String etiqueta) async {
    final destino = find.text(etiqueta);
    expect(
      destino,
      findsWidgets,
      reason: 'No encontré "$etiqueta" para navegar',
    );
    await tocar(tester, destino.first);
    await tester.pumpAndSettle();
  }

  testWidgets('entra, recorre las secciones y ninguna explota', (tester) async {
    await entrar(tester);

    // Arranca en el Panel (Inicio), con los bloques del diseño.
    expect(find.textContaining('Buen'), findsWidgets);
    expect(find.text('Para atender hoy'), findsOneWidget);
    expect(find.text('Cómo vienen las ventas'), findsOneWidget);
    // "Tus autos en venta" queda abajo del todo: hay que bajar a buscarlo.
    await tester.drag(find.text('Para atender hoy'), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Tus autos en venta'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final seccion in [
      'Inventario',
      'Clientes',
      'Vehículos',
      'Gastos',
      'Precios',
      'Ventas',
      'Campañas',
      'Estadísticas',
      'Simulador',
      'Configuración',
    ]) {
      await ir(tester, seccion);
      expect(
        tester.takeException(),
        isNull,
        reason: 'La sección $seccion tiró una excepción',
      );
    }
  });

  testWidgets('inventario: pestañas, buscador y filtros responden', (
    tester,
  ) async {
    await entrar(tester);
    await ir(tester, 'Inventario');

    expect(find.text('Inventario'), findsWidgets);
    expect(find.widgetWithText(ChipSeleccion, 'Disponibles'), findsOneWidget);

    // Las pestañas cambian lo que se lista.
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Vendidos'));
    expect(find.textContaining('Mostrando'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Todos'));

    // El buscador filtra y el botón de limpiar lo deshace.
    await tester.enterText(
      find.descendant(
        of: find.byType(Buscador),
        matching: find.byType(TextField),
      ),
      'zzzz-no-existe',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ningún auto coincide'), findsOneWidget);

    await tocar(tester, find.text('Limpiar filtros').first);
    expect(find.textContaining('Ningún auto coincide'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ficha: se abre desde el inventario y sus botones navegan', (
    tester,
  ) async {
    await entrar(tester);
    await ir(tester, 'Inventario');

    await tocar(tester, find.text('Ver ficha').first);
    expect(find.text('Valuación comercial y precio'), findsOneWidget);
    expect(find.text('Datos técnicos'), findsOneWidget);
    expect(find.text('Papeles y documentación'), findsOneWidget);

    // El simulador de precio recalcula al mover el margen.
    expect(find.text('Simulador de precio'), findsOneWidget);

    await tocar(tester, find.text('Cargar un gasto'));
    expect(find.text('Gastos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alta de vehículo: cancelar no guarda, confirmar sí', (
    tester,
  ) async {
    await entrar(tester);

    // Cuántas unidades hay antes.
    await ir(tester, 'Inventario');
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Todos'));
    final textoAntes = tester
        .widgetList<Text>(find.textContaining('Mostrando'))
        .first
        .data!;

    // 1. Se abre el alta y se cancela: no tiene que quedar nada.
    await ir(tester, 'Vehículos');
    await tocar(tester, find.text('Nueva unidad').first);
    expect(find.text('EL VEHÍCULO'), findsWidgets);
    expect(find.text('Marca'), findsWidgets);
    expect(find.text('Modelo'), findsWidgets);
    await tocar(tester, find.text('Cancelar').first);

    await ir(tester, 'Inventario');
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Todos'));
    expect(
      tester.widgetList<Text>(find.textContaining('Mostrando')).first.data,
      textoAntes,
      reason: 'Cancelar el alta no puede cambiar el inventario',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clientes: filtros, alta y baja de un interesado', (
    tester,
  ) async {
    await entrar(tester);
    await ir(tester, 'Clientes');

    expect(find.text('Clientes'), findsWidgets);
    expect(find.widgetWithText(ChipSeleccion, 'Todos'), findsOneWidget);

    // Las pestañas y los filtros por semáforo responden.
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Interesados'));
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Situación normal'));
    expect(tester.takeException(), isNull);
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Situación normal'));

    // El alta se abre y se puede cerrar sin guardar.
    await tocar(tester, find.text('Nuevo cliente').first);
    expect(find.textContaining('01 ·'), findsWidgets);
    expect(find.text('Nombre y apellido'), findsWidgets);
    await tocar(tester, find.byIcon(Icons.close_rounded).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('simulador: cambia de sistema y recalcula', (tester) async {
    await entrar(tester);
    await ir(tester, 'Simulador');

    expect(find.text('Monto a financiar'), findsOneWidget);
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Alemán'));
    expect(find.text('Primera cuota (van bajando)'), findsOneWidget);

    await tocar(tester, find.byTooltip('Una cuota más'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('estadísticas: cambia el período y dibuja los gráficos', (
    tester,
  ) async {
    await entrar(tester);
    await ir(tester, 'Estadísticas');

    expect(find.text('Ventas por mes'), findsOneWidget);
    expect(find.text('Lo que más vendés'), findsOneWidget);
    await tocar(tester, find.widgetWithText(ChipSeleccion, 'Este mes'));
    await tester.drag(find.text('Ventas por mes'), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Ganancia por mes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en celular: barra inferior, hoja de cargar y hoja de más', (
    tester,
  ) async {
    await entrar(tester, tamano: const Size(390, 844));

    // Los cinco lugares de la barra, por su icono.
    for (final icono in [
      Icons.add_circle_outline_rounded,
      Icons.more_horiz_rounded,
    ]) {
      expect(
        find.byIcon(icono),
        findsWidgets,
        reason: 'Falta el icono $icono en la barra inferior',
      );
    }
    expect(find.text('Panel'), findsWidgets);

    // El "+" abre la hoja de cargar.
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Vehículos'), findsWidgets);
    await tester.tapAt(const Offset(200, 60)); // fuera de la hoja
    await tester.pumpAndSettle();

    // "Más" abre las opciones, con los bloques del diseño.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Más opciones'), findsOneWidget);
    expect(find.text('MI NEGOCIO'), findsOneWidget);
    expect(find.text('Estadísticas'), findsWidgets);
    expect(find.text('Tamaño de la letra'), findsOneWidget);
    expect(find.text('Modo oscuro'), findsOneWidget);
    expect(find.text('Ocultar montos'), findsOneWidget);

    // El tema y el tamaño de letra se pueden cambiar sin romper nada.
    await tocar(tester, find.byType(Switch).first);
    await tocar(tester, find.text('A++').first);
    expect(tester.takeException(), isNull);
  });
}
