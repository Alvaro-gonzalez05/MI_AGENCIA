import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/motor_calculo.dart';
import '../../ui/componentes.dart';

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
    final v = vehiculo;

    final izquierda = [
      _Cabecera(vehiculo: v),
      const SizedBox(height: Esp.md),
      _Costos(vehiculo: v),
      const SizedBox(height: Esp.md),
      _GananciaReal(vehiculo: v, cfg: cfg),
    ];

    final derecha = [
      _SimuladorPrecio(vehiculo: v, cfg: cfg),
      const SizedBox(height: Esp.md),
      _SimuladorFinanciacion(vehiculo: v, cfg: cfg),
    ];

    return ListView(
      padding: const EdgeInsets.all(Esp.xl),
      children: [
        TextButton.icon(
          onPressed: () => context.go('/inventario'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Inventario'),
        ),
        const SizedBox(height: Esp.sm),
        if (dosColumnas)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Column(children: izquierda)),
              const SizedBox(width: Esp.md),
              Expanded(flex: 2, child: Column(children: derecha)),
            ],
          )
        else
          Column(children: [
            ...izquierda,
            const SizedBox(height: Esp.md),
            ...derecha,
          ]),
        const SizedBox(height: Esp.xl),
      ],
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.vehiculo});
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.titulo,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: Esp.xs),
                    Text(
                      '${v.codigo} · ${v.subtitulo}'
                      '${v.km != null ? ' · ${Fmt.km(v.km)}' : ''}',
                      style: TextStyle(fontSize: 13, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              Pastilla(
                texto: v.alerta.etiqueta,
                color: v.alerta.color(p),
                lavado: v.alerta.lavado(p),
              ),
            ],
          ),
          if (v.observaciones != null && v.observaciones!.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Text(
                v.observaciones!,
                style: TextStyle(fontSize: 13, color: p.tinta2, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: _Destacado(
                  etiqueta: 'En stock',
                  valor: Fmt.dias(v.diasEnStock),
                  color: v.alerta.color(p),
                ),
              ),
              Expanded(
                child: _Destacado(
                  etiqueta: 'Precio publicado',
                  valor: Fmt.pesos(v.precioActual),
                ),
              ),
              Expanded(
                child: _Destacado(
                  etiqueta: 'Margen actual',
                  valor: Fmt.porcentaje(v.margenActual),
                  color: v.margenActual < 0 ? p.critico : p.bien,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Destacado extends StatelessWidget {
  const _Destacado({required this.etiqueta, required this.valor, this.color});
  final String etiqueta, valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color ?? p.tinta,
            ),
          ),
        ),
      ],
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
          const EtiquetaSeccion('Capital y costos'),
          const SizedBox(height: Esp.sm),
          FilaDato(
              etiqueta: 'Precio de compra',
              valor: Fmt.pesos(v.precioCompra)),
          FilaDato(
            etiqueta: 'Gastos acumulados (${v.cantidadGastos})',
            valor: Fmt.pesos(v.gastosAcum),
          ),
          Divider(color: p.borde, height: Esp.lg),
          FilaDato(
            etiqueta: 'Costo total',
            valor: Fmt.pesos(v.costoTotal),
            destacado: true,
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
                v.diasEnStock > 0 ? v.costoTotal / v.diasEnStock : v.costoTotal),
          ),
        ],
      ),
    );
  }
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

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('Ganancia real ajustada por inflación'),
          const SizedBox(height: Esp.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MontoDual(
                  pesos: v.gananciaRealIpc,
                  tipoCambio: cfg.tipoCambio,
                  color: enRojo ? p.critico : p.bien,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Margen real',
                        style: TextStyle(fontSize: 11.5, color: p.tinta3)),
                    Text(
                      Fmt.porcentaje(
                        v.precioActual > 0
                            ? (v.precioActual - v.costoTotalHoy) / v.precioActual
                            : 0,
                      ),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: enRojo ? p.critico : p.bien,
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
          const EtiquetaSeccion('Simulador de precio'),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Text('Margen deseado',
                  style: TextStyle(fontSize: 13, color: p.tinta2)),
              const Spacer(),
              Text(
                Fmt.porcentaje(_margen, decimales: 0),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: p.acento,
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
          Divider(color: p.borde, height: Esp.lg),
          FilaDato(
            etiqueta: 'Precio a publicar',
            valor: Fmt.pesos(sugerido),
            destacado: true,
            valorColor: p.acento,
          ),
          FilaDato(etiqueta: 'Precio exacto', valor: Fmt.pesos(exacto)),
          FilaDato(
            etiqueta: 'Diferencia vs. actual',
            valor:
                '${diferencia >= 0 ? '+' : ''}${Fmt.pesos(diferencia)}',
            valorColor: diferencia > 0 ? p.bien : p.critico,
          ),
          FilaDato(
            etiqueta: 'Ajuste necesario',
            valor: Fmt.porcentajeConSigno(ajuste),
            valorColor: ajuste.abs() < 0.02 ? p.tinta2 : p.observar,
          ),
          const SizedBox(height: Esp.sm),
          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: p.acentoLavado,
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Text(
              ajuste.abs() < 0.02
                  ? 'El precio actual ya está alineado con ese margen.'
                  : ajuste > 0
                      ? 'Habría que subir el precio ${Fmt.porcentaje(ajuste)} '
                          'para alcanzar ese margen.'
                      : 'Se puede bajar el precio ${Fmt.porcentaje(ajuste.abs())} '
                          'y todavía alcanzar ese margen.',
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
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

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final r = Motor.financiacion(
      monto: widget.vehiculo.precioActual,
      cuotas: _cuotas,
      tasaMensual: _tasa,
    );

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('Simulador de financiación'),
          const SizedBox(height: Esp.md),
          Text(
            'Interés directo sobre el capital, que es como se vende en el '
            'rubro: “$_cuotas cuotas fijas de…”.',
            style: TextStyle(fontSize: 12, color: p.tinta3, height: 1.4),
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Text('Cuotas', style: TextStyle(fontSize: 13, color: p.tinta2)),
              const Spacer(),
              for (final n in [6, 12, 18, 24])
                Padding(
                  padding: const EdgeInsets.only(left: Esp.sm - 2),
                  child: _BotonCuota(
                    n: n,
                    activo: _cuotas == n,
                    onTap: () => setState(() => _cuotas = n),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Row(
            children: [
              Text('Tasa mensual',
                  style: TextStyle(fontSize: 13, color: p.tinta2)),
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
          Divider(color: p.borde, height: Esp.lg),
          FilaDato(
            etiqueta: 'Cuota mensual',
            valor: Fmt.pesos(r.cuota),
            destacado: true,
            valorColor: p.acento,
          ),
          FilaDato(etiqueta: 'Total a pagar', valor: Fmt.pesos(r.total)),
          FilaDato(
            etiqueta: 'Intereses',
            valor: Fmt.pesos(r.interes),
            valorColor: p.observar,
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
    return Material(
      color: activo ? p.acentoLavado : p.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Curva.sm),
        child: Container(
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Curva.sm),
            border: Border.all(color: activo ? p.acento : p.borde),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: activo ? p.acento : p.tinta2,
            ),
          ),
        ),
      ),
    );
  }
}
