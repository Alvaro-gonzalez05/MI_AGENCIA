import '../../ui/confirmacion.dart';

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
    final asincrono = ref.watch(gastosProvider);
    final margen = MediaQuery.sizeOf(context).width < Corte.tablet
        ? Esp.lg + 4
        : Esp.xxl;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(context),
        icon: const Icon(Icons.add_rounded, size: 22),
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
            padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, 104),
            children: [
              Aparecer(
                child: _Resumen(
                  total: total,
                  cantidad: gastos.length,
                  ranking: ranking.take(4).toList(),
                ),
              ),
              const SizedBox(height: Esp.lg + 2),
              for (var i = 0; i < gastos.length; i++) ...[
                if (i < 20)
                  Aparecer(
                    indice: i + 1,
                    child: _Fila(gasto: gastos[i]),
                  )
                else
                  _Fila(gasto: gastos[i]),
                const SizedBox(height: Esp.sm + 2),
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
      confirmarGuardado(context, 'Gasto cargado');
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
      destacada: true,
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.receipt_long_rounded,
                tamano: 38,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Invertido en preparación',
                  descripcion:
                      '$cantidad gasto${cantidad == 1 ? '' : 's'} cargado'
                      '${cantidad == 1 ? '' : 's'}',
                  sobreNegro: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.pesos(total),
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                color: p.acento,
              ),
            ),
          ),
          if (ranking.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            for (final e in ranking)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.md),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(e.key.icono, size: 15, color: p.sobreNegro2),
                        const SizedBox(width: Esp.sm),
                        Expanded(
                          child: Text(
                            e.key.etiqueta,
                            style: TextStyle(fontSize: 13, color: p.sobreNegro),
                          ),
                        ),
                        Text(
                          Fmt.porcentaje(
                            total > 0 ? e.value / total : 0,
                            decimales: 0,
                          ),
                          style: TextStyle(
                            fontFamily: TemaApp.mono,
                            fontSize: 12,
                            color: p.sobreNegro2,
                          ),
                        ),
                        const SizedBox(width: Esp.md),
                        Text(
                          Fmt.pesosCompacto(e.value),
                          style: TextStyle(
                            fontFamily: TemaApp.mono,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.sobreNegro,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Esp.sm - 2),
                    BarraProgreso(
                      valor: total > 0 ? e.value / total : 0,
                      color: p.acento,
                      fondo: p.negroElevado,
                      alto: 6,
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
      padding: const EdgeInsets.all(Esp.md + 2),
      child: Row(
        children: [
          IconoEnCirculo(
            icono: g.categoria.icono,
            tamano: 44,
            color: p.tinta,
            fondo: p.superficieHundida,
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
