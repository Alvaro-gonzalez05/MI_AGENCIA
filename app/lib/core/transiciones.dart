import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Cómo se pasa de una pantalla a otra.
///
/// La transición por defecto de Material empuja la pantalla nueva ENCIMA de
/// la vieja. Entre secciones eso se siente tosco, porque Panel y Gastos no son
/// una arriba de la otra: son hermanas. Nada tendría que "taparse".
///
/// Hay una limitación de go_router que manda el diseño acá, y conviene
/// dejarla escrita para no volver a chocarse con ella:
///
/// **Al saltar entre secciones hermanas, go_router REEMPLAZA la ruta, y la
/// pantalla que se va no corre ninguna animación de salida: se queda en
/// opacidad 1 hasta que desaparece.** Medido, no supuesto — está en
/// test/transiciones_test.dart. Eso hace que cualquier fundido de entrada se
/// vea como un fantasma: durante 150 ms se ven las dos encimadas, porque las
/// pantallas de sección son transparentes y el fondo lo pone el shell.
///
/// Se probó también cruzarlas con un AnimatedSwitcher en el shell, para
/// tenerlas bajo un mismo controlador. No se puede: el hijo de un ShellRoute
/// es un Navigator con GlobalKey, y dos vivos a la vez revientan con
/// "duplicate GlobalKey".
///
/// Así que entre secciones no hay transición de página ([paginaSeccion]), y el
/// movimiento lo pone `Aparecer`, que ya escalona las tarjetas de cada
/// pantalla. El cambio de sección es instantáneo y limpio, y lo que se ve
/// entrar es el contenido. Sale mejor que cualquier fundido que se pueda hacer
/// con la pantalla vieja clavada abajo.
///
/// La ficha de una unidad es otra cosa: es una ruta HIJA, así que ahí sí hay
/// un push de verdad, con su animación de salida. Entra de costado
/// ([paginaDetalle]), que es el gesto de "entré" y "volví".
abstract final class Transiciones {
  /// Corta. Una transición entre pantallas que se nota es una que molesta a
  /// la décima vez que la ves en el día.
  static const duracion = Duration(milliseconds: 260);

  /// Una pantalla de sección: entra sin animación de página.
  ///
  /// No es pereza ni un "ya lo hacemos después". Con la pantalla vieja clavada
  /// en opacidad 1 abajo (ver arriba), cualquier fundido de entrada se ve como
  /// un fantasma encimado. Sin transición de página, el cambio es limpio y el
  /// movimiento lo pone `Aparecer` sobre las tarjetas, que es donde se lee
  /// mejor.
  static Page<void> paginaSeccion(GoRouterState estado, Widget hijo) =>
      NoTransitionPage<void>(key: estado.pageKey, child: hijo);

  /// Una ficha: el detalle de algo que estaba en una lista.
  ///
  /// Entra desde la derecha y se va para el mismo lado, que es el gesto de
  /// "entré" y "volví". El desplazamiento es chico (6% del ancho) porque el
  /// shell no se mueve: lo único que viaja es el contenido.
  static Page<void> paginaDetalle(GoRouterState estado, Widget hijo) =>
      CustomTransitionPage<void>(
        key: estado.pageKey,
        child: hijo,
        transitionDuration: duracion,
        reverseTransitionDuration: duracion,
        transitionsBuilder: (context, animacion, _, hijo) {
          final curva = CurvedAnimation(
            parent: animacion,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curva,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(curva),
              child: hijo,
            ),
          );
        },
      );
}

// Las pantallas que se abren con el Navigator de siempre (los formularios a
// pantalla completa, la ficha del interesado) las sigue manejando
// `TransicionSuave`, en core/tema/tema.dart. Son dos caminos distintos —
// go_router y Navigator — y cada uno necesita lo suyo, pero el lenguaje de
// movimiento es el mismo: fundido corto, desplazamiento chico, nada que se
// apile opaco encima de otra cosa.
