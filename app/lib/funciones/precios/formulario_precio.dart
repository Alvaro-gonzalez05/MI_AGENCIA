import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/precios.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Cambio del precio publicado de una unidad.
///
/// El precio es la unica variable que la agencia puede mover despues de haber
/// comprado. Por eso la pantalla no pide solo el numero: muestra a que margen
/// queda y cual seria el precio para sostener el minimo.
class FormularioPrecio extends ConsumerStatefulWidget {
  const FormularioPrecio({super.key, this.vehiculoFijo});

  final VehiculoInventario? vehiculoFijo;

  @override
  ConsumerState<FormularioPrecio> createState() => _FormularioPrecioState();
}

class _FormularioPrecioState extends ConsumerState<FormularioPrecio> {
  late AltaPrecio _p = AltaPrecio(
    vehiculoId: widget.vehiculoFijo?.id,
    fecha: _hoy(),
  );

  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  VehiculoInventario? _vehiculo(List<VehiculoInventario> inv) =>
      _p.vehiculoId == null
      ? null
      : inv.where((v) => v.id == _p.vehiculoId).firstOrNull;

  Future<void> _guardar(List<VehiculoInventario> inv) async {
    final v = _vehiculo(inv);
    final errores = _p.validar(
      fechaIngreso: v?.fechaIngreso,
      precioActual: v?.precioActual,
    );
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearCambioPrecio(_p);
      ref.invalidate(preciosProvider);
      ref.invalidate(inventarioProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorGeneral = _mensaje(e);
      });
    }
  }

  static String _mensaje(Object e) {
    final t = e.toString();
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para cambiar precios en esta agencia.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá internet y probá de nuevo.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final inv = ref.watch(inventarioProvider).value ?? const [];
    final vehiculo = _vehiculo(inv);

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(title: const Text('Cambiar precio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Esp.xl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.vehiculoFijo == null) ...[
                      SelectorVehiculo(
                        titulo: 'Qué unidad',
                        ayuda: 'Las vendidas no aparecen: su precio ya está cerrado.',
                        vehiculos: inv.where((v) => !v.vendido).toList(),
                        seleccionado: _p.vehiculoId,
                        error: _errores['vehiculo'],
                        onCambio: (id) =>
                            setState(() => _p = _p.copiar(vehiculoId: id)),
                      ),
                      const SizedBox(height: Esp.md),
                    ],
                    _bloquePrecio(vehiculo),
                    const SizedBox(height: Esp.md),
                    if (vehiculo != null) _impacto(vehiculo),
                    if (_errorGeneral != null) ...[
                      const SizedBox(height: Esp.md),
                      AvisoError(mensaje: _errorGeneral!),
                    ],
                    const SizedBox(height: Esp.xl),
                    BotoneraFormulario(
                      guardando: _guardando,
                      etiquetaGuardar: 'Guardar precio',
                      onCancelar: () => Navigator.of(context).pop(false),
                      onGuardar: () => _guardar(inv),
                    ),
                    const SizedBox(height: Esp.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bloquePrecio(VehiculoInventario? v) {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'El precio nuevo'),
          const SizedBox(height: Esp.lg),

          if (v != null) ...[
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                children: [
                  Text(
                    'Publicado hoy',
                    style: TextStyle(fontSize: 12.5, color: p.tinta3),
                  ),
                  const Spacer(),
                  Text(
                    Fmt.pesos(v.precioActual),
                    style: TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.tinta,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Esp.lg),
          ],

          CampoFormulario(
            etiqueta: 'Precio nuevo',
            error: _errores['precio'],
            hijo: TextFormField(
              onChanged: (s) => setState(
                () => _p = _p.copiar(precioNuevo: double.tryParse(s)),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontFamily: TemaApp.mono, fontSize: 16),
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

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Fecha',
            error: _errores['fecha'],
            hijo: SelectorFecha(
              valor: _p.fecha,
              hayError: _errores['fecha'] != null,
              onCambio: (f) => setState(() => _p = _p.copiar(fecha: f)),
            ),
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Motivo',
            ayuda: 'Para acordarte en tres meses por qué lo tocaste',
            hijo: TextFormField(
              onChanged: (s) => setState(() => _p = _p.copiar(motivo: s)),
              decoration: const InputDecoration(
                hintText:
                    'Bajó el interés, ajuste de mercado, cerrar la venta…',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _impacto(VehiculoInventario v) {
    final p = context.paleta;
    final cfg = ref.watch(configProvider);
    final nuevo = _p.precioNuevo;

    if (nuevo == null || nuevo <= 0) {
      return Tarjeta(
        padding: const EdgeInsets.all(Esp.xl),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, size: 17, color: p.tinta3),
            const SizedBox(width: Esp.md),
            Expanded(
              child: Text(
                'Escribí el precio y te muestro a qué margen queda, con todo '
                'lo que ya lleva invertido.',
                style: TextStyle(fontSize: 13, color: p.tinta3, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final i = ImpactoPrecio.calcular(
      costoTotal: v.costoTotal,
      precioActual: v.precioActual,
      precioNuevo: nuevo,
    );

    final color = i.quedaEnPerdida
        ? p.critico
        : i.margenNuevo < cfg.margenMinimo
        ? p.observar
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(titulo: '${v.codigo} · ${v.titulo}'),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: ValorAntesDespues(
                  etiqueta: 'Margen antes',
                  valor: Fmt.porcentaje(i.margenAnterior),
                  color: p.tinta2,
                ),
              ),
              Icon(Icons.arrow_forward, size: 16, color: p.tinta3),
              Expanded(
                child: ValorAntesDespues(
                  etiqueta: 'Margen después',
                  valor: Fmt.porcentaje(i.margenNuevo),
                  color: color,
                  destacado: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          Divider(color: p.borde, height: 1),
          const SizedBox(height: Esp.md),
          FilaDato(
            etiqueta: 'Variación del precio',
            valor: Fmt.porcentajeConSigno(i.variacion),
            valorColor: i.variacion < 0 ? p.critico : p.bien,
          ),
          FilaDato(etiqueta: 'Costo invertido', valor: Fmt.pesos(i.costoTotal)),
          FilaDato(
            etiqueta: 'Ganancia a este precio',
            valor: Fmt.pesos(i.gananciaNueva),
            valorColor: color,
            destacado: true,
          ),
          const SizedBox(height: Esp.sm),
          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Text(
              i.quedaEnPerdida
                  ? 'A este precio la unidad se vende a pérdida. El punto de '
                        'equilibrio está en ${Fmt.pesos(i.costoTotal)}.'
                  : i.margenNuevo < cfg.margenMinimo
                  ? 'Queda por debajo del mínimo de '
                        '${Fmt.porcentaje(cfg.margenMinimo)}. Para sostenerlo '
                        'habría que publicarla a '
                        '${Fmt.pesos(i.costoTotal / (1 - cfg.margenMinimo))}.'
                  : 'Sigue arriba del margen mínimo. Para el objetivo de '
                        '${Fmt.porcentaje(cfg.margenObjetivo)} sería '
                        '${Fmt.pesos(i.costoTotal / (1 - cfg.margenObjetivo))}.',
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
