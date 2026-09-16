import '../../ui/confirmacion.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/precios.dart';
import '../../ui/componentes.dart';
import 'formulario_precio.dart';

/// Historial de cambios de precio.
///
/// La lectura que importa no es "cuánto vale", sino **cuántas veces hubo que
/// bajarle el precio a una unidad**. Tres bajas seguidas dicen que se compró
/// mal, y eso solo se ve mirando el historial junto.
class PantallaPrecios extends ConsumerWidget {
  const PantallaPrecios({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(preciosProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(context),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Cambiar precio'),
      ),
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudo cargar el historial',
          descripcion: '$e',
        ),
        data: (cambios) {
          if (cambios.isEmpty) {
            return EstadoVacio(
              icono: Icons.sell_outlined,
              titulo: 'Todavía no hubo cambios de precio',
              descripcion:
                  'Cuando ajustes el precio de una unidad va a quedar acá, con '
                  'el motivo, para entender después por qué se movió.',
              accion: FilledButton.icon(
                onPressed: () => abrirFormulario(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Cambiar un precio'),
              ),
            );
          }

          final bajas = cambios.where((c) => c.esBaja).length;
          final porUnidad = <String, int>{};
          for (final c in cambios) {
            final k = c.vehiculoCodigo ?? c.vehiculoId;
            porUnidad[k] = (porUnidad[k] ?? 0) + 1;
          }
          final masTocadas = porUnidad.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return ListView(
            padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.xl, Esp.xl, 96),
            children: [
              _Resumen(
                total: cambios.length,
                bajas: bajas,
                masTocada: masTocadas.isNotEmpty && masTocadas.first.value > 1
                    ? masTocadas.first
                    : null,
                titulo: _tituloDe(cambios, masTocadas),
              ),
              const SizedBox(height: Esp.lg),
              for (final c in cambios) ...[
                _Fila(cambio: c),
                const SizedBox(height: Esp.sm),
              ],
            ],
          );
        },
      ),
    );
  }

  static String? _tituloDe(
    List<CambioPrecio> cambios,
    List<MapEntry<String, int>> ranking,
  ) {
    if (ranking.isEmpty) return null;
    final codigo = ranking.first.key;
    return cambios
        .where((c) => (c.vehiculoCodigo ?? c.vehiculoId) == codigo)
        .firstOrNull
        ?.vehiculoTitulo;
  }

  static Future<void> abrirFormulario(BuildContext context) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FormularioPrecio(),
      ),
    );
    if (guardado == true && context.mounted) {
      confirmarGuardado(context, 'Precio actualizado');
    }
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.total,
    required this.bajas,
    required this.masTocada,
    required this.titulo,
  });

  final int total;
  final int bajas;
  final MapEntry<String, int>? masTocada;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Movimientos de precio',
            descripcion:
                'Bajar el precio es resignar margen: conviene verlo junto',
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: _Dato(
                  etiqueta: 'Cambios',
                  valor: '$total',
                  color: p.tinta,
                ),
              ),
              Expanded(
                child: _Dato(
                  etiqueta: 'Fueron bajas',
                  valor: '$bajas',
                  color: bajas > total / 2 ? p.observar : p.tinta,
                ),
              ),
            ],
          ),
          if (masTocada != null) ...[
            const SizedBox(height: Esp.lg),
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.observarLavado,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.trending_down, size: 16, color: p.observar),
                  const SizedBox(width: Esp.md),
                  Expanded(
                    child: Text(
                      'A ${masTocada!.key}${titulo != null ? ' · $titulo' : ''} '
                      'le tocaste el precio ${masTocada!.value} veces. '
                      'Cuando una unidad necesita varios ajustes, el problema '
                      'suele estar en el precio de compra.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.tinta2,
                        height: 1.45,
                      ),
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

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.color,
  });

  final String etiqueta, valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.cambio});

  final CambioPrecio cambio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = cambio;
    final v = c.variacion;
    final color = v == null
        ? p.neutro
        : v < 0
        ? p.critico
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.md),
      child: Row(
        children: [
          IconoEnCirculo(
            icono: v == null
                ? Icons.flag_outlined
                : v < 0
                ? Icons.south_east
                : Icons.north_east,
            color: color,
          ),
          const SizedBox(width: Esp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.vehiculoCodigo ?? ''} · ${c.vehiculoTitulo ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                if (c.motivo != null && c.motivo!.isNotEmpty)
                  Text(
                    c.motivo!,
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
              Row(
                children: [
                  if (c.precioAnterior != null) ...[
                    Text(
                      Fmt.pesosCompacto(c.precioAnterior),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 11.5,
                        color: p.tinta3,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: Esp.sm - 2),
                  ],
                  Text(
                    Fmt.pesosCompacto(c.precioNuevo),
                    style: TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.tinta,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (v != null)
                    Text(
                      Fmt.porcentajeConSigno(v),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  const SizedBox(width: Esp.sm - 2),
                  Text(
                    Fmt.fecha(c.fecha),
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
        ],
      ),
    );
  }
}
