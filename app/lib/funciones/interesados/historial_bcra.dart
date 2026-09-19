import 'package:flutter/material.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../dominio/bcra.dart';
import '../../ui/componentes.dart';

/// Los últimos 24 meses en la Central de Deudores, mes por mes.
///
/// Existe por el reclamo del cliente (checklist 3.1): una persona que fue
/// irrecuperable y después pagó salía "sin deudas", porque la app solo
/// miraba el último mes. La web del BCRA muestra estos 24 meses, y verlos
/// dibujados es lo que hace entendible un amarillo: "estuvo mal, pero hace
/// un año y medio que está al día".
///
/// Se lee de izquierda a derecha, como una línea de tiempo: lo viejo a la
/// izquierda, hoy a la derecha.
class HistorialBcra extends StatelessWidget {
  const HistorialBcra({super.key, required this.consulta});

  final ConsultaBcra consulta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = consulta;
    // Del más viejo al más nuevo, que es como se lee una línea de tiempo.
    final meses = c.historico.reversed.toList();

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Últimos ${meses.length} meses',
            descripcion: _resumen(c),
          ),
          const SizedBox(height: Esp.lg),

          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < meses.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(child: _Celda(mes: meses[i])),
                ],
              ],
            ),
          ),
          const SizedBox(height: Esp.xs + 2),
          Row(
            children: [
              Text(
                meses.first.corto,
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 10.5,
                  color: p.tinta3,
                ),
              ),
              const Spacer(),
              Text(
                meses.last.corto,
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 10.5,
                  color: p.tinta3,
                ),
              ),
            ],
          ),

          const SizedBox(height: Esp.md),
          Wrap(
            spacing: Esp.md,
            runSpacing: Esp.xs,
            children: [
              for (final (s, texto) in const [
                (0, 'Sin deuda'),
                (1, 'Normal'),
                (2, 'Riesgo bajo'),
                (3, 'Riesgo medio'),
                (4, 'Alto / irrecuperable'),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colorDeSituacion(p, s),
                        borderRadius: BorderRadius.circular(2),
                        border: s == 0
                            ? Border.all(color: p.bordeFuerte)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      texto,
                      style: TextStyle(fontSize: 11, color: p.tinta3),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _resumen(ConsultaBcra c) {
    final peor = c.situacionMax24m;
    if (peor == null) return 'Sin deudas en todo el período';
    if (peor == 1) return 'Pagó en término todo el período';
    final base = 'Peor situación: $peor';
    if (c.regularizo && c.alDiaDesde.isNotEmpty) {
      return '$base · al día desde ${c.alDiaDesde}';
    }
    return base;
  }
}

/// El color de una situación, igual en la línea de tiempo y en el PDF.
Color colorDeSituacion(Paleta p, int situacion) => switch (situacion) {
  0 => p.superficieHundida,
  1 => p.bien,
  2 => p.observar,
  3 => p.atencion,
  _ => p.critico,
};

class _Celda extends StatelessWidget {
  const _Celda({required this.mes});

  final MesBcra mes;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final s = mes.situacion;

    return Tooltip(
      message: s == 0
          ? '${mes.corto} · sin deuda'
          : '${mes.corto} · situación $s',
      child: Container(
        decoration: BoxDecoration(
          color: colorDeSituacion(p, s),
          borderRadius: BorderRadius.circular(4),
          // Un mes sin deuda no es un hueco: tiene su borde, para que se lea
          // como "estuvo, y no debía" y no como un dato que falta.
          border: s == 0 ? Border.all(color: p.borde) : null,
        ),
      ),
    );
  }
}
