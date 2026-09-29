import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/gastos.dart';
import '../../dominio/modelos.dart';
import '../../dominio/ventas.dart';
import '../../ui/componentes.dart';
import '../estadisticas/pantalla_estadisticas.dart';

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
    final esMovil = ancho < Corte.tablet;

    // Las tarjetas se adaptan solas: 4 en escritorio, 2 en tablet y movil,
    // 1 solo en telefonos muy angostos.
    final columnas = ancho >= 1100
        ? 4
        : ancho >= 360
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

    final metricas = [
      TarjetaMetrica(
        titulo: 'Capital inmovilizado',
        valor: Fmt.pesosCompacto(r.capitalInmovilizado),
        detalle: '${r.unidadesEnStock} unidades en stock',
        icono: Icons.account_balance_wallet_rounded,
        resaltada: true,
        onTap: () => context.go('/inventario'),
      ),
      TarjetaMetrica(
        titulo: 'Ganancia potencial',
        valor: Fmt.pesosCompacto(r.gananciaPotencial),
        detalle: 'Margen promedio ${Fmt.porcentaje(r.margenPromedio)}',
        detalleColor: r.margenPromedio < cfg.margenObjetivo
            ? p.observar
            : p.bien,
        icono: Icons.trending_up_rounded,
      ),
      TarjetaMetrica(
        titulo: 'Días promedio en stock',
        valor: r.diasPromedioStock.toStringAsFixed(0),
        detalle: 'Objetivo: menos de ${cfg.diasAmarillo} días',
        detalleColor: r.diasPromedioStock > cfg.diasAmarillo
            ? p.atencion
            : p.bien,
        icono: Icons.schedule_rounded,
      ),
      TarjetaMetrica(
        titulo: 'Unidades en rojo',
        valor: '${r.criticos}',
        detalle: 'Más de ${cfg.diasRojo} días sin venderse',
        detalleColor: r.criticos > 0 ? p.critico : p.tinta3,
        icono: Icons.warning_amber_rounded,
        onTap: () => context.go('/inventario'),
      ),
    ];

    final antiguedad = _ListaAtencion(
      titulo: 'Mayor antigüedad',
      descripcion: 'Cada día parado cuesta plata',
      vehiculos: enRojo.take(5).toList(),
      valor: (v) => Fmt.dias(v.diasEnStock),
      color: (v) => p.critico,
    );
    final margen = _ListaAtencion(
      titulo: 'Margen bajo el mínimo',
      descripcion: 'Por debajo de ${Fmt.porcentaje(cfg.margenMinimo)}',
      vehiculos: bajoMargen.take(5).toList(),
      valor: (v) => Fmt.porcentaje(v.margenActual),
      color: (v) => v.margenActual < 0 ? p.critico : p.observar,
    );

    final ventas = ref.watch(ventasProvider).value ?? const <Venta>[];
    final gastos = ref.watch(gastosProvider).value ?? const [];
    final interesados = ref.watch(interesadosProvider).value ?? const [];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        esMovil ? Esp.lg + 4 : Esp.xxl,
        Esp.sm,
        esMovil ? Esp.lg + 4 : Esp.xl,
        Esp.xxl,
      ),
      children: [
        // El saludo con el resumen del mes: es lo primero que se mira al
        // abrir la app a la mañana (pantalla "Inicio" del diseño).
        Aparecer(
          child: _Saludo(
            usuario: ref.watch(usuarioProvider),
            agencia: ref.watch(miAgenciaProvider).value?.nombre,
            ventas: ventas,
            gastos: gastos,
          ),
        ),
        const SizedBox(height: Esp.lg + 2),

        Aparecer(
          indice: 1,
          child: _ParaAtenderHoy(
            inventario: inventario,
            interesados: interesados,
            cfg: cfg,
          ),
        ),
        const SizedBox(height: Esp.lg + 2),

        Aparecer(
          indice: 2,
          child: GraficoVentasPorMes(ventas: ventas, meses: 6),
        ),
        const SizedBox(height: Esp.lg + 2),

        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            mainAxisSpacing: Esp.md + 2,
            crossAxisSpacing: Esp.md + 2,
            // 162 dejaba las tarjetas 5 px cortas y Flutter pintaba la
            // franja de overflow. El contenido es de alto fijo (todos los
            // textos van a una linea), asi que alcanza con darle el alto real.
            mainAxisExtent: columnas == 1 ? 166 : 178,
          ),
          children: [
            for (var i = 0; i < metricas.length; i++)
              Aparecer(indice: i, child: metricas[i]),
          ],
        ),

        const SizedBox(height: Esp.lg + 2),
        Aparecer(
          indice: 4,
          child: _GananciaReal(resumen: r, cfg: cfg),
        ),

        const SizedBox(height: Esp.lg + 2),
        Aparecer(
          indice: 5,
          child: _DistribucionRotacion(inventario: inventario, cfg: cfg),
        ),

        const SizedBox(height: Esp.lg + 2),
        Aparecer(indice: 6, child: _AutosEnVenta(inventario: inventario)),

        const SizedBox(height: Esp.lg + 2),
        if (ancho >= Corte.escritorio)
          Aparecer(
            indice: 7,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: antiguedad),
                  const SizedBox(width: Esp.lg + 2),
                  Expanded(child: margen),
                ],
              ),
            ),
          )
        else ...[
          Aparecer(indice: 7, child: antiguedad),
          const SizedBox(height: Esp.lg + 2),
          Aparecer(indice: 8, child: margen),
        ],
      ],
    );
  }
}

/// La tarjeta que justifica el producto: lo mismo en nominal y en real.
/// Va en negro porque es la que hay que leer primero.
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
        color: p.sobreNegro,
      ),
      _BloqueGanancia(
        etiqueta: 'Ganancia real (USD)',
        valor: Fmt.pesos(resumen.gananciaRealizadaIpc),
        nota: 'Ajustada por el dólar oficial de cada compra',
        color: p.acento,
        grande: true,
      ),
      _BloqueGanancia(
        etiqueta: 'En dólares',
        valor: Fmt.dolares(resumen.gananciaRealizadaUsd),
        nota: 'Al dólar oficial del día de cada venta',
        color: p.sobreNegro,
      ),
    ];

    return Tarjeta(
      destacada: true,
      padding: EdgeInsets.all(angosto ? Esp.lg + 4 : Esp.xl + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.insights_rounded,
                tamano: 38,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Ganancia de las unidades vendidas',
                  descripcion: 'Nominal contra real, ajustada por dólar',
                  sobreNegro: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.xl),
          if (angosto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final b in bloques) ...[b, const SizedBox(height: Esp.lg)],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bloques.length; i++) ...[
                  Expanded(child: bloques[i]),
                  if (i < bloques.length - 1)
                    Container(
                      width: 1,
                      height: 58,
                      margin: const EdgeInsets.symmetric(horizontal: Esp.lg),
                      color: p.negroBorde,
                    ),
                ],
              ],
            ),
          const SizedBox(height: Esp.xl),
          BarraProgreso(
            valor: proporcion,
            color: p.acento,
            fondo: p.negroElevado,
            alto: 10,
          ),
          const SizedBox(height: Esp.md),
          Text(
            resumen.gananciaRealizada <= 0
                ? 'Todavía no hay ventas cargadas.'
                : perdida >= 0
                ? 'Medida en dólares, la ganancia es ${Fmt.pesos(perdida)} '
                      'menor que en pesos: queda el '
                      '${Fmt.porcentaje(proporcion, decimales: 0)} de la nominal.'
                : 'Medida en dólares, la ganancia es ${Fmt.pesos(-perdida)} '
                      'mayor que en pesos.',
            style: TextStyle(fontSize: 14, color: p.sobreNegro2, height: 1.5),
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
    this.grande = false,
  });

  final String etiqueta, valor, nota;
  final Color color;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 13, color: p.sobreNegro2)),
        const SizedBox(height: Esp.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: grande ? 28 : 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: Esp.xs),
        Text(
          nota,
          style: TextStyle(
            fontSize: 13,
            color: p.sobreNegro2.withValues(alpha: 0.8),
          ),
        ),
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

    int cuantos(AlertaRotacion a) => enStock.where((v) => v.alerta == a).length;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Antigüedad del stock',
            descripcion:
                '${enStock.length} unidad${enStock.length == 1 ? '' : 'es'} '
                'en el predio',
          ),
          const SizedBox(height: Esp.lg + 2),
          // Barra apilada: una sola linea dice toda la salud del inventario.
          // Crece de izquierda a derecha al entrar a la pantalla.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, hijo) => ClipRRect(
              borderRadius: BorderRadius.circular(Curva.completo),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: t,
                child: hijo,
              ),
            ),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (alerta, _) in grupos)
                    if (cuantos(alerta) > 0)
                      Expanded(
                        flex: cuantos(alerta),
                        child: Container(
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: alerta.color(p),
                            borderRadius: BorderRadius.circular(Curva.completo),
                          ),
                        ),
                      ),
                  // Evita que la barra colapse cuando no hay nada cargado.
                  if (enStock.isEmpty)
                    Expanded(child: Container(color: p.superficieHundida)),
                ],
              ),
            ),
          ),
          const SizedBox(height: Esp.lg + 2),
          LayoutBuilder(
            builder: (context, restricciones) {
              final porFila = restricciones.maxWidth >= 640 ? 4 : 2;
              final anchoItem =
                  (restricciones.maxWidth - Esp.sm * (porFila - 1)) / porFila;
              return Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [
                  for (final (alerta, rango) in grupos)
                    SizedBox(
                      width: anchoItem,
                      child: _ItemLeyenda(
                        color: alerta.color(p),
                        etiqueta: alerta.etiqueta,
                        rango: rango,
                        cantidad: cuantos(alerta),
                      ),
                    ),
                ],
              );
            },
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
  });

  final Color color;
  final String etiqueta, rango;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md + 2),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: Esp.sm - 2),
              Expanded(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.tinta2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm - 2),
          Text(
            '$cantidad',
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: p.tinta,
            ),
          ),
          Text(
            rango,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: p.tinta3),
          ),
        ],
      ),
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
          CabeceraBloque(
            titulo: titulo,
            descripcion: descripcion,
            accion: 'Ver todo',
            onAccion: () => context.go('/inventario'),
          ),
          const SizedBox(height: Esp.md),
          if (vehiculos.isEmpty)
            Container(
              padding: const EdgeInsets.all(Esp.lg),
              decoration: BoxDecoration(
                color: p.bienLavado,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: p.bien),
                  const SizedBox(width: Esp.sm),
                  Text(
                    'Ninguna unidad en esta situación.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: p.tinta2,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final v in vehiculos)
              Padding(
                padding: const EdgeInsets.only(top: Esp.sm),
                child: Material(
                  color: p.superficieHundida,
                  borderRadius: BorderRadius.circular(Curva.md),
                  child: InkWell(
                    onTap: () => context.go('/inventario/${v.id}'),
                    borderRadius: BorderRadius.circular(Curva.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Esp.sm + 2,
                        vertical: Esp.sm,
                      ),
                      child: Row(
                        children: [
                          IconoEnCirculo(
                            icono: Icons.directions_car_filled_rounded,
                            tamano: 36,
                            color: p.tinta,
                            fondo: p.superficie,
                          ),
                          const SizedBox(width: Esp.md),
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
                                  v.codigo,
                                  style: TextStyle(
                                    fontFamily: TemaApp.mono,
                                    fontSize: 13,
                                    color: p.tinta3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Esp.sm),
                          Pastilla(
                            texto: valor(v),
                            color: color(v),
                            lavado: color(v).withValues(alpha: 0.14),
                            conPunto: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Saludo y resumen del mes, en la tarjeta oscura del diseño.
class _Saludo extends StatelessWidget {
  const _Saludo({
    required this.usuario,
    required this.agencia,
    required this.ventas,
    required this.gastos,
  });

  final Usuario? usuario;
  final String? agencia;
  final List<Venta> ventas;
  final List<Gasto> gastos;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final hoy = DateTime.now();
    final desde = DateTime(hoy.year, hoy.month, 1);
    final delMes = ventas.where((v) => !v.fechaVenta.isBefore(desde)).toList();
    final mesAnterior = ventas
        .where(
          (v) =>
              v.fechaVenta.isBefore(desde) &&
              !v.fechaVenta.isBefore(DateTime(hoy.year, hoy.month - 1, 1)),
        )
        .length;
    final ganancia = delMes.fold<double>(
      0,
      (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
    );
    final gastoMes = gastos
        .where((g) => !g.fecha.isBefore(desde))
        .fold<double>(0, (s, g) => s + g.importe);

    final saludo = hoy.hour < 13
        ? 'Buen día'
        : hoy.hour < 20
        ? 'Buenas tardes'
        : 'Buenas noches';
    final nombre = (usuario?.nombre ?? '').split(' ').first;

    return Tarjeta(
      destacada: true,
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Fmt.fechaLarga(hoy).toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: p.acento,
            ),
          ),
          const SizedBox(height: Esp.xs),
          Text(
            nombre.isEmpty ? '¡$saludo!' : '¡$saludo, $nombre!',
            style: TextStyle(
              fontFamily: TemaApp.titulo,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: p.sobreNegro,
            ),
          ),
          if (agencia != null) ...[
            const SizedBox(height: 2),
            Text(
              agencia!,
              style: TextStyle(fontSize: 16, color: p.sobreNegro2),
            ),
          ],
          const SizedBox(height: Esp.xl),
          LayoutBuilder(
            builder: (context, r) {
              final enFila = r.maxWidth >= 720;
              final tarjetas = [
                _DatoDelMes(
                  etiqueta: 'VENDIDOS ESTE MES',
                  valor:
                      '${delMes.length} '
                      '${delMes.length == 1 ? 'auto' : 'autos'}',
                  nota: mesAnterior == 0
                      ? 'El mes pasado no hubo entregas'
                      : delMes.length == mesAnterior
                      ? 'Igual que el mes pasado'
                      : delMes.length > mesAnterior
                      ? '${delMes.length - mesAnterior} más que el mes pasado'
                      : '${mesAnterior - delMes.length} menos que el mes pasado',
                  color: p.bien,
                ),
                _DatoDelMes(
                  etiqueta: 'GANANCIA DEL MES',
                  valor: Fmt.pesosCompacto(ganancia),
                  nota: 'Real, ajustada por dólar',
                  color: p.acento,
                ),
                _DatoDelMes(
                  etiqueta: 'GASTOS DEL MES',
                  valor: Fmt.pesosCompacto(gastoMes),
                  nota: 'Repuestos, taller y trámites',
                  color: p.critico,
                ),
              ];
              return enFila
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tarjetas.length; i++) ...[
                            if (i > 0) const SizedBox(width: Esp.sm),
                            Expanded(child: tarjetas[i]),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < tarjetas.length; i++) ...[
                          if (i > 0) const SizedBox(height: Esp.sm),
                          tarjetas[i],
                        ],
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _DatoDelMes extends StatelessWidget {
  const _DatoDelMes({
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
    return Container(
      padding: const EdgeInsets.all(Esp.md + 2),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.negroBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: p.sobreNegro2,
            ),
          ),
          const SizedBox(height: Esp.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: TemaApp.titulo,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: p.sobreNegro,
              ),
            ),
          ),
          const SizedBox(height: Esp.xs),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: Esp.sm - 2),
              Expanded(
                child: Text(
                  nota,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 14,
                    color: p.sobreNegro2,
                    height: 1.3,
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

/// "Para atender hoy": lo que no puede esperar, sacado de lo que ya está
/// cargado. No es una agenda todavía —eso viene en la tanda de tareas—,
/// pero sí lo que el sistema puede deducir solo.
class _ParaAtenderHoy extends StatelessWidget {
  const _ParaAtenderHoy({
    required this.inventario,
    required this.interesados,
    required this.cfg,
  });

  final List<VehiculoInventario> inventario;
  final List<Interesado> interesados;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final hoy = DateTime.now();

    final pendientes = <_Pendiente>[];

    // 1. Los interesados con una acción anotada que ya venció.
    for (final i in interesados) {
      final cuando = i.proximaAccionFecha;
      if (cuando == null || i.proximaAccion == null) continue;
      if (cuando.isAfter(DateTime(hoy.year, hoy.month, hoy.day))) continue;
      final atraso = DateTime(
        hoy.year,
        hoy.month,
        hoy.day,
      ).difference(DateTime(cuando.year, cuando.month, cuando.day)).inDays;
      pendientes.add(
        _Pendiente(
          icono: Icons.alarm_rounded,
          color: atraso > 0 ? p.critico : p.observar,
          titulo: i.nombre,
          detalle: i.proximaAccion!,
          marca: atraso == 0 ? 'Para hoy' : 'Hace ${Fmt.dias(atraso)}',
          accion: 'Ver ficha',
          onAccion: () => context.go('/interesados'),
          orden: 100 + atraso,
        ),
      );
    }

    // 2. Las unidades que llevan demasiado tiempo paradas.
    final paradas =
        inventario
            .where((v) => !v.vendido && v.alerta == AlertaRotacion.critico)
            .toList()
          ..sort((a, b) => b.diasEnStock.compareTo(a.diasEnStock));
    for (final v in paradas.take(3)) {
      pendientes.add(
        _Pendiente(
          icono: Icons.hourglass_bottom_rounded,
          color: p.critico,
          titulo: v.titulo,
          detalle:
              'Lleva ${Fmt.dias(v.diasEnStock)} en el salón. Conviene revisar '
              'el precio o volver a publicarla.',
          marca: '${v.diasEnStock} días',
          accion: 'Ver ficha',
          onAccion: () => context.go('/inventario/${v.id}'),
          orden: 50 + v.diasEnStock,
        ),
      );
    }

    // 3. Consultas al BCRA vencidas: financiar con un dato viejo es el
    //    riesgo que el semáforo vino a evitar.
    final vencidas = interesados
        .where((i) => i.consulta?.vencida == true)
        .take(2);
    for (final i in vencidas) {
      pendientes.add(
        _Pendiente(
          icono: Icons.update_rounded,
          color: p.observar,
          titulo: i.nombre,
          detalle:
              'La consulta al BCRA venció. Volvé a consultarla antes de '
              'ofrecerle financiación.',
          marca: 'BCRA',
          accion: 'Ver ficha',
          onAccion: () => context.go('/interesados'),
          orden: 10,
        ),
      );
    }

    pendientes.sort((a, b) => b.orden.compareTo(a.orden));
    final lista = pendientes.take(4).toList();

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Para atender hoy',
                  descripcion: lista.isEmpty
                      ? 'No hay nada pendiente: está todo al día'
                      : 'Ordenado por lo que más urge',
                ),
              ),
              if (lista.isNotEmpty)
                Pastilla(
                  texto:
                      '${lista.length} '
                      '${lista.length == 1 ? 'pendiente' : 'pendientes'}',
                  color: p.observar,
                  lavado: p.observarLavado,
                ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          if (lista.isEmpty)
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 22, color: p.bien),
                const SizedBox(width: Esp.sm),
                Expanded(
                  child: Text(
                    'Ninguna unidad pasada de plazo y ninguna acción vencida '
                    'con los interesados.',
                    style: TextStyle(fontSize: 15, color: p.tinta2),
                  ),
                ),
              ],
            )
          else
            for (final x in lista)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.sm),
                child: Container(
                  padding: const EdgeInsets.all(Esp.md),
                  decoration: BoxDecoration(
                    color: p.superficieHundida,
                    borderRadius: BorderRadius.circular(Curva.md),
                  ),
                  child: Row(
                    children: [
                      IconoEnCirculo(
                        icono: x.icono,
                        tamano: 40,
                        color: x.color,
                        fondo: x.color.withValues(alpha: 0.14),
                      ),
                      const SizedBox(width: Esp.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    x.titulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: p.tinta,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Esp.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Esp.sm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: x.color.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(
                                      Curva.completo,
                                    ),
                                  ),
                                  child: Text(
                                    x.marca,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: x.color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              x.detalle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: p.tinta2,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Esp.sm),
                      OutlinedButton(
                        onPressed: x.onAccion,
                        child: Text(x.accion),
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

class _Pendiente {
  _Pendiente({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
    required this.marca,
    required this.accion,
    required this.onAccion,
    required this.orden,
  });

  final IconData icono;
  final Color color;
  final String titulo, detalle, marca, accion;
  final VoidCallback onAccion;

  /// Cuánto urge. Más alto, más arriba.
  final int orden;
}

/// "Tus autos en venta": las unidades publicadas, como las muestra el
/// diseño, con su patente y su precio.
class _AutosEnVenta extends StatelessWidget {
  const _AutosEnVenta({required this.inventario});

  final List<VehiculoInventario> inventario;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final enStock = inventario.where((v) => !v.vendido).toList()
      ..sort((a, b) => a.diasEnStock.compareTo(b.diasEnStock));

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Tus autos en venta',
                  descripcion: enStock.isEmpty
                      ? 'Todavía no hay unidades en stock'
                      : '${enStock.length} '
                            '${enStock.length == 1 ? 'unidad publicada' : 'unidades publicadas'}',
                ),
              ),
              TextButton.icon(
                onPressed: () => context.go('/inventario'),
                icon: const Text('Ver todos'),
                label: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          if (enStock.isEmpty)
            Text(
              'Cargá la primera unidad desde el botón "+" de la barra de abajo.',
              style: TextStyle(fontSize: 15, color: p.tinta2),
            )
          else
            LayoutBuilder(
              builder: (context, r) {
                final columnas = r.maxWidth >= 1000
                    ? 4
                    : r.maxWidth >= 700
                    ? 3
                    : r.maxWidth >= 420
                    ? 2
                    : 1;
                final ancho = (r.maxWidth - Esp.md * (columnas - 1)) / columnas;
                return Wrap(
                  spacing: Esp.md,
                  runSpacing: Esp.md,
                  children: [
                    for (final v in enStock.take(columnas * 2))
                      SizedBox(
                        width: ancho,
                        child: _AutoChico(vehiculo: v),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AutoChico extends StatelessWidget {
  const _AutoChico({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    return Material(
      color: p.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.md),
      child: InkWell(
        onTap: () => context.go('/inventario/${v.id}'),
        borderRadius: BorderRadius.circular(Curva.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: v.alerta.lavado(p),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Curva.md),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.directions_car_filled_rounded,
                  size: 32,
                  color: v.alerta.color(p),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Esp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${v.anio}${v.km == null ? '' : ' · ${Fmt.km(v.km)}'}',
                    style: TextStyle(fontSize: 14, color: p.tinta3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: p.tinta,
                    ),
                  ),
                  if (v.version != null)
                    Text(
                      v.version!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.tinta2),
                    ),
                  const SizedBox(height: Esp.sm),
                  Text(
                    Fmt.pesos(v.precioActual),
                    style: TextStyle(
                      fontFamily: TemaApp.titulo,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: p.tinta,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
