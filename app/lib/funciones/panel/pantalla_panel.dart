import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventario = ref.watch(inventarioProvider);

    return inventario.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar el panel',
        descripcion: '$e',
      ),
      data: (inv) => _Contenido(inventario: inv),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.inventario});

  final List<VehiculoInventario> inventario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final r = ref.watch(resumenProvider);
    final cfg = ref.watch(configProvider);
    final ancho = MediaQuery.sizeOf(context).width;

    // Las tarjetas se adaptan solas: 4 en escritorio, 2 en tablet, 1 en movil.
    final columnas = ancho >= Corte.escritorio
        ? 4
        : ancho >= Corte.tablet
        ? 3
        : ancho >= Corte.movil
        ? 2
        : 1;

    final enRojo =
        inventario
            .where((v) => !v.vendido && v.alerta == AlertaRotacion.critico)
            .toList()
          ..sort((a, b) => b.diasEnStock.compareTo(a.diasEnStock));

    final bajoMargen =
        inventario
            .where((v) => !v.vendido && v.margenActual < cfg.margenMinimo)
            .toList()
          ..sort((a, b) => a.margenActual.compareTo(b.margenActual));

    return ListView(
      padding: const EdgeInsets.all(Esp.xl),
      children: [
        GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Esp.md,
          crossAxisSpacing: Esp.md,
          childAspectRatio: columnas == 1 ? 3.4 : 1.75,
          children: [
            TarjetaMetrica(
              titulo: 'Capital inmovilizado',
              valor: Fmt.pesosCompacto(r.capitalInmovilizado),
              detalle: '${r.unidadesEnStock} unidades en stock',
              icono: Icons.account_balance_wallet_outlined,
              onTap: () => context.go('/inventario'),
            ),
            TarjetaMetrica(
              titulo: 'Ganancia potencial',
              valor: Fmt.pesosCompacto(r.gananciaPotencial),
              detalle: 'Margen promedio ${Fmt.porcentaje(r.margenPromedio)}',
              detalleColor: r.margenPromedio < cfg.margenObjetivo
                  ? p.observar
                  : p.bien,
              icono: Icons.trending_up,
            ),
            TarjetaMetrica(
              titulo: 'Días promedio en stock',
              valor: r.diasPromedioStock.toStringAsFixed(0),
              detalle: 'Objetivo: menos de ${cfg.diasAmarillo} días',
              detalleColor: r.diasPromedioStock > cfg.diasAmarillo
                  ? p.atencion
                  : p.bien,
              icono: Icons.schedule,
            ),
            TarjetaMetrica(
              titulo: 'Unidades en rojo',
              valor: '${r.criticos}',
              detalle: 'Más de ${cfg.diasRojo} días sin venderse',
              detalleColor: r.criticos > 0 ? p.critico : p.tinta3,
              icono: Icons.warning_amber_rounded,
              onTap: () => context.go('/inventario'),
            ),
          ],
        ),

        const SizedBox(height: Esp.xl),
        _GananciaReal(resumen: r, cfg: cfg),

        const SizedBox(height: Esp.xl),
        _DistribucionRotacion(inventario: inventario, cfg: cfg),

        const SizedBox(height: Esp.xl),
        if (ancho >= Corte.escritorio)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ListaAtencion(
                    titulo: 'Mayor antigüedad',
                    descripcion: 'Cada día parado cuesta plata',
                    vehiculos: enRojo.take(5).toList(),
                    valor: (v) => Fmt.dias(v.diasEnStock),
                    color: (v) => p.critico,
                  ),
                ),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: _ListaAtencion(
                    titulo: 'Margen bajo el mínimo',
                    descripcion:
                        'Por debajo de ${Fmt.porcentaje(cfg.margenMinimo)}',
                    vehiculos: bajoMargen.take(5).toList(),
                    valor: (v) => Fmt.porcentaje(v.margenActual),
                    color: (v) => v.margenActual < 0 ? p.critico : p.observar,
                  ),
                ),
              ],
            ),
          )
        else ...[
          _ListaAtencion(
            titulo: 'Mayor antigüedad',
            descripcion: 'Cada día parado cuesta plata',
            vehiculos: enRojo.take(5).toList(),
            valor: (v) => Fmt.dias(v.diasEnStock),
            color: (v) => p.critico,
          ),
          const SizedBox(height: Esp.md),
          _ListaAtencion(
            titulo: 'Margen bajo el mínimo',
            descripcion: 'Por debajo de ${Fmt.porcentaje(cfg.margenMinimo)}',
            vehiculos: bajoMargen.take(5).toList(),
            valor: (v) => Fmt.porcentaje(v.margenActual),
            color: (v) => v.margenActual < 0 ? p.critico : p.observar,
          ),
        ],
        const SizedBox(height: Esp.xl),
      ],
    );
  }
}

/// La tarjeta que justifica el producto: lo mismo en nominal y en real.
class _GananciaReal extends StatelessWidget {
  const _GananciaReal({required this.resumen, required this.cfg});

  final ResumenAgencia resumen;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final perdida = resumen.gananciaRealizada - resumen.gananciaRealizadaIpc;
    final proporcion = resumen.gananciaRealizada > 0
        ? resumen.gananciaRealizadaIpc / resumen.gananciaRealizada
        : 0.0;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final bloques = [
      _BloqueGanancia(
        etiqueta: 'Ganancia nominal',
        valor: Fmt.pesos(resumen.gananciaRealizada),
        nota: 'Lo que dice la suma de las ventas',
        color: p.tinta,
      ),
      _BloqueGanancia(
        etiqueta: 'Ganancia real (IPC)',
        valor: Fmt.pesos(resumen.gananciaRealizadaIpc),
        nota: 'Descontada la inflación del período',
        color: p.bien,
      ),
      _BloqueGanancia(
        etiqueta: 'En dólares',
        valor: Fmt.dolares(resumen.gananciaRealizadaUsd),
        nota: 'Al tipo de cambio ${Fmt.pesos(cfg.tipoCambio)}',
        color: p.tinta2,
      ),
    ];

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('Ganancia de las unidades vendidas'),
          const SizedBox(height: Esp.lg),
          if (angosto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final b in bloques) ...[b, const SizedBox(height: Esp.lg)],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < bloques.length; i++) ...[
                  Expanded(child: bloques[i]),
                  if (i < bloques.length - 1)
                    Container(
                      width: 1,
                      height: 54,
                      margin: const EdgeInsets.symmetric(horizontal: Esp.lg),
                      color: p.borde,
                    ),
                ],
              ],
            ),
          const SizedBox(height: Esp.lg),
          BarraProgreso(valor: proporcion, color: p.bien, alto: 5),
          const SizedBox(height: Esp.md),
          Text(
            resumen.gananciaRealizada <= 0
                ? 'Todavía no hay ventas cargadas.'
                : 'La inflación se llevó ${Fmt.pesos(perdida)} de la ganancia '
                      'nominal: queda ${Fmt.porcentaje(proporcion, decimales: 0)} '
                      'de poder de compra real.',
            style: TextStyle(fontSize: 13, color: p.tinta2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _BloqueGanancia extends StatelessWidget {
  const _BloqueGanancia({
    required this.etiqueta,
    required this.valor,
    required this.nota,
    required this.color,
  });

  final String etiqueta, valor, nota;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 12.5, color: p.tinta3)),
        const SizedBox(height: Esp.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: Esp.xs),
        Text(nota, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
      ],
    );
  }
}

class _DistribucionRotacion extends StatelessWidget {
  const _DistribucionRotacion({required this.inventario, required this.cfg});

  final List<VehiculoInventario> inventario;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final enStock = inventario.where((v) => !v.vendido).toList();

    final grupos = <(AlertaRotacion, String)>[
      (AlertaRotacion.normal, 'Hasta ${cfg.diasVerde} días'),
      (AlertaRotacion.observar, '${cfg.diasVerde} a ${cfg.diasAmarillo}'),
      (AlertaRotacion.atencion, '${cfg.diasAmarillo} a ${cfg.diasRojo}'),
      (AlertaRotacion.critico, 'Más de ${cfg.diasRojo} días'),
    ];

    final total = enStock.isEmpty ? 1 : enStock.length;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('Antigüedad del stock'),
          const SizedBox(height: Esp.lg),
          // Barra apilada: una sola linea dice toda la salud del inventario.
          ClipRRect(
            borderRadius: BorderRadius.circular(Curva.completo),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final (alerta, _) in grupos)
                    Expanded(
                      flex: enStock.where((v) => v.alerta == alerta).length,
                      child: Container(color: alerta.color(p)),
                    ),
                  // Evita que la barra colapse cuando no hay nada cargado.
                  if (enStock.isEmpty)
                    Expanded(child: Container(color: p.superficieHundida)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Esp.lg),
          Wrap(
            spacing: Esp.xl,
            runSpacing: Esp.md,
            children: [
              for (final (alerta, rango) in grupos)
                _ItemLeyenda(
                  color: alerta.color(p),
                  etiqueta: alerta.etiqueta,
                  rango: rango,
                  cantidad: enStock.where((v) => v.alerta == alerta).length,
                  porcentaje:
                      enStock.where((v) => v.alerta == alerta).length / total,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  const _ItemLeyenda({
    required this.color,
    required this.etiqueta,
    required this.rango,
    required this.cantidad,
    required this.porcentaje,
  });

  final Color color;
  final String etiqueta, rango;
  final int cantidad;
  final double porcentaje;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Esp.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$cantidad',
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                const SizedBox(width: Esp.sm - 2),
                Text(
                  etiqueta,
                  style: TextStyle(fontSize: 12.5, color: p.tinta2),
                ),
              ],
            ),
            Text(rango, style: TextStyle(fontSize: 11, color: p.tinta3)),
          ],
        ),
      ],
    );
  }
}

class _ListaAtencion extends StatelessWidget {
  const _ListaAtencion({
    required this.titulo,
    required this.descripcion,
    required this.vehiculos,
    required this.valor,
    required this.color,
  });

  final String titulo, descripcion;
  final List<VehiculoInventario> vehiculos;
  final String Function(VehiculoInventario) valor;
  final Color Function(VehiculoInventario) color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EtiquetaSeccion(titulo),
          const SizedBox(height: Esp.xs),
          Text(descripcion, style: TextStyle(fontSize: 12, color: p.tinta3)),
          const SizedBox(height: Esp.lg),
          if (vehiculos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Esp.lg),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: p.bien),
                  const SizedBox(width: Esp.sm),
                  Text(
                    'Ninguna unidad en esta situación.',
                    style: TextStyle(fontSize: 13, color: p.tinta2),
                  ),
                ],
              ),
            )
          else
            for (final v in vehiculos)
              InkWell(
                onTap: () => context.go('/inventario/${v.id}'),
                borderRadius: BorderRadius.circular(Curva.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Esp.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          v.codigo,
                          style: TextStyle(
                            fontFamily: TemaApp.mono,
                            fontSize: 11.5,
                            color: p.tinta3,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: p.tinta),
                        ),
                      ),
                      Text(
                        valor(v),
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color(v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
