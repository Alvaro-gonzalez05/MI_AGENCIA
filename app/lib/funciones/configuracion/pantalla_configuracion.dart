import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';
import 'datos_agencia.dart';

/// Parámetros de la agencia.
///
/// No es una pantalla de ajustes cualquiera: estos números alimentan el motor
/// de cálculo, así que mover un umbral repinta el inventario entero. Por eso
/// muestra en vivo cuántas unidades cambian de estado antes de guardar.
class PantallaConfiguracion extends ConsumerStatefulWidget {
  const PantallaConfiguracion({super.key});

  @override
  ConsumerState<PantallaConfiguracion> createState() => _PantallaConfigState();
}

class _PantallaConfigState extends ConsumerState<PantallaConfiguracion> {
  ConfigAgencia? _editada;
  bool _guardando = false;
  String? _error;

  ConfigAgencia get _c => _editada ?? ref.read(configProvider);

  void _cambiar(ConfigAgencia nueva) => setState(() => _editada = nueva);

  bool get _hayCambios {
    final o = ref.read(configProvider);
    final e = _editada;
    if (e == null) return false;
    return e.diasVerde != o.diasVerde ||
        e.diasAmarillo != o.diasAmarillo ||
        e.diasRojo != o.diasRojo ||
        e.margenMinimo != o.margenMinimo ||
        e.margenObjetivo != o.margenObjetivo ||
        e.umbralGastosAltos != o.umbralGastosAltos ||
        e.redondeo != o.redondeo ||
        e.capacidad != o.capacidad ||
        e.tasaFinanciacionMensual != o.tasaFinanciacionMensual;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(repositorioProvider).guardarConfig(_c);
      // Los umbrales cambian las alertas de todo el inventario.
      ref.invalidate(configAsyncProvider);
      ref.invalidate(inventarioProvider);
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _editada = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración guardada — todo se recalculó'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString().contains('permission')
            ? 'Solo el dueño o un administrador pueden cambiar la configuración.'
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = ref.watch(inventarioProvider).value ?? const [];
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          esMovil ? Esp.lg + 4 : Esp.xxl,
          Esp.xl,
          esMovil ? Esp.lg + 4 : Esp.xxl,
          96,
        ),
        children: [
          const DatosDeLaAgencia(),
          const SizedBox(height: Esp.md),
          _bloqueRotacion(inv),
          const SizedBox(height: Esp.md),
          _bloqueMargenes(inv),
          const SizedBox(height: Esp.md),
          _bloqueOperativa(),
          if (_error != null) ...[
            const SizedBox(height: Esp.md),
            AvisoError(mensaje: _error!),
          ],
          const SizedBox(height: Esp.xl),
          if (_hayCambios)
            BotoneraFormulario(
              guardando: _guardando,
              etiquetaGuardar: 'Guardar cambios',
              onCancelar: () => setState(() => _editada = null),
              onGuardar: _guardar,
            )
          else
            Center(
              child: Text(
                'No hay cambios sin guardar',
                style: TextStyle(fontSize: 12.5, color: context.paleta.tinta3),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------

  Widget _bloqueRotacion(List<VehiculoInventario> inv) {
    final p = context.paleta;
    final c = _c;
    final enStock = inv.where((v) => !v.vendido).toList();

    int cuantos(bool Function(int dias) test) =>
        enStock.where((v) => test(v.diasEnStock)).length;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Semáforo de rotación',
            descripcion:
                'A partir de cuántos días una unidad empieza a preocupar',
          ),
          const SizedBox(height: Esp.lg),

          _Deslizador(
            etiqueta: 'Hasta acá está todo bien',
            valor: c.diasVerde.toDouble(),
            min: 7,
            max: 90,
            texto: Fmt.dias(c.diasVerde),
            color: p.bien,
            onCambio: (v) {
              final nuevo = v.round();
              _cambiar(
                ConfigAgencia(
                  diasVerde: nuevo,
                  // Los umbrales tienen que quedar ordenados: la base lo exige
                  // con un check, y si no se empujan acá el guardado falla.
                  diasAmarillo: c.diasAmarillo <= nuevo
                      ? nuevo + 1
                      : c.diasAmarillo,
                  diasRojo: c.diasRojo <= nuevo + 1 ? nuevo + 2 : c.diasRojo,
                  margenMinimo: c.margenMinimo,
                  margenObjetivo: c.margenObjetivo,
                  umbralGastosAltos: c.umbralGastosAltos,
                  redondeo: c.redondeo,
                  capacidad: c.capacidad,
                  tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                  tipoCambio: c.tipoCambio,
                ),
              );
            },
          ),
          const SizedBox(height: Esp.md),
          _Deslizador(
            etiqueta: 'Acá ya hay que mirarla',
            valor: c.diasAmarillo.toDouble(),
            min: (c.diasVerde + 1).toDouble(),
            max: 180,
            texto: Fmt.dias(c.diasAmarillo),
            color: p.atencion,
            onCambio: (v) {
              final nuevo = v.round();
              _cambiar(
                ConfigAgencia(
                  diasVerde: c.diasVerde,
                  diasAmarillo: nuevo,
                  diasRojo: c.diasRojo <= nuevo ? nuevo + 1 : c.diasRojo,
                  margenMinimo: c.margenMinimo,
                  margenObjetivo: c.margenObjetivo,
                  umbralGastosAltos: c.umbralGastosAltos,
                  redondeo: c.redondeo,
                  capacidad: c.capacidad,
                  tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                  tipoCambio: c.tipoCambio,
                ),
              );
            },
          ),
          const SizedBox(height: Esp.md),
          _Deslizador(
            etiqueta: 'Acá es un problema',
            valor: c.diasRojo.toDouble(),
            min: (c.diasAmarillo + 1).toDouble(),
            max: 365,
            texto: Fmt.dias(c.diasRojo),
            color: p.critico,
            onCambio: (v) => _cambiar(
              ConfigAgencia(
                diasVerde: c.diasVerde,
                diasAmarillo: c.diasAmarillo,
                diasRojo: v.round(),
                margenMinimo: c.margenMinimo,
                margenObjetivo: c.margenObjetivo,
                umbralGastosAltos: c.umbralGastosAltos,
                redondeo: c.redondeo,
                capacidad: c.capacidad,
                tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                tipoCambio: c.tipoCambio,
              ),
            ),
          ),

          if (enStock.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.md),
            Text(
              'Con estos umbrales, de tus ${enStock.length} unidades:',
              style: TextStyle(fontSize: 12.5, color: p.tinta3),
            ),
            const SizedBox(height: Esp.sm),
            Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                Pastilla(
                  texto: '${cuantos((d) => d < c.diasVerde)} al día',
                  color: p.bien,
                  lavado: p.bienLavado,
                ),
                Pastilla(
                  texto:
                      '${cuantos((d) => d >= c.diasVerde && d < c.diasAmarillo)} a observar',
                  color: p.observar,
                  lavado: p.observarLavado,
                ),
                Pastilla(
                  texto:
                      '${cuantos((d) => d >= c.diasAmarillo && d < c.diasRojo)} en atención',
                  color: p.atencion,
                  lavado: p.atencionLavado,
                ),
                Pastilla(
                  texto: '${cuantos((d) => d >= c.diasRojo)} críticas',
                  color: p.critico,
                  lavado: p.criticoLavado,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bloqueMargenes(List<VehiculoInventario> inv) {
    final p = context.paleta;
    final c = _c;
    final enStock = inv.where((v) => !v.vendido).toList();
    final bajoMinimo = enStock
        .where((v) => v.margenActual < c.margenMinimo)
        .length;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Márgenes',
            descripcion: 'Se miden sobre el precio de venta, no sobre el costo',
          ),
          const SizedBox(height: Esp.lg),

          _Deslizador(
            etiqueta: 'Mínimo aceptable',
            valor: c.margenMinimo,
            min: 0,
            max: 0.5,
            divisiones: 50,
            texto: Fmt.porcentaje(c.margenMinimo),
            color: p.observar,
            onCambio: (v) => _cambiar(
              ConfigAgencia(
                diasVerde: c.diasVerde,
                diasAmarillo: c.diasAmarillo,
                diasRojo: c.diasRojo,
                margenMinimo: v,
                margenObjetivo: c.margenObjetivo < v ? v : c.margenObjetivo,
                umbralGastosAltos: c.umbralGastosAltos,
                redondeo: c.redondeo,
                capacidad: c.capacidad,
                tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                tipoCambio: c.tipoCambio,
              ),
            ),
          ),
          const SizedBox(height: Esp.md),
          _Deslizador(
            etiqueta: 'Objetivo',
            valor: c.margenObjetivo,
            min: c.margenMinimo,
            max: 0.7,
            divisiones: 70,
            texto: Fmt.porcentaje(c.margenObjetivo),
            color: p.bien,
            onCambio: (v) => _cambiar(
              ConfigAgencia(
                diasVerde: c.diasVerde,
                diasAmarillo: c.diasAmarillo,
                diasRojo: c.diasRojo,
                margenMinimo: c.margenMinimo,
                margenObjetivo: v,
                umbralGastosAltos: c.umbralGastosAltos,
                redondeo: c.redondeo,
                capacidad: c.capacidad,
                tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                tipoCambio: c.tipoCambio,
              ),
            ),
          ),

          if (enStock.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: bajoMinimo > 0 ? p.criticoLavado : p.bienLavado,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Text(
                bajoMinimo == 0
                    ? 'Ninguna unidad queda por debajo del mínimo.'
                    : '$bajoMinimo de ${enStock.length} unidades quedan por '
                          'debajo del mínimo con este umbral.',
                style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bloqueOperativa() {
    final p = context.paleta;
    final c = _c;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'Operativa'),
          const SizedBox(height: Esp.lg),

          _Deslizador(
            etiqueta: 'Tasa de financiación mensual',
            valor: c.tasaFinanciacionMensual,
            min: 0,
            max: 0.25,
            divisiones: 50,
            texto: Fmt.porcentaje(c.tasaFinanciacionMensual),
            color: p.acentoTexto,
            onCambio: (v) => _cambiar(
              ConfigAgencia(
                diasVerde: c.diasVerde,
                diasAmarillo: c.diasAmarillo,
                diasRojo: c.diasRojo,
                margenMinimo: c.margenMinimo,
                margenObjetivo: c.margenObjetivo,
                umbralGastosAltos: c.umbralGastosAltos,
                redondeo: c.redondeo,
                capacidad: c.capacidad,
                tasaFinanciacionMensual: v,
                tipoCambio: c.tipoCambio,
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          Text(
            'Redondeo del precio a publicar',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: p.tinta2,
            ),
          ),
          const SizedBox(height: Esp.sm),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final r in [10000.0, 50000.0, 100000.0, 500000.0])
                ChipSeleccion(
                  etiqueta: Fmt.pesosCompacto(r),
                  activo: c.redondeo == r,
                  onTap: () => _cambiar(
                    ConfigAgencia(
                      diasVerde: c.diasVerde,
                      diasAmarillo: c.diasAmarillo,
                      diasRojo: c.diasRojo,
                      margenMinimo: c.margenMinimo,
                      margenObjetivo: c.margenObjetivo,
                      umbralGastosAltos: c.umbralGastosAltos,
                      redondeo: r,
                      capacidad: c.capacidad,
                      tasaFinanciacionMensual: c.tasaFinanciacionMensual,
                      tipoCambio: c.tipoCambio,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Esp.xs),
          Text(
            'El simulador redondea siempre para arriba, nunca a favor del cliente.',
            style: TextStyle(fontSize: 11.5, color: p.tinta3),
          ),
        ],
      ),
    );
  }
}

/// Deslizador con su etiqueta y el valor en mono a la derecha.
class _Deslizador extends StatelessWidget {
  const _Deslizador({
    required this.etiqueta,
    required this.valor,
    required this.min,
    required this.max,
    required this.texto,
    required this.color,
    required this.onCambio,
    this.divisiones,
  });

  final String etiqueta;
  final double valor, min, max;
  final String texto;
  final Color color;
  final ValueChanged<double> onCambio;
  final int? divisiones;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    // El valor puede quedar fuera de rango mientras se arrastra otro
    // deslizador que empuja este mínimo; sin el clamp, Slider tira assert.
    final v = valor.clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: TextStyle(fontSize: 13, color: p.tinta2),
              ),
            ),
            Text(
              texto,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: p.superficieHundida,
            overlayColor: color.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisiones ?? (max - min).round().clamp(1, 400),
            onChanged: onCambio,
          ),
        ),
      ],
    );
  }
}
