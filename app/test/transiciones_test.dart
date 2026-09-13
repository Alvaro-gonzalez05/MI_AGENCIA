import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mi_agencia/core/transiciones.dart';

/// Cómo se ve el paso de una sección a otra.
///
/// El cliente lo describió así: "aparece sobre lo que ya había y se ve medio
/// tosco". Traducido a algo que se pueda medir: durante la transición las dos
/// pantallas están opacas al mismo tiempo, así que la nueva se lee como una
/// hoja pegada encima de la vieja en vez de un cambio de sección.
///
/// Estos tests miden justamente eso. No comprueban que "se vea lindo" —eso no
/// se puede afirmar en un test— sino la propiedad concreta que causaba la
/// sensación: que en ningún momento haya dos pantallas a opacidad plena.
void main() {
  /// Un shell con dos secciones hermanas, como el de la app.
  GoRouter router() => GoRouter(
    initialLocation: '/uno',
    routes: [
      ShellRoute(
        builder: (context, estado, hijo) => hijo,
        routes: [
          GoRoute(
            path: '/uno',
            pageBuilder: (_, e) =>
                Transiciones.paginaSeccion(e, const Text('PANTALLA UNO')),
          ),
          GoRoute(
            path: '/dos',
            pageBuilder: (_, e) =>
                Transiciones.paginaSeccion(e, const Text('PANTALLA DOS')),
          ),
        ],
      ),
    ],
  );

  /// Con cuanta opacidad se ve, de verdad, una pantalla.
  ///
  /// Se busca su texto y se multiplican TODOS los fundidos que tiene encima
  /// hasta la raiz. Contar los FadeTransition sueltos del arbol no sirve:
  /// Material mete los suyos, y el numero termina diciendo cualquier cosa.
  double opacidadDe(WidgetTester tester, String texto) {
    final encontrados = find.text(texto).evaluate();
    if (encontrados.isEmpty) return 0;

    var opacidad = 1.0;
    encontrados.single.visitAncestorElements((elemento) {
      final w = elemento.widget;
      if (w is FadeTransition) opacidad *= w.opacity.value;
      if (w is Opacity) opacidad *= w.opacity;
      return true;
    });
    return opacidad;
  }

  testWidgets('cambiar de sección no encima una pantalla sobre la otra', (
    tester,
  ) async {
    final r = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    r.go('/dos');
    await tester.pump();

    for (var ms = 0; ms <= 400; ms += 20) {
      await tester.pump(const Duration(milliseconds: 20));
      final vieja = opacidadDe(tester, 'PANTALLA UNO');
      final nueva = opacidadDe(tester, 'PANTALLA DOS');

      expect(
        vieja * nueva,
        0,
        reason:
            'A los $ms ms se veian las dos a la vez (vieja '
            '${vieja.toStringAsFixed(2)}, nueva ${nueva.toStringAsFixed(2)}). '
            'Eso es el fantasma que se sentia como una hoja pegada encima de '
            'la otra: go_router deja la pantalla que se va en opacidad 1, asi '
            'que cualquier fundido de entrada la muestra por debajo.',
      );
    }

    await tester.pumpAndSettle();
    expect(find.text('PANTALLA DOS'), findsOneWidget);
    expect(find.text('PANTALLA UNO'), findsNothing);
  });

  testWidgets('la sección nueva está entera desde el primer cuadro', (
    tester,
  ) async {
    final r = router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    r.go('/dos');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // Sin animacion de pagina, el contenido llega de una. El movimiento lo
    // pone `Aparecer` sobre las tarjetas de adentro, no la pantalla entera.
    expect(opacidadDe(tester, 'PANTALLA DOS'), 1);
  });

  testWidgets('la ficha entra de costado, no se funde', (tester) async {
    // Una ficha SI es un adentro de la lista, y ahi el movimiento lateral es
    // el que cuenta de donde venis. Es a proposito que sea distinto.
    final r = GoRouter(
      initialLocation: '/lista',
      routes: [
        GoRoute(
          path: '/lista',
          pageBuilder: (_, e) =>
              Transiciones.paginaSeccion(e, const Text('LISTA')),
          routes: [
            GoRoute(
              path: ':id',
              pageBuilder: (_, e) =>
                  Transiciones.paginaDetalle(e, const Text('FICHA')),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();

    r.go('/lista/abc');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final deslizamientos = tester.widgetList<SlideTransition>(
      find.byType(SlideTransition),
    );
    expect(
      deslizamientos.any((s) => s.position.value.dx.abs() > 0.001),
      isTrue,
      reason: 'La ficha tendria que entrar desplazada en horizontal.',
    );

    await tester.pumpAndSettle();
    expect(find.text('FICHA'), findsOneWidget);
  });
}
