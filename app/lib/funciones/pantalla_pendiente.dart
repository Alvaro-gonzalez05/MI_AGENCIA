import 'package:flutter/material.dart';

import '../core/tema/colores.dart';
import '../core/tema/tema.dart';
import '../ui/componentes.dart';
import '../ui/shell/secciones.dart';

/// Pantalla de seccion todavia no construida.
///
/// Existe a proposito en vez de dejar rutas rotas o pantallas en blanco: la
/// navegacion completa se puede recorrer de punta a punta, y cada seccion
/// pendiente dice exactamente que va a hacer. Sirve para mostrarle el alcance
/// al cliente sin prometer que ya funciona.
class PantallaPendiente extends StatelessWidget {
  const PantallaPendiente({
    super.key,
    required this.seccion,
    required this.puntos,
    this.requiereBase = true,
  });

  final Seccion seccion;

  /// Que va a hacer esta pantalla cuando este terminada.
  final List<String> puntos;

  /// Si depende de que Supabase este conectado.
  final bool requiereBase;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Esp.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Tarjeta(
            padding: const EdgeInsets.all(Esp.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.acentoLavado,
                        borderRadius: BorderRadius.circular(Curva.md),
                        border: Border.all(
                            color: p.acento.withValues(alpha: 0.25)),
                      ),
                      child: Icon(seccion.icono, color: p.acento, size: 21),
                    ),
                    const SizedBox(width: Esp.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(seccion.titulo,
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            seccion.subtitulo,
                            style:
                                TextStyle(fontSize: 12.5, color: p.tinta3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Esp.xl),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Esp.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.observarLavado,
                    borderRadius: BorderRadius.circular(Curva.completo),
                    border: Border.all(
                        color: p.observar.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    requiereBase
                        ? 'Pendiente — necesita la base conectada'
                        : 'Pendiente',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.observar,
                    ),
                  ),
                ),
                const SizedBox(height: Esp.xl),
                const EtiquetaSeccion('Qué va a hacer'),
                const SizedBox(height: Esp.md),
                for (final punto in puntos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Esp.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 7, right: Esp.md),
                          decoration: BoxDecoration(
                            color: p.acento,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            punto,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: p.tinta2,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
