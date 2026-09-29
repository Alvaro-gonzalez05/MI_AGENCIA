import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/ventas.dart';
import '../../ui/componentes.dart';

/// Estadísticas del negocio (pantalla del diseño nuevo).
///
/// Responde cuatro preguntas que la agencia se hace todos los meses:
/// cuánto vendí, cuánto gané de verdad, cuánto tardo en vender y en qué se
/// me va la plata. Todo sale de lo que ya está cargado: ventas, gastos e
/// inventario.

enum PeriodoEstadistica {
  mes('Este mes'),
  tres('Últimos 3 meses'),
  anio('Este año');

  const PeriodoEstadistica(this.etiqueta);
  final String etiqueta;

  DateTime get desde {
    final hoy = DateTime.now();
    return switch (this) {
      PeriodoEstadistica.mes => DateTime(hoy.year, hoy.month, 1),
      PeriodoEstadistica.tres => DateTime(hoy.year, hoy.month - 2, 1),
      PeriodoEstadistica.anio => DateTime(hoy.year, 1, 1),
    };
  }

  /// Cuántos meses dibuja el gráfico.
  int get meses => switch (this) {
    PeriodoEstadistica.mes => 6,
    PeriodoEstadistica.tres => 6,
    PeriodoEstadistica.anio => 12,
  };
}

final _periodoProvider = NotifierProvider<_Periodo, PeriodoEstadistica>(
  _Periodo.new,
);

class _Periodo extends Notifier<PeriodoEstadistica> {
  @override
  PeriodoEstadistica build() => PeriodoEstadistica.anio;

  void poner(PeriodoEstadistica v) => state = v;
}

class PantallaEstadisticas extends ConsumerWidget {
  const PantallaEstadisticas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;
    final enFila = ancho >= Corte.escritorio;

    final periodo = ref.watch(_periodoProvider);
    final ventas = ref.watch(ventasProvider).value ?? const <Venta>[];
    final gastos = ref.watch(gastosProvider).value ?? const [];
    final inventario =
        ref.watch(inventarioProvider).value ?? const <VehiculoInventario>[];

    final desde = periodo.desde;
    final delPeriodo = ventas
        .where((v) => !v.fechaVenta.isBefore(desde))
        .toList();
    final gastosPeriodo = gastos
        .where((g) => !g.fecha.isBefore(desde))
        .fold<double>(0, (s, g) => s + g.importe);

    final ganancia = delPeriodo.fold<double>(
      0,
      (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
    );
    final diasPromedio = delPeriodo.isEmpty
        ? null
        : delPeriodo.fold<int>(0, (s, v) => s + (v.diasEnStock ?? 0)) /
              delPeriodo.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, Esp.xxl),
      children: [
        Aparecer(
          child: CabeceraPantalla(
            titulo: 'Estadísticas',
            subtitulo: 'Rendimiento del negocio, ventas y tiempos de rotación',
            // Wrap y no una fila deslizable: adentro de la cabecera el ancho
            // es libre, y una fila que se desplaza no sabe cuánto medir.
            accion: Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                for (final e in PeriodoEstadistica.values)
                  ChipSeleccion(
                    etiqueta: e.etiqueta,
                    activo: periodo == e,
                    onTap: () => ref.read(_periodoProvider.notifier).poner(e),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Esp.lg),

        Aparecer(
          indice: 1,
          child: _Tarjetas(
            vendidos: delPeriodo.length,
            ganancia: ganancia,
            diasPromedio: diasPromedio,
            gastos: gastosPeriodo,
          ),
        ),
        const SizedBox(height: Esp.lg),

        Aparecer(
          indice: 2,
          child: GraficoVentasPorMes(ventas: ventas, meses: periodo.meses),
        ),
        const SizedBox(height: Esp.lg),

        if (enFila)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Aparecer(
                    indice: 3,
                    child: _LoQueMasVendes(ventas: delPeriodo),
                  ),
                ),
                const SizedBox(width: Esp.lg),
                Expanded(
                  child: Aparecer(
                    indice: 4,
                    child: _LosQueMasTardan(inventario: inventario),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Aparecer(indice: 3, child: _LoQueMasVendes(ventas: delPeriodo)),
          const SizedBox(height: Esp.lg),
          Aparecer(indice: 4, child: _LosQueMasTardan(inventario: inventario)),
        ],
        const SizedBox(height: Esp.lg),

        Aparecer(
          indice: 5,
          child: _GananciaPorMes(ventas: ventas, meses: periodo.meses),
        ),
      ],
    );
  }
}

class _Tarjetas extends StatelessWidget {
  const _Tarjetas({
    required this.vendidos,
    required this.ganancia,
    required this.diasPromedio,
    required this.gastos,
  });

  final int vendidos;
  final double ganancia;
  final double? diasPromedio;
  final double gastos;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return LayoutBuilder(
      builder: (context, r) {
        final columnas = r.maxWidth >= 980
            ? 4
            : r.maxWidth >= 560
            ? 2
            : 1;
        final ancho = (r.maxWidth - Esp.md * (columnas - 1)) / columnas;
        final tarjetas = [
          TarjetaMetrica(
            titulo: 'Autos vendidos',
            valor: '$vendidos',
            detalle: vendidos == 0 ? 'Todavía ninguno' : 'en el período',
            icono: Icons.directions_car_filled_outlined,
          ),
          TarjetaMetrica(
            titulo: 'Ganancia real (USD)',
            valor: Fmt.pesosCompacto(ganancia),
            detalle: 'Ajustada por dólar',
            detalleColor: ganancia < 0 ? p.critico : p.bien,
            icono: Icons.payments_outlined,
            resaltada: true,
          ),
          TarjetaMetrica(
            titulo: 'Tardás en vender',
            valor: diasPromedio == null
                ? Fmt.sinDato
                : Fmt.dias(diasPromedio!.round()),
            detalle: 'en promedio por auto',
            icono: Icons.schedule_rounded,
          ),
          TarjetaMetrica(
            titulo: 'Gastos del período',
            valor: Fmt.pesosCompacto(gastos),
            detalle: 'Repuestos, taller y trámites',
            detalleColor: p.critico,
            icono: Icons.receipt_long_outlined,
          ),
        ];
        // Alto fijo: la tarjeta reparte su contenido con spaceBetween, y
        // para eso necesita saber hasta dónde llega.
        return Wrap(
          spacing: Esp.md,
          runSpacing: Esp.md,
          children: [
            for (final t in tarjetas)
              SizedBox(width: ancho, height: 178, child: t),
          ],
        );
      },
    );
  }
}

/// Serie mensual: los últimos [meses] meses, del más viejo al más nuevo.
List<({DateTime mes, int unidades, double ganancia})> _serie(
  List<Venta> ventas,
  int meses,
) {
  final hoy = DateTime.now();
  return [
    for (var i = meses - 1; i >= 0; i--)
      () {
        final mes = DateTime(hoy.year, hoy.month - i, 1);
        final delMes = ventas.where(
          (v) =>
              v.fechaVenta.year == mes.year && v.fechaVenta.month == mes.month,
        );
        return (
          mes: mes,
          unidades: delMes.length,
          ganancia: delMes.fold<double>(
            0,
            (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
          ),
        );
      }(),
  ];
}

const _nombreMes = [
  'Ene',
  'Feb',
  'Mar',
  'Abr',
  'May',
  'Jun',
  'Jul',
  'Ago',
  'Sep',
  'Oct',
  'Nov',
  'Dic',
];

/// Barras de unidades vendidas por mes. El mes en curso va en ámbar.
///
/// Es publica porque el Inicio muestra el mismo grafico: tener dos copias
/// era garantia de que se fueran pareciendo cada vez menos.
class GraficoVentasPorMes extends StatelessWidget {
  const GraficoVentasPorMes({
    super.key,
    required this.ventas,
    required this.meses,
  });

  final List<Venta> ventas;
  final int meses;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final serie = _serie(ventas, meses);
    final maximo = serie.fold<int>(0, (m, x) => math.max(m, x.unidades));
    final mejor = serie.isEmpty
        ? null
        : serie.reduce((a, b) => b.unidades >= a.unidades ? b : a);
    final hoy = DateTime.now();

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Ventas por mes',
            descripcion: maximo == 0
                ? 'Todavía no hay ventas cargadas en el período'
                : '${mejor!.unidades} ${mejor.unidades == 1 ? 'entrega' : 'entregas'} '
                      'en ${_nombreMes[mejor.mes.month - 1]}, que fue el mejor mes',
          ),
          const SizedBox(height: Esp.xl),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final x in serie) ...[
                  Expanded(
                    child: _Barra(
                      valor: x.unidades,
                      maximo: math.max(maximo, 1),
                      etiqueta: _nombreMes[x.mes.month - 1],
                      actual:
                          x.mes.year == hoy.year && x.mes.month == hoy.month,
                    ),
                  ),
                  if (x != serie.last) const SizedBox(width: Esp.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: Esp.md),
          Row(
            children: [
              _Referencia(color: p.bordeFuerte, texto: 'Meses anteriores'),
              const SizedBox(width: Esp.lg),
              _Referencia(color: p.acento, texto: 'Mes en curso'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.valor,
    required this.maximo,
    required this.etiqueta,
    required this.actual,
  });

  final int valor, maximo;
  final String etiqueta;
  final bool actual;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$valor',
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: actual ? p.tinta : p.tinta2,
          ),
        ),
        const SizedBox(height: Esp.xs),
        Expanded(
          child: LayoutBuilder(
            builder: (context, r) {
              // Una barra en cero igual deja una marca: si no, no se
              // distingue un mes sin ventas de un mes sin datos.
              final alto = math.max(4.0, r.maxHeight * valor / maximo);
              return Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: Duracion.lenta,
                  curve: Curves.easeOutCubic,
                  height: alto,
                  decoration: BoxDecoration(
                    color: actual ? p.acento : p.bordeFuerte,
                    borderRadius: BorderRadius.circular(Curva.sm),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Esp.sm),
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 14,
            fontWeight: actual ? FontWeight.w700 : FontWeight.w400,
            color: actual ? p.tinta : p.tinta3,
          ),
        ),
      ],
    );
  }
}

class _Referencia extends StatelessWidget {
  const _Referencia({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: Esp.sm - 2),
        Text(texto, style: TextStyle(fontSize: 14, color: p.tinta3)),
      ],
    );
  }
}

/// Ranking de marcas vendidas.
class _LoQueMasVendes extends StatelessWidget {
  const _LoQueMasVendes({required this.ventas});

  final List<Venta> ventas;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final porMarca = <String, int>{};
    for (final v in ventas) {
      // El título viene como "Marca Modelo": la marca es la primera palabra.
      final titulo = (v.vehiculoTitulo ?? '').trim();
      if (titulo.isEmpty) continue;
      final marca = titulo.split(' ').first;
      porMarca[marca] = (porMarca[marca] ?? 0) + 1;
    }
    final ranking = porMarca.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maximo = ranking.isEmpty ? 1 : ranking.first.value;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Lo que más vendés',
            descripcion: 'Marcas con más entregas en el período',
          ),
          const SizedBox(height: Esp.lg),
          if (ranking.isEmpty)
            Text(
              'Cuando cargues ventas, acá vas a ver qué marcas se te mueven '
              'más rápido.',
              style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.45),
            )
          else
            for (var i = 0; i < math.min(5, ranking.length); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i + 1}. ${ranking[i].key}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.tinta,
                            ),
                          ),
                        ),
                        Text(
                          '${ranking[i].value} '
                          '${ranking[i].value == 1 ? 'auto' : 'autos'}',
                          style: TextStyle(
                            fontFamily: TemaApp.mono,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: i == 0 ? p.acentoTexto : p.tinta2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Esp.xs),
                    BarraProgreso(
                      valor: ranking[i].value / maximo,
                      color: i == 0 ? p.acento : p.bordeFuerte,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Las unidades que más tiempo llevan sin venderse.
class _LosQueMasTardan extends StatelessWidget {
  const _LosQueMasTardan({required this.inventario});

  final List<VehiculoInventario> inventario;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final parados = inventario.where((v) => !v.vendido).toList()
      ..sort((a, b) => b.diasEnStock.compareTo(a.diasEnStock));
    final top = parados.take(3).toList();

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Los que más tardan',
            descripcion: 'Conviene revisarles el precio o la publicación',
          ),
          const SizedBox(height: Esp.lg),
          if (top.isEmpty)
            Text(
              'No hay unidades en stock.',
              style: TextStyle(fontSize: 15, color: p.tinta2),
            )
          else
            for (final v in top)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.tinta,
                            ),
                          ),
                          Text(
                            '${v.codigo}${v.patente == null ? '' : ' · ${v.patente}'}',
                            style: TextStyle(fontSize: 14, color: p.tinta3),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${Fmt.dias(v.diasEnStock)} en el salón',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: v.alerta.color(p),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Esp.sm),
                    OutlinedButton(
                      onPressed: () => context.go('/inventario/${v.id}'),
                      child: const Text('Ver ficha'),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Ganancia mes a mes, en línea.
class _GananciaPorMes extends StatelessWidget {
  const _GananciaPorMes({required this.ventas, required this.meses});

  final List<Venta> ventas;
  final int meses;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final serie = _serie(ventas, meses);
    final valores = serie.map((x) => x.ganancia).toList();
    final hayAlgo = valores.any((v) => v != 0);

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Ganancia por mes',
            descripcion: hayAlgo
                ? 'Ganancia real (ajustada por dólar) de las unidades entregadas'
                : 'Se dibuja cuando haya ventas cargadas',
          ),
          const SizedBox(height: Esp.xl),
          SizedBox(
            height: 200,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LineaPintor(
                valores: valores,
                etiquetas: [for (final x in serie) _nombreMes[x.mes.month - 1]],
                linea: p.acentoTexto,
                relleno: p.acento.withValues(alpha: 0.18),
                grilla: p.borde,
                texto: p.tinta3,
                punto: p.acento,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaPintor extends CustomPainter {
  _LineaPintor({
    required this.valores,
    required this.etiquetas,
    required this.linea,
    required this.relleno,
    required this.grilla,
    required this.texto,
    required this.punto,
  });

  final List<double> valores;
  final List<String> etiquetas;
  final Color linea, relleno, grilla, texto, punto;

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;
    const margenAbajo = 26.0;
    final alto = size.height - margenAbajo;
    final maximo = valores.reduce(math.max);
    final minimo = math.min(0.0, valores.reduce(math.min));
    final rango = (maximo - minimo).abs() < 1 ? 1.0 : maximo - minimo;

    double x(int i) => valores.length == 1
        ? size.width / 2
        : i * size.width / (valores.length - 1);
    double y(double v) => alto - (v - minimo) / rango * (alto - 16) - 8;

    // Tres líneas de guía: sin ellas no se sabe si la curva sube mucho o poco.
    final lapizGrilla = Paint()
      ..color = grilla
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final yy = 8 + i * (alto - 16) / 2;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), lapizGrilla);
    }

    final camino = Path()..moveTo(x(0), y(valores.first));
    for (var i = 1; i < valores.length; i++) {
      camino.lineTo(x(i), y(valores[i]));
    }

    final bajo = Path.from(camino)
      ..lineTo(x(valores.length - 1), alto)
      ..lineTo(x(0), alto)
      ..close();
    canvas.drawPath(bajo, Paint()..color = relleno);

    canvas.drawPath(
      camino,
      Paint()
        ..color = linea
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < valores.length; i++) {
      canvas.drawCircle(
        Offset(x(i), y(valores[i])),
        i == valores.length - 1 ? 6 : 4,
        Paint()..color = i == valores.length - 1 ? punto : linea,
      );
    }

    for (var i = 0; i < etiquetas.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: etiquetas[i],
          style: TextStyle(fontSize: 13, color: texto, fontFamily: 'Atkinson'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (x(i) - tp.width / 2).clamp(0, size.width - tp.width),
          size.height - tp.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_LineaPintor otro) =>
      otro.valores != valores || otro.linea != linea;
}
