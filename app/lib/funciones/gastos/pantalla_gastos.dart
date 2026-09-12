import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/gastos.dart';
import '../../ui/componentes.dart';
import 'formulario_gasto.dart';

class PantallaGastos extends ConsumerWidget {
  const PantallaGastos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final asincrono = ref.watch(gastosProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(context),
        backgroundColor: p.acento,
        foregroundColor: p.acentoTinta,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Nuevo gasto'),
      ),
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar los gastos',
          descripcion: '$e',
        ),
        data: (gastos) {
          if (gastos.isEmpty) {
            return EstadoVacio(
              icono: Icons.receipt_long_outlined,
              titulo: 'Todavía no hay gastos cargados',
              descripcion:
                  'Sin gastos, el costo de cada unidad es solo el precio de '
                  'compra y los márgenes que ves están inflados.',
              accion: FilledButton.icon(
                onPressed: () => abrirFormulario(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Cargar un gasto'),
              ),
            );
          }

          final total = gastos.fold<double>(0, (s, g) => s + g.importe);
          final porCategoria = <CategoriaGasto, double>{};
          for (final g in gastos) {
            porCategoria[g.categoria] =
                (porCategoria[g.categoria] ?? 0) + g.importe;
          }
          final ranking = porCategoria.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return ListView(
            padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.xl, Esp.xl, 96),
            children: [
              _Resumen(
                total: total,
                cantidad: gastos.length,
                ranking: ranking.take(4).toList(),
              ),
              const SizedBox(height: Esp.lg),
              for (final g in gastos) ...[
                _Fila(gasto: g),
                const SizedBox(height: Esp.sm),
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<void> abrirFormulario(BuildContext context) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FormularioGasto(),
      ),
    );
    if (guardado == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Gasto cargado')));
    }
  }
}

/// Adonde se va la plata. Es la pregunta que se hace el dueño cuando mira los
/// gastos: no le interesa el listado, le interesa en qué se le va.
class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.total,
    required this.cantidad,
    required this.ranking,
  });

  final double total;
  final int cantidad;
  final List<MapEntry<CategoriaGasto, double>> ranking;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('Invertido en preparación'),
          const SizedBox(height: Esp.md),
          Text(
            Fmt.pesos(total),
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: p.tinta,
            ),
          ),
          Text(
            '$cantidad gasto${cantidad == 1 ? '' : 's'} cargado'
            '${cantidad == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12.5, color: p.tinta3),
          ),
          if (ranking.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.md),
            for (final e in ranking)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.sm),
                child: Row(
                  children: [
                    Icon(e.key.icono, size: 15, color: p.tinta3),
                    const SizedBox(width: Esp.md),
                    Expanded(
                      child: Text(
                        e.key.etiqueta,
                        style: TextStyle(fontSize: 13, color: p.tinta2),
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(
                        Fmt.porcentaje(
                          total > 0 ? e.value / total : 0,
                          decimales: 0,
                        ),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 12,
                          color: p.tinta3,
                        ),
                      ),
                    ),
                    const SizedBox(width: Esp.md),
                    Text(
                      Fmt.pesosCompacto(e.value),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.tinta,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.gasto});

  final Gasto gasto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final g = gasto;

    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.sm),
            ),
            child: Icon(g.categoria.icono, size: 16, color: p.tinta2),
          ),
          const SizedBox(width: Esp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.descripcion?.isNotEmpty == true
                      ? g.descripcion!
                      : g.categoria.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: p.tinta,
                  ),
                ),
                Text(
                  [
                    if (g.vehiculoCodigo != null)
                      '${g.vehiculoCodigo} · ${g.vehiculoTitulo ?? ''}',
                    g.categoria.etiqueta,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.tinta3),
                ),
              ],
            ),
          ),
          const SizedBox(width: Esp.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.pesos(g.importe),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.tinta,
                ),
              ),
              Text(
                Fmt.fecha(g.fecha),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 11,
                  color: p.tinta3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
