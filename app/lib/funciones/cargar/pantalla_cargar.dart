import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../ui/componentes.dart';
import '../../ui/shell/secciones.dart';
import '../vehiculos/formulario_vehiculo.dart';
import '../vehiculos/importar_vehiculos.dart';

/// "¿Qué querés cargar?": la sección Cargar del diseño.
///
/// Es una de las cinco secciones de la app, no una hoja que sube: todo lo
/// que se da de alta a mano entra por acá, y por eso el resto del menú no
/// necesita cuatro entradas sueltas (vehículos, gastos, precios, ventas).
class PantallaCargar extends ConsumerWidget {
  const PantallaCargar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;

    void irA(String ruta) => context.go(ruta);

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, Esp.xxl),
      children: [
        Aparecer(child: _Opciones(onIr: irA)),
        const SizedBox(height: Esp.lg),
        Aparecer(indice: 1, child: _UltimoQueCargaste(onIr: irA)),
      ],
    );
  }
}

/// Las cinco opciones del diseño: dos grandes y tres chicas.
class _Opciones extends StatelessWidget {
  const _Opciones({required this.onIr});

  final void Function(String ruta) onIr;

  @override
  Widget build(BuildContext context) {
    final grandes = [
      OpcionCarga(
        icono: Icons.add_rounded,
        titulo: 'Un auto solo',
        descripcion: 'Completás los datos de a uno, paso a paso.',
        accion: 'Comenzar ahora',
        destacada: true,
        // Derecho al formulario: el que toca acá ya eligió, no hace falta
        // pasar por la lista de unidades para volver a decidir.
        onTap: () => Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const FormularioVehiculo(),
          ),
        ),
      ),
      OpcionCarga(
        icono: Icons.description_outlined,
        titulo: 'Varios autos de una vez',
        descripcion:
            'Subí una planilla, un PDF o la foto del cuaderno de inventario.',
        accion: 'Subir lista',
        destacada: true,
        onTap: () {
          // Abre la importación derecho: el que entra por acá ya viene con
          // el archivo en la mano.
          Navigator.of(context).push<bool>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const ImportarVehiculos(),
            ),
          );
        },
      ),
    ];

    final chicas = [
      OpcionCarga(
        icono: Secciones.gastos.icono,
        titulo: 'Un gasto',
        descripcion: 'Reparación, lavadero, batería o trámites de gestoría.',
        accion: 'Anotar gasto',
        onTap: () => onIr(Secciones.gastos.ruta),
      ),
      OpcionCarga(
        icono: Secciones.ventas.icono,
        titulo: 'Una venta',
        descripcion: 'Registrar la entrega y cerrar la operación.',
        accion: 'Cerrar venta',
        onTap: () => onIr(Secciones.ventas.ruta),
      ),
      OpcionCarga(
        icono: Secciones.precios.icono,
        titulo: 'Cambiar precios',
        descripcion: 'Actualizar los valores de venta de las unidades.',
        accion: 'Actualizar',
        onTap: () => onIr(Secciones.precios.ruta),
      ),
    ];

    return LayoutBuilder(
      builder: (context, r) {
        final enFila = r.maxWidth >= 640;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (enFila)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < grandes.length; i++) ...[
                      if (i > 0) const SizedBox(width: Esp.md),
                      Expanded(child: grandes[i]),
                    ],
                  ],
                ),
              )
            else
              for (var i = 0; i < grandes.length; i++) ...[
                if (i > 0) const SizedBox(height: Esp.md),
                grandes[i],
              ],
            const SizedBox(height: Esp.md),
            if (enFila)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < chicas.length; i++) ...[
                      if (i > 0) const SizedBox(width: Esp.md),
                      Expanded(child: chicas[i]),
                    ],
                  ],
                ),
              )
            else
              for (var i = 0; i < chicas.length; i++) ...[
                if (i > 0) const SizedBox(height: Esp.md),
                chicas[i],
              ],
          ],
        );
      },
    );
  }
}

/// Una de las opciones de "¿Qué querés cargar?".
/// Una de las tarjetas de "¿Qué querés cargar?". Es pública porque el
/// formulario de alta la vuelve a usar cuando pregunta si se carga una
/// unidad o una lista: la misma pregunta se ve igual en los dos lados.
class OpcionCarga extends StatelessWidget {
  const OpcionCarga({
    super.key,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.accion,
    required this.onTap,
    this.destacada = false,
  });

  final IconData icono;
  final String titulo, descripcion, accion;
  final VoidCallback onTap;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconoEnCirculo(
            icono: icono,
            tamano: destacada ? 52 : 44,
            color: destacada ? p.acentoTinta : p.acentoTexto,
            fondo: destacada ? p.acento : p.acentoLavado,
          ),
          const SizedBox(height: Esp.md),
          Text(titulo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            descripcion,
            style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.35),
          ),
          const SizedBox(height: Esp.md),
          // Alineado a la izquierda pero con el ancho de la tarjeta como
          // tope: con la letra en A++ el boton no entra en una sola linea y
          // el texto se tiene que poder recortar.
          Align(
            alignment: Alignment.centerLeft,
            child: destacada
                ? FilledButton.icon(
                    onPressed: onTap,
                    icon: Flexible(
                      child: Text(
                        accion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    label: const Icon(Icons.arrow_forward_rounded, size: 20),
                  )
                : TextButton.icon(
                    onPressed: onTap,
                    icon: Flexible(
                      child: Text(
                        accion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    label: const Icon(Icons.arrow_forward_rounded, size: 20),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Lo último que cargaste": la actividad reciente, con el atajo para
/// corregir lo que haya salido mal.
class _UltimoQueCargaste extends ConsumerWidget {
  const _UltimoQueCargaste({required this.onIr});

  final void Function(String ruta) onIr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final inventario = ref.watch(inventarioProvider).value ?? const [];
    final gastos = ref.watch(gastosProvider).value ?? const [];
    final ventas = ref.watch(ventasProvider).value ?? const [];

    // Una sola lista con lo último de cada cosa, ordenada por fecha.
    final movimientos =
        <({DateTime cuando, IconData icono, String texto, String ruta})>[
          for (final v in inventario.take(20))
            (
              cuando: v.fechaIngreso,
              icono: Icons.directions_car_filled_rounded,
              texto: '${v.titulo}${v.patente == null ? '' : ' · ${v.patente}'}',
              ruta: '/inventario/${v.id}',
            ),
          for (final g in gastos.take(20))
            (
              cuando: g.fecha,
              icono: Icons.receipt_long_outlined,
              texto:
                  'Gasto: ${g.descripcion?.isNotEmpty == true ? g.descripcion! : g.categoria.etiqueta}'
                  ' · ${Fmt.pesos(g.importe)}',
              ruta: Secciones.gastos.ruta,
            ),
          for (final v in ventas.take(20))
            (
              cuando: v.fechaVenta,
              icono: Icons.sell_outlined,
              texto:
                  'Venta: ${v.vehiculoTitulo ?? v.vehiculoCodigo ?? 'una unidad'}',
              ruta: Secciones.ventas.ruta,
            ),
        ]..sort((a, b) => b.cuando.compareTo(a.cuando));

    if (movimientos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 20, color: p.tinta2),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Text(
                'Lo último que cargaste',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Pastilla(
              texto: 'Actividad reciente',
              color: p.tinta2,
              lavado: p.superficieHundida,
              conPunto: false,
            ),
          ],
        ),
        const SizedBox(height: Esp.sm),
        Tarjeta(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final m in movimientos.take(4))
                Padding(
                  padding: const EdgeInsets.all(Esp.md),
                  child: Row(
                    children: [
                      IconoEnCirculo(
                        icono: m.icono,
                        tamano: 40,
                        color: p.tinta2,
                        fondo: p.superficieHundida,
                      ),
                      const SizedBox(width: Esp.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.texto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              Fmt.fecha(m.cuando),
                              style: TextStyle(fontSize: 14, color: p.tinta3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Esp.sm),
                      OutlinedButton(
                        onPressed: () => onIr(m.ruta),
                        child: const Text('Corregir'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
