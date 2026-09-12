import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/alta_vehiculo.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import 'formulario_vehiculo.dart';

/// Carga de unidades.
///
/// Separada del Inventario a proposito: Inventario es para MIRAR el negocio
/// (margenes, rotacion, capital parado) y esta es para CARGAR. Mezclarlas
/// deja una tabla llena de columnas de analisis donde el que carga solo
/// necesita un boton.
class PantallaVehiculos extends ConsumerWidget {
  const PantallaVehiculos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final asincrono = ref.watch(inventarioProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context, ref),
        backgroundColor: p.acento,
        foregroundColor: p.acentoTinta,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Nueva unidad'),
      ),
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar las unidades',
          descripcion: '$e',
        ),
        data: (inv) {
          final activos = inv.where((v) => !v.vendido).toList()
            ..sort((a, b) => b.fechaIngreso.compareTo(a.fechaIngreso));

          if (activos.isEmpty) {
            return EstadoVacio(
              icono: Icons.directions_car_outlined,
              titulo: 'Todavía no hay unidades cargadas',
              descripcion:
                  'Cargá la primera y el sistema empieza a calcular costos, '
                  'márgenes y días en stock solo.',
              accion: FilledButton.icon(
                onPressed: () => _abrirFormulario(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Cargar un vehículo'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.xl, Esp.xl, 96),
            itemCount: activos.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: Esp.sm),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Esp.sm),
                  child: Text(
                    '${activos.length} unidad${activos.length == 1 ? '' : 'es'} '
                    'en el predio',
                    style: TextStyle(fontSize: 12.5, color: p.tinta3),
                  ),
                );
              }
              return _Fila(vehiculo: activos[i - 1]);
            },
          );
        },
      ),
    );
  }

  static Future<void> _abrirFormulario(
    BuildContext context,
    WidgetRef ref, {
    AltaVehiculo? inicial,
  }) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FormularioVehiculo(inicial: inicial),
      ),
    );

    if (guardado == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inicial == null ? 'Unidad dada de alta' : 'Cambios guardados',
          ),
        ),
      );
    }
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final v = vehiculo;

    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.md),
      onTap: () => context.go('/inventario/${v.id}'),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: v.alerta.color(p),
              borderRadius: BorderRadius.circular(Curva.completo),
            ),
          ),
          const SizedBox(width: Esp.md),
          SizedBox(
            width: 46,
            child: Text(
              v.codigo,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 12,
                color: p.tinta3,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                Text(
                  '${v.subtitulo}'
                  '${v.km != null ? ' · ${Fmt.km(v.km)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.tinta3),
                ),
              ],
            ),
          ),
          const SizedBox(width: Esp.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Ingresó',
                style: TextStyle(fontSize: 10.5, color: p.tinta3),
              ),
              Text(
                Fmt.fecha(v.fechaIngreso),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 12.5,
                  color: p.tinta2,
                ),
              ),
            ],
          ),
          const SizedBox(width: Esp.md),
          IconButton(
            tooltip: 'Editar',
            icon: Icon(Icons.edit_outlined, size: 18, color: p.tinta3),
            onPressed: () => PantallaVehiculos._abrirFormulario(
              context,
              ref,
              inicial: AltaVehiculo(
                id: v.id,
                codigo: v.codigo,
                marca: v.marca,
                modelo: v.modelo,
                anio: v.anio,
                version: v.version ?? '',
                km: v.km,
                patente: v.patente ?? '',
                fechaIngreso: v.fechaIngreso,
                fechaCompra: v.fechaCompra ?? v.fechaIngreso,
                precioCompra: v.precioCompra,
                precioObjetivo: v.precioObjetivo,
                estado: v.estado,
                observaciones: v.observaciones ?? '',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
