import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tema/colores.dart';
import '../core/tema/tema.dart';

void confirmarGuardado(BuildContext context, String mensaje) =>
    _mostrarResultado(
      context,
      mensaje: mensaje,
      icono: Icons.check_rounded,
      color: context.paleta.bien,
    );

void confirmarEliminado(BuildContext context, String mensaje) =>
    _mostrarResultado(
      context,
      mensaje: mensaje,
      icono: Icons.delete_outline_rounded,
      color: context.paleta.neutro,
    );

void mostrarError(BuildContext context, Object error) {
  _mostrarResultado(
    context,
    mensaje: error.toString().replaceFirst('Exception: ', ''),
    icono: Icons.error_outline_rounded,
    color: context.paleta.critico,
    duracion: const Duration(seconds: 6),
  );
}

void _mostrarResultado(
  BuildContext context, {
  required String mensaje,
  required IconData icono,
  required Color color,
  Duration duracion = const Duration(seconds: 3),
}) {
  final mensajero = ScaffoldMessenger.of(context);
  mensajero.hideCurrentSnackBar();
  HapticFeedback.lightImpact();
  mensajero.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: duracion,
      content: Row(
        children: [
          SelloConfirmacion(tamano: 26, icono: icono, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(mensaje)),
        ],
      ),
    ),
  );
}

/// Dialogo comun para toda accion que puede hacer perder o publicar datos.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String descripcion,
  required String confirmar,
  String cancelar = 'Cancelar',
  IconData icono = Icons.help_outline_rounded,
  bool peligrosa = false,
  bool permitirCancelarTocandoAfuera = true,
}) async {
  final sinAnimaciones = MediaQuery.disableAnimationsOf(context);
  final respuesta = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: permitirCancelarTocandoAfuera,
    barrierLabel: cancelar,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: sinAnimaciones ? Duration.zero : Duracion.media,
    pageBuilder: (context, _, _) => _DialogoConfirmacion(
      titulo: titulo,
      descripcion: descripcion,
      confirmar: confirmar,
      cancelar: cancelar,
      icono: icono,
      peligrosa: peligrosa,
    ),
    transitionBuilder: (context, animacion, _, child) {
      final curva = CurvedAnimation(
        parent: animacion,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animacion,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curva),
          child: child,
        ),
      );
    },
  );
  return respuesta ?? false;
}

class _DialogoConfirmacion extends StatelessWidget {
  const _DialogoConfirmacion({
    required this.titulo,
    required this.descripcion,
    required this.confirmar,
    required this.cancelar,
    required this.icono,
    required this.peligrosa,
  });

  final String titulo, descripcion, confirmar, cancelar;
  final IconData icono;
  final bool peligrosa;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final color = peligrosa ? p.critico : p.acentoTexto;
    final fondo = peligrosa ? p.criticoLavado : p.acentoLavado;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Dialog(
            insetPadding: const EdgeInsets.all(Esp.lg),
            child: Padding(
              padding: const EdgeInsets.all(Esp.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: fondo,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icono, color: color, size: 25),
                  ),
                  const SizedBox(height: Esp.lg),
                  Text(titulo, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: Esp.sm),
                  Text(
                    descripcion,
                    style: TextStyle(color: p.tinta2, height: 1.5),
                  ),
                  const SizedBox(height: Esp.xl),
                  Wrap(
                    alignment: WrapAlignment.end,
                    runAlignment: WrapAlignment.end,
                    spacing: Esp.sm,
                    runSpacing: Esp.sm,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(cancelar),
                      ),
                      FilledButton.icon(
                        key: const Key('confirmar-accion'),
                        style: peligrosa
                            ? FilledButton.styleFrom(
                                backgroundColor: p.critico,
                                foregroundColor: Colors.white,
                              )
                            : null,
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context, true);
                        },
                        icon: Icon(icono, size: 18),
                        label: Text(confirmar),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SelloConfirmacion extends StatelessWidget {
  const SelloConfirmacion({
    super.key,
    this.tamano = 56,
    this.icono = Icons.check_rounded,
    this.color,
  });

  final double tamano;
  final IconData icono;
  final Color? color;

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
        color: color ?? context.paleta.bien,
        shape: BoxShape.circle,
      ),
      child: Icon(icono, color: Colors.white, size: tamano * .62),
    ),
  );
}
