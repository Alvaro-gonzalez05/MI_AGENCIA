import '../../ui/confirmacion.dart';

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
import 'importar_vehiculos.dart';

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
    final margen = MediaQuery.sizeOf(context).width < Corte.tablet
        ? Esp.lg + 4
        : Esp.xxl;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: asincrono.value?.any((v) => !v.vendido) == true
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(context, ref),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Nueva unidad'),
            )
          : null,
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
              accion: Wrap(
                spacing: Esp.md,
                runSpacing: Esp.md,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _abrirFormulario(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Cargar un vehículo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _abrirImportacion(context, ref),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Importar de un archivo'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, 104),
            itemCount: activos.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: Esp.sm + 2),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Esp.xs),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Esp.md + 2,
                          vertical: 6,
                        ),
                        decoration: ShapeDecoration(
                          color: p.negro,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          '${activos.length} unidad'
                          '${activos.length == 1 ? '' : 'es'} en el predio',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.sobreNegro,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // La importacion vive aca y no en el FAB porque es algo
                      // que se hace una vez, al empezar, y despues nunca mas:
                      // el boton de todos los dias es "Nueva unidad".
                      TextButton.icon(
                        onPressed: () => _abrirImportacion(context, ref),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                        label: const Text('Importar'),
                      ),
                    ],
                  ),
                );
              }
              final fila = _Fila(vehiculo: activos[i - 1]);
              return i > 20 ? fila : Aparecer(indice: i, child: fila);
            },
          );
        },
      ),
    );
  }

  /// Carga masiva leyendo la planilla, el PDF o la foto que trajo la agencia.
  static Future<void> _abrirImportacion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final cargo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const ImportarVehiculos(),
      ),
    );
    if (cargo == true && context.mounted) {
      ref.invalidate(inventarioProvider);
    }
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
      confirmarGuardado(
        context,
        inicial == null ? 'Unidad dada de alta' : 'Cambios guardados',
      );
    }
  }
}

class _Fila extends ConsumerStatefulWidget {
  const _Fila({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  ConsumerState<_Fila> createState() => _FilaState();
}

class _FilaState extends ConsumerState<_Fila> {
  bool _eliminando = false;

  Future<void> _eliminar() async {
    final v = widget.vehiculo;
    final ok = await confirmarAccion(
      context,
      titulo: 'Dar de baja ${v.codigo}',
      descripcion:
          '${v.titulo} dejará de aparecer en el inventario. Su historial de '
          'gastos, precios y operaciones se conserva.',
      confirmar: 'Dar de baja',
      icono: Icons.remove_circle_outline_rounded,
      peligrosa: true,
    );
    if (!ok || !mounted) return;

    setState(() => _eliminando = true);
    try {
      await ref.read(repositorioProvider).eliminarVehiculo(v.id);
      if (!mounted) return;
      confirmarEliminado(context, '${v.codigo} fue dado de baja');
      ref.invalidate(inventarioProvider);
      ref.invalidate(gastosProvider);
      ref.invalidate(gastosDeVehiculoProvider(v.id));
      ref.invalidate(preciosProvider);
      ref.invalidate(ventasProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = widget.vehiculo;

    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(Esp.md, Esp.md, Esp.sm, Esp.md),
      onTap: () => context.go('/inventario/${v.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: v.alerta.lavado(p),
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 23,
              color: v.alerta.color(p),
            ),
          ),
          const SizedBox(width: Esp.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${v.codigo} · ${v.subtitulo}'
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
              Text('Ingresó', style: TextStyle(fontSize: 11, color: p.tinta3)),
              Text(
                Fmt.fecha(v.fechaIngreso),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: p.tinta2,
                ),
              ),
            ],
          ),
          const SizedBox(width: Esp.sm),
          if (_eliminando)
            const SizedBox.square(
              dimension: 38,
              child: Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              key: Key('vehiculo-menu-${v.id}'),
              tooltip: 'Acciones de ${v.codigo}',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (accion) {
                if (accion == 'editar') {
                  PantallaVehiculos._abrirFormulario(
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
                  );
                } else if (accion == 'eliminar') {
                  _eliminar();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar unidad'),
                  ),
                ),
                PopupMenuItem(
                  key: Key('vehiculo-eliminar-${v.id}'),
                  value: 'eliminar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: p.critico),
                    title: Text(
                      'Dar de baja',
                      style: TextStyle(color: p.critico),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
