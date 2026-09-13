import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/ventas.dart';
import '../../ui/componentes.dart';
import 'formulario_venta.dart';

/// Ventas cerradas.
///
/// Muestra siempre el par nominal / real. Una agencia que mira solo la
/// columna en pesos cree que gana el doble de lo que gana.
class PantallaVentas extends ConsumerWidget {
  const PantallaVentas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(ventasProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(context),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Registrar venta'),
      ),
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar las ventas',
          descripcion: '$e',
        ),
        data: (ventas) {
          if (ventas.isEmpty) {
            return EstadoVacio(
              icono: Icons.check_circle_outline,
              titulo: 'Todavía no hay ventas registradas',
              descripcion:
                  'Al cargar una venta, la unidad sale del stock sola y recién '
                  'ahí el margen deja de ser una estimación.',
              accion: FilledButton.icon(
                onPressed: () => abrirFormulario(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Registrar una venta'),
              ),
            );
          }

          final nominal = ventas.fold<double>(
            0,
            (s, v) => s + (v.ganancia ?? 0),
          );
          final real = ventas.fold<double>(
            0,
            (s, v) => s + (v.gananciaReal ?? 0),
          );
          final dias = ventas
              .where((v) => v.diasEnStock != null)
              .map((v) => v.diasEnStock!)
              .toList();
          final promedio = dias.isEmpty
              ? null
              : dias.reduce((a, b) => a + b) / dias.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.xl, Esp.xl, 96),
            children: [
              _Resumen(
                cantidad: ventas.length,
                nominal: nominal,
                real: real,
                diasPromedio: promedio,
              ),
              const SizedBox(height: Esp.lg),
              for (final v in ventas) ...[
                _Fila(venta: v),
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
        builder: (_) => const FormularioVenta(),
      ),
    );
    if (guardado == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venta registrada — la unidad salió del stock'),
        ),
      );
    }
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.cantidad,
    required this.nominal,
    required this.real,
    required this.diasPromedio,
  });

  final int cantidad;
  final double nominal;
  final double real;
  final double? diasPromedio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final erosion = nominal - real;
    final proporcion = nominal > 0 ? real / nominal : 0.0;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo:
                '$cantidad venta${cantidad == 1 ? '' : 's'} cerrada'
                '${cantidad == 1 ? '' : 's'}',
            descripcion: diasPromedio == null
                ? null
                : 'Rotación promedio: ${diasPromedio!.toStringAsFixed(0)} días',
          ),
          const SizedBox(height: Esp.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ganancia nominal',
                      style: TextStyle(fontSize: 11.5, color: p.tinta3),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Fmt.pesos(nominal),
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: p.tinta2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Real, descontada la inflación',
                      style: TextStyle(fontSize: 11.5, color: p.tinta3),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Fmt.pesos(real),
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: real < 0 ? p.critico : p.bien,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          BarraProgreso(
            valor: proporcion.clamp(0, 1),
            color: real < 0 ? p.critico : p.bien,
          ),
          const SizedBox(height: Esp.md),
          Text(
            nominal <= 0
                ? 'Todavía no hay ganancia acumulada.'
                : 'La inflación se llevó ${Fmt.pesos(erosion)}: queda el '
                      '${Fmt.porcentaje(proporcion, decimales: 0)} del poder '
                      'de compra de esa ganancia.',
            style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.venta});

  final Venta venta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = venta;
    final real = v.gananciaReal;
    final color = real == null
        ? p.neutro
        : real < 0
        ? p.critico
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(icono: Icons.check_rounded, color: color),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v.vehiculoCodigo ?? ''} · ${v.vehiculoTitulo ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.tinta,
                      ),
                    ),
                    Text(
                      [
                        Fmt.fecha(v.fechaVenta),
                        if (v.diasEnStock != null)
                          '${Fmt.dias(v.diasEnStock)} en stock',
                        if (v.formaPago != null) v.formaPago!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.md),
              Text(
                Fmt.pesos(v.precioFinal),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.tinta,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Divider(color: p.borde, height: 1),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              Expanded(
                child: _Mini(
                  etiqueta: 'Ganancia',
                  valor: Fmt.pesosCompacto(v.ganancia),
                  color: (v.ganancia ?? 0) < 0 ? p.critico : p.tinta2,
                ),
              ),
              Expanded(
                child: _Mini(
                  etiqueta: 'Real (IPC)',
                  valor: Fmt.pesosCompacto(real),
                  color: color,
                ),
              ),
              Expanded(
                child: _Mini(
                  etiqueta: 'Margen',
                  valor: Fmt.porcentaje(v.margenReal),
                  color: p.tinta2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({
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
        Text(etiqueta, style: TextStyle(fontSize: 10.5, color: p.tinta3)),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
