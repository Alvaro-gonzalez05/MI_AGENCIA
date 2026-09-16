import 'package:flutter/material.dart';

import '../core/tema/colores.dart';

/// Feedback breve, sin bloquear al vendedor ni superponer dos pantallas.
void confirmarGuardado(BuildContext context, String mensaje) {
  final mensajero = ScaffoldMessenger.of(context);
  mensajero.hideCurrentSnackBar();
  mensajero.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          const SelloConfirmacion(tamano: 26),
          const SizedBox(width: 12),
          Expanded(child: Text(mensaje)),
        ],
      ),
    ),
  );
}

class SelloConfirmacion extends StatelessWidget {
  const SelloConfirmacion({super.key, this.tamano = 56});
  final double tamano;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.65, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380),
    curve: Curves.easeOutBack,
    builder: (context, escala, child) =>
        Transform.scale(scale: escala, child: child),
    child: Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: context.paleta.bien,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check_rounded, color: Colors.white, size: tamano * .62),
    ),
  );
}
