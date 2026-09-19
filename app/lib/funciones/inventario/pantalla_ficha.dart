import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/motor_calculo.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Ficha de una unidad: todo lo que se sabe de ella, mas los dos simuladores.
class PantallaFicha extends ConsumerWidget {
  const PantallaFicha({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(inventarioProvider);

    return asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar la ficha',
        descripcion: '$e',
      ),
      data: (inv) {
        final v = inv.where((x) => x.id == id).firstOrNull;
        if (v == null) {
          return EstadoVacio(
            icono: Icons.help_outline,
            titulo: 'Unidad no encontrada',
            descripcion: 'El vehículo $id no existe o fue dado de baja.',
            accion: FilledButton(
              onPressed: () => context.go('/inventario'),
              child: const Text('Volver al inventario'),
            ),
          );
        }
        return _Ficha(vehiculo: v, cfg: ref.watch(configProvider));
      },
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.vehiculo, required this.cfg});

  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho >= Corte.escritorio;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;
    final v = vehiculo;
    const hueco = SizedBox(height: Esp.lg);

    final izquierda = <Widget>[
      Aparecer(child: _Cabecera(vehiculo: v)),
      hueco,
      Aparecer(indice: 1, child: _Costos(vehiculo: v)),
      hueco,
      Aparecer(
        indice: 2,
        child: _GananciaReal(vehiculo: v, cfg: cfg),
      ),
    ];

    final derecha = <Widget>[
      Aparecer(
        indice: dosColumnas ? 1 : 3,
        child: _SimuladorPrecio(vehiculo: v, cfg: cfg),
      ),
      hueco,
      Aparecer(
        indice: dosColumnas ? 2 : 4,
        child: _SimuladorFinanciacion(vehiculo: v, cfg: cfg),
      ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, Esp.xxl),
      children: [
        Row(
          children: [
            BotonCircular(
              icono: Icons.arrow_back_rounded,
              tooltip: 'Volver al inventario',
              onTap: () => context.go('/inventario'),
            ),
            const SizedBox(width: Esp.md),
            Text(
              'Inventario',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: context.paleta.tinta2,
              ),
            ),
          ],
        ),
        const SizedBox(height: Esp.lg),
        if (dosColumnas)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Column(children: izquierda)),
              const SizedBox(width: Esp.lg),
              Expanded(flex: 2, child: Column(children: derecha)),
            ],
          )
        else
          Column(children: [...izquierda, hueco, ...derecha]),
      ],
    );
  }
}

/// Cabecera negra, como la ficha de un auto en una app de alquiler: el
/// titulo grande, el estado y tres datos clave en mosaicos.
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Tarjeta(
      destacada: true,
      padding: EdgeInsets.all(angosto ? Esp.lg + 4 : Esp.xl + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: p.acento,
                  borderRadius: BorderRadius.circular(Curva.md + 2),
                ),
                child: Icon(
                  Icons.directions_car_filled_rounded,
                  size: 28,
                  color: p.acentoTinta,
                ),
              ),
              const SizedBox(width: Esp.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.titulo,
                      style: TextStyle(
                        fontSize: angosto ? 21 : 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.2,
                        color: p.sobreNegro,
                      ),
                    ),
                    const SizedBox(height: Esp.xs),
                    Text(
                      '${v.codigo} · ${v.subtitulo}'
                      '${v.km != null ? ' · ${Fmt.km(v.km)}' : ''}',
                      style: TextStyle(fontSize: 13, color: p.sobreNegro2),
                    ),
                  ],
                ),
              ),
              if (!angosto) ...[
                const SizedBox(width: Esp.md),
                Pastilla(
                  texto: v.alerta.etiqueta,
                  color: v.alerta.color(p),
                  lavado: v.alerta.color(p).withValues(alpha: 0.18),
                ),
              ],
            ],
          ),
          if (angosto) ...[
            const SizedBox(height: Esp.md),
            Pastilla(
              texto: v.alerta.etiqueta,
              color: v.alerta.color(p),
              lavado: v.alerta.color(p).withValues(alpha: 0.18),
            ),
          ],
          const SizedBox(height: Esp.xl),
          Row(
            children: [
              Expanded(
                child: _Mosaico(
                  icono: Icons.schedule_rounded,
                  etiqueta: 'En stock',
                  valor: Fmt.dias(v.diasEnStock),
                  color: v.alerta.color(p),
                ),
              ),
              const SizedBox(width: Esp.sm + 2),
              Expanded(
                child: _Mosaico(
                  icono: Icons.sell_rounded,
                  etiqueta: 'Precio',
                  valor: Fmt.pesos(v.precioActual),
                  color: p.acento,
                ),
              ),
              const SizedBox(width: Esp.sm + 2),
              Expanded(
                child: _Mosaico(
                  icono: Icons.percent_rounded,
                  etiqueta: 'Margen',
                  valor: Fmt.porcentaje(v.margenActual),
                  color: v.margenActual < 0 ? p.critico : p.bien,
                ),
              ),
            ],
          ),
          if (v.observaciones != null && v.observaciones!.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Text(
              'Observaciones',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.sobreNegro,
              ),
            ),
            const SizedBox(height: Esp.xs),
            Text(
              v.observaciones!,
              style: TextStyle(fontSize: 13, color: p.sobreNegro2, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _Mosaico extends StatelessWidget {
  const _Mosaico({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.color,
  });

  final IconData icono;
  final String etiqueta, valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.negroBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 15, color: color),
          ),
          const SizedBox(height: Esp.sm + 2),
          Text(
            etiqueta,
            style: TextStyle(fontSize: 11.5, color: p.sobreNegro2),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Costos extends StatelessWidget {
  const _Costos({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Capital y costos',
            descripcion: 'Todo lo invertido en la unidad',
          ),
          const SizedBox(height: Esp.md),
          FilaDato(
            etiqueta: 'Precio de compra',
            valor: Fmt.pesos(v.precioCompra),
          ),
          FilaDato(
            etiqueta: 'Gastos acumulados (${v.cantidadGastos})',
            valor: Fmt.pesos(v.gastosAcum),
          ),
          _Resaltado(
            child: FilaDato(
              etiqueta: 'Costo total',
              valor: Fmt.pesos(v.costoTotal),
              destacado: true,
            ),
          ),
          FilaDato(
            etiqueta: 'Costo a valor de hoy (IPC)',
            valor: Fmt.pesos(v.costoTotalHoy),
            valorColor: p.observar,
          ),
          Divider(color: p.borde, height: Esp.lg),
          FilaDato(
            etiqueta: 'Ganancia estimada',
            valor: Fmt.pesos(v.gananciaEstimada),
            valorColor: v.gananciaEstimada < 0 ? p.critico : p.bien,
            destacado: true,
          ),
          FilaDato(
            etiqueta: 'Capital inmovilizado',
            valor: Fmt.pesos(v.capitalInmovilizado),
          ),
          FilaDato(
            etiqueta: 'Costo por día parado',
            valor: Fmt.pesos(
              v.diasEnStock > 0 ? v.costoTotal / v.diasEnStock : v.costoTotal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo hundido para la fila que resume un bloque.
class _Resaltado extends StatelessWidget {
  const _Resaltado({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: Esp.xs),
    padding: const EdgeInsets.symmetric(horizontal: Esp.md),
    decoration: BoxDecoration(
      color: context.paleta.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.sm + 2),
    ),
    child: child,
  );
}

class _GananciaReal extends StatelessWidget {
  const _GananciaReal({required this.vehiculo, required this.cfg});
  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final enRojo = v.gananciaRealIpc < 0;
    final color = enRojo ? p.critico : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: enRojo
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                tamano: 38,
                color: color,
                fondo: color.withValues(alpha: 0.14),
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Ganancia real',
                  descripcion: 'Ajustada por inflación',
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MontoDual(
                  pesos: v.gananciaRealIpc,
                  tipoCambio: cfg.tipoCambio,
                  tamano: 24,
                  color: color,
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Margen real',
                      style: TextStyle(fontSize: 11.5, color: p.tinta3),
                    ),
                    Text(
                      Fmt.porcentaje(
                        v.precioActual > 0
                            ? (v.precioActual - v.costoTotalHoy) /
                                  v.precioActual
                            : 0,
                      ),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          Text(
            enRojo
                ? 'A precio de hoy, esta unidad pierde plata una vez descontada '
                      'la inflación acumulada desde que entró.'
                : 'Es lo que queda después de descontar la inflación acumulada '
                      'desde que la unidad entró al stock.',
            style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Numero grande que anima entre valores al mover un slider.
class _CifraAnimada extends StatelessWidget {
  const _CifraAnimada({
    required this.valor,
    required this.formato,
    required this.estilo,
  });

  final double valor;
  final String Function(double) formato;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: valor),
    duration: Duracion.media,
    curve: Curves.easeOutCubic,
    builder: (_, x, _) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(formato(x), style: estilo),
    ),
  );
}

/// Simulador de precio. Vive en Dart, no en SQL, porque recalcula a cada
/// movimiento del slider y es un "que pasaria si" que no se persiste.
class _SimuladorPrecio extends StatefulWidget {
  const _SimuladorPrecio({required this.vehiculo, required this.cfg});
  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  State<_SimuladorPrecio> createState() => _SimuladorPrecioState();
}

class _SimuladorPrecioState extends State<_SimuladorPrecio> {
  late double _margen = widget.cfg.margenObjetivo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = widget.vehiculo;

    final exacto = Motor.precioParaMargen(v.costoTotal, _margen);
    final sugerido = Motor.redondearArriba(exacto, widget.cfg.redondeo);
    final diferencia = sugerido - v.precioActual;
    final ajuste = v.precioActual > 0 ? sugerido / v.precioActual - 1 : 0.0;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.tune_rounded,
                tamano: 38,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Simulador de precio',
                  descripcion: 'Elegí el margen y te da el precio',
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),

          // Resultado en una pildora amarilla: es lo que se viene a buscar.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Esp.lg + 2),
            decoration: BoxDecoration(
              color: p.acento,
              borderRadius: BorderRadius.circular(Curva.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Precio a publicar',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: p.acentoTinta.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                _CifraAnimada(
                  valor: sugerido,
                  formato: Fmt.pesos,
                  estilo: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: p.acentoTinta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Text(
                'Margen deseado',
                style: TextStyle(fontSize: 13, color: p.tinta2),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Esp.md,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  color: p.negro,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  Fmt.porcentaje(_margen, decimales: 0),
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.acento,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _margen,
            min: 0,
            max: 0.60,
            divisions: 60,
            onChanged: (x) => setState(() => _margen = x),
          ),
          FilaDato(etiqueta: 'Precio exacto', valor: Fmt.pesos(exacto)),
          FilaDato(
            etiqueta: 'Diferencia vs. actual',
            valor: '${diferencia >= 0 ? '+' : ''}${Fmt.pesos(diferencia)}',
            valorColor: diferencia > 0 ? p.bien : p.critico,
          ),
          FilaDato(
            etiqueta: 'Ajuste necesario',
            valor: Fmt.porcentajeConSigno(ajuste),
            valorColor: ajuste.abs() < 0.02 ? p.tinta2 : p.observar,
          ),
          const SizedBox(height: Esp.sm),
          AnimatedSwitcher(
            duration: Duracion.media,
            child: Container(
              key: ValueKey(
                ajuste.abs() < 0.02
                    ? 0
                    : ajuste > 0
                    ? 1
                    : -1,
              ),
              width: double.infinity,
              padding: const EdgeInsets.all(Esp.md + 2),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 17,
                    color: p.tinta2,
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      ajuste.abs() < 0.02
                          ? 'El precio actual ya está alineado con ese margen.'
                          : ajuste > 0
                          ? 'Habría que subir el precio '
                                '${Fmt.porcentaje(ajuste)} para alcanzar ese '
                                'margen.'
                          : 'Se puede bajar el precio '
                                '${Fmt.porcentaje(ajuste.abs())} y todavía '
                                'alcanzar ese margen.',
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
          ),
        ],
      ),
    );
  }
}

class _SimuladorFinanciacion extends StatefulWidget {
  const _SimuladorFinanciacion({required this.vehiculo, required this.cfg});
  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  State<_SimuladorFinanciacion> createState() => _SimuladorFinanciacionState();
}

class _SimuladorFinanciacionState extends State<_SimuladorFinanciacion> {
  int _cuotas = 12;
  late double _tasa = widget.cfg.tasaFinanciacionMensual;

  /// Cuánto se financia. Arranca en el precio entero, pero casi nadie
  /// financia el 100%: lo habitual es que el comprador entregue algo
  /// (checklist del cliente, punto 2.2).
  late double _monto = widget.vehiculo.precioActual;

  late final TextEditingController _montoCtrl = TextEditingController(
    text: _monto.round().toString(),
  );

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  double get _precio => widget.vehiculo.precioActual;
  double get _anticipo => (_precio - _monto).clamp(0, _precio);

  void _ponerMonto(double monto) {
    final acotado = monto.clamp(0, _precio).toDouble();
    setState(() => _monto = acotado);
    _montoCtrl.value = TextEditingValue(
      text: acotado.round().toString(),
      selection: TextSelection.collapsed(
        offset: acotado.round().toString().length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final r = Motor.financiacion(
      monto: _monto,
      cuotas: _cuotas,
      tasaMensual: _tasa,
    );

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.calendar_month_rounded,
                tamano: 38,
                color: p.sobreNegro,
                fondo: p.negro,
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Simulador de financiación',
                  descripcion: 'Interés directo sobre el capital',
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Text(
            'Es como se vende en el rubro: “$_cuotas cuotas fijas de…”.',
            style: TextStyle(fontSize: 12, color: p.tinta3, height: 1.4),
          ),
          const SizedBox(height: Esp.lg),

          // Cuánto se financia, y de ahí sale el anticipo.
          CampoFormulario(
            etiqueta: 'Monto a financiar',
            ayuda: 'El resto lo pone el comprador de anticipo',
            error: _monto <= 0 ? 'Tiene que ser mayor a cero.' : null,
            hijo: TextFormField(
              controller: _montoCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontFamily: TemaApp.mono, fontSize: 16),
              onChanged: (t) {
                final n = double.tryParse(t) ?? 0;
                // Se acota al precio, pero sin reescribir el campo mientras
                // escribe: pisar el texto en cada tecla es insoportable.
                setState(() => _monto = n > _precio ? _precio : n);
              },
              decoration: InputDecoration(
                prefixText: r'$',
                prefixStyle: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 16,
                  color: p.tinta3,
                ),
              ),
            ),
          ),
          const SizedBox(height: Esp.sm),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final pct in const [0.0, 0.2, 0.3, 0.5])
                ChipSeleccion(
                  etiqueta: pct == 0
                      ? 'Sin anticipo'
                      : '${(pct * 100).round()}% de anticipo',
                  activo: (_anticipo - _precio * pct).abs() < 1,
                  onTap: () => _ponerMonto(_precio * (1 - pct)),
                ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          FilaDato(
            etiqueta: 'Anticipo del comprador',
            valor: Fmt.pesos(_anticipo),
            valorColor: p.tinta2,
          ),

          const SizedBox(height: Esp.lg),
          Text('Cuotas', style: TextStyle(fontSize: 13, color: p.tinta2)),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              for (final n in [6, 12, 18, 24]) ...[
                Expanded(
                  child: _BotonCuota(
                    n: n,
                    activo: _cuotas == n,
                    onTap: () => setState(() => _cuotas = n),
                  ),
                ),
                if (n != 24) const SizedBox(width: Esp.sm),
              ],
            ],
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Text(
                'Tasa mensual',
                style: TextStyle(fontSize: 13, color: p.tinta2),
              ),
              const Spacer(),
              Text(
                Fmt.porcentaje(_tasa),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.tinta,
                ),
              ),
            ],
          ),
          Slider(
            value: _tasa,
            min: 0,
            max: 0.20,
            divisions: 40,
            onChanged: (x) => setState(() => _tasa = x),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Esp.lg + 2),
            decoration: BoxDecoration(
              color: p.negro,
              borderRadius: BorderRadius.circular(Curva.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuota mensual',
                  style: TextStyle(fontSize: 12.5, color: p.sobreNegro2),
                ),
                const SizedBox(height: 2),
                _CifraAnimada(
                  valor: r.cuota,
                  formato: Fmt.pesos,
                  estilo: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: p.acento,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.sm),
          FilaDato(etiqueta: 'Total financiado', valor: Fmt.pesos(r.total)),
          FilaDato(
            etiqueta: 'Intereses',
            valor: Fmt.pesos(r.interes),
            valorColor: p.observar,
          ),
          // Lo que termina pagando el comprador por el auto, con anticipo
          // incluido. Es el número que pregunta.
          if (_anticipo > 0)
            FilaDato(
              etiqueta: 'Total con anticipo',
              valor: Fmt.pesos(r.total + _anticipo),
              destacado: true,
            ),
        ],
      ),
    );
  }
}

class _BotonCuota extends StatelessWidget {
  const _BotonCuota({
    required this.n,
    required this.activo,
    required this.onTap,
  });

  final int n;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return AnimatedContainer(
      duration: Duracion.media,
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: activo ? p.acento : p.superficieHundida,
        shape: const StadiumBorder(),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: activo ? p.acentoTinta : p.tinta2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
