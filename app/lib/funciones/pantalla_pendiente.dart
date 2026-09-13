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
          constraints: const BoxConstraints(maxWidth: 580),
          child: Aparecer(
            child: Tarjeta(
              padding: const EdgeInsets.all(Esp.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconoEnCirculo(
                        icono: seccion.icono,
                        tamano: 56,
                        color: p.acentoTinta,
                        fondo: p.acento,
                      ),
                      const SizedBox(width: Esp.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seccion.titulo,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              seccion.subtitulo,
                              style: TextStyle(fontSize: 13, color: p.tinta3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Esp.xl),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Esp.md + 2,
                      vertical: 7,
                    ),
                    decoration: ShapeDecoration(
                      color: p.negro,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.construction_rounded,
                          size: 14,
                          color: p.acento,
                        ),
                        const SizedBox(width: Esp.sm - 2),
                        Flexible(
                          child: Text(
                            requiereBase
                                ? 'En construcción — necesita la base conectada'
                                : 'En construcción',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.sobreNegro,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Esp.xl),
                  const EtiquetaSeccion('Qué va a hacer'),
                  const SizedBox(height: Esp.md),
                  for (var i = 0; i < puntos.length; i++)
                    Aparecer(
                      indice: i + 1,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: Esp.sm),
                        padding: const EdgeInsets.all(Esp.md + 2),
                        decoration: BoxDecoration(
                          color: p.superficieHundida,
                          borderRadius: BorderRadius.circular(Curva.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: p.acento,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontFamily: TemaApp.mono,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: p.acentoTinta,
                                ),
                              ),
                            ),
                            const SizedBox(width: Esp.md),
                            Expanded(
                              child: Text(
                                puntos[i],
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
