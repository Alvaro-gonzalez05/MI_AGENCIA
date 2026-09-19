import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/ventas.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Cierre de una venta.
///
/// Es la pantalla donde el margen deja de ser una estimacion. Por eso muestra
/// el resultado real ANTES de guardar: nominal, ajustado por inflacion y en
/// dolares. Si la operacion perdio contra la inflacion, se ve en el momento,
/// no tres meses despues en un informe.
class FormularioVenta extends ConsumerStatefulWidget {
  const FormularioVenta({super.key, this.vehiculoFijo, this.venta});

  final VehiculoInventario? vehiculoFijo;

  /// Si viene, se está corrigiendo esa venta en vez de cargar una nueva.
  final Venta? venta;

  @override
  ConsumerState<FormularioVenta> createState() => _FormularioVentaState();
}

class _FormularioVentaState extends ConsumerState<FormularioVenta> {
  late AltaVenta _v = widget.venta != null
      ? AltaVenta.desde(widget.venta!)
      : AltaVenta(vehiculoId: widget.vehiculoFijo?.id, fechaVenta: _hoy());

  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  VehiculoInventario? _vehiculo(List<VehiculoInventario> inv) =>
      _v.vehiculoId == null
      ? null
      : inv.where((x) => x.id == _v.vehiculoId).firstOrNull;

  Future<void> _guardar(List<VehiculoInventario> inv) async {
    final v = _vehiculo(inv);
    final errores = _v.validar(fechaIngreso: v?.fechaIngreso);
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      final repo = ref.read(repositorioProvider);
      if (_v.esEdicion) {
        await repo.actualizarVenta(_v);
      } else {
        await repo.crearVenta(_v);
      }
      // La venta saca la unidad del stock y cambia todos los totales.
      ref.invalidate(ventasProvider);
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
    if (t.contains('ventas_vehiculo_id_key') || t.contains('duplicate key')) {
      return 'Esa unidad ya figura como vendida. Una unidad no se puede '
          'vender dos veces.';
    }
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para registrar ventas en esta agencia.';
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
      appBar: AppBar(
        title: Text(_v.esEdicion ? 'Corregir venta' : 'Registrar venta'),
      ),
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
                    // Al corregir, la unidad queda fija: cambiarle el auto a
                    // una venta es anularla y cargar otra.
                    if (_v.esEdicion) ...[
                      Tarjeta(
                        child: Row(
                          children: [
                            IconoEnCirculo(
                              icono: Icons.directions_car_filled_rounded,
                              color: p.tinta2,
                            ),
                            const SizedBox(width: Esp.md),
                            Expanded(
                              child: Text(
                                vehiculo == null
                                    ? '${widget.venta!.vehiculoCodigo ?? ''} ${widget.venta!.vehiculoTitulo ?? ''}'
                                    : '${vehiculo.codigo} · ${vehiculo.titulo}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: p.tinta,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Esp.md),
                    ] else if (widget.vehiculoFijo == null) ...[
                      SelectorVehiculo(
                        titulo: 'Qué se vendió',
                        ayuda: 'Al guardar, la unidad sale del stock automáticamente.',
                        vehiculos: inv.where((v) => !v.vendido).toList(),
                        seleccionado: _v.vehiculoId,
                        error: _errores['vehiculo'],
                        onCambio: (id) =>
                            setState(() => _v = _v.copiar(vehiculoId: id)),
                      ),
                      const SizedBox(height: Esp.md),
                    ],
                    _bloqueOperacion(),
                    const SizedBox(height: Esp.md),
                    if (vehiculo != null) _resultado(vehiculo),
                    if (_errorGeneral != null) ...[
                      const SizedBox(height: Esp.md),
                      AvisoError(mensaje: _errorGeneral!),
                    ],
                    const SizedBox(height: Esp.xl),
                    BotoneraFormulario(
                      guardando: _guardando,
                      etiquetaGuardar: _v.esEdicion
                          ? 'Guardar corrección'
                          : 'Cerrar la venta',
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

  Widget _bloqueOperacion() {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'La operación'),
          const SizedBox(height: Esp.lg),

          CampoFormulario(
            etiqueta: 'Precio final de venta',
            error: _errores['precioFinal'],
            hijo: TextFormField(
              initialValue: _v.precioFinal?.round().toString(),
              onChanged: (s) => setState(
                () => _v = _v.copiar(precioFinal: double.tryParse(s)),
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
            etiqueta: 'Gastos de cierre',
            ayuda:
                'Comisión, gestoría, transferencia — lo que aparece al firmar',
            error: _errores['gastosFinales'],
            hijo: TextFormField(
              initialValue: _v.gastosFinales == 0
                  ? null
                  : _v.gastosFinales.round().toString(),
              onChanged: (s) => setState(
                () => _v = _v.copiar(gastosFinales: double.tryParse(s) ?? 0),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontFamily: TemaApp.mono),
              decoration: InputDecoration(
                prefixText: r'$',
                prefixStyle: TextStyle(
                  fontFamily: TemaApp.mono,
                  color: p.tinta3,
                ),
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Fecha de la venta',
            error: _errores['fecha'],
            hijo: SelectorFecha(
              valor: _v.fechaVenta,
              hayError: _errores['fecha'] != null,
              onCambio: (f) => setState(() => _v = _v.copiar(fechaVenta: f)),
            ),
          ),

          const SizedBox(height: Esp.lg),
          Text(
            'Forma de pago',
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
              for (final f in FormaPago.values)
                ChipSeleccion(
                  etiqueta: f.etiqueta,
                  activo: _v.formaPago == f,
                  onTap: () => setState(() => _v = _v.copiar(formaPago: f)),
                ),
            ],
          ),

          // Las cuotas solo tienen sentido si hay financiacion de por medio.
          if (_v.pideCuotas) ...[
            const SizedBox(height: Esp.lg),
            CampoFormulario(
              etiqueta: 'Cantidad de cuotas',
              error: _errores['cuotas'],
              hijo: TextFormField(
                initialValue: _v.cuotas?.toString(),
                onChanged: (s) =>
                    setState(() => _v = _v.copiar(cuotas: int.tryParse(s))),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontFamily: TemaApp.mono),
              ),
            ),
          ],

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Observaciones',
            hijo: TextFormField(
              initialValue: _v.observaciones,
              maxLines: 2,
              onChanged: (s) =>
                  setState(() => _v = _v.copiar(observaciones: s)),
              decoration: const InputDecoration(
                hintText: 'Quién compró, condiciones, entrega…',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// El resultado real de la operacion, antes de confirmarla.
  Widget _resultado(VehiculoInventario v) {
    final p = context.paleta;
    final precio = _v.precioFinal;

    if (precio == null || precio <= 0) {
      return Tarjeta(
        padding: const EdgeInsets.all(Esp.xl),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, size: 17, color: p.tinta3),
            const SizedBox(width: Esp.md),
            Expanded(
              child: Text(
                'Escribí el precio de cierre y te muestro qué dejó la '
                'operación de verdad.',
                style: TextStyle(fontSize: 13, color: p.tinta3, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final r = ResultadoVenta(
      costoTotal: v.costoTotal,
      costoTotalHoy: v.costoTotalHoy,
      precioFinal: precio,
      gastosFinales: _v.gastosFinales,
      tipoCambio: ref.watch(configProvider).tipoCambio,
    );

    final color = r.perdioPlata
        ? p.critico
        : r.gananciaReal < 0
        ? p.observar
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Resultado de la operación',
            descripcion:
                '${v.codigo} · ${v.titulo} · ${Fmt.dias(v.diasEnStock)} en stock',
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: ValorAntesDespues(
                  etiqueta: 'Ganancia nominal',
                  valor: Fmt.pesos(r.ganancia),
                  color: r.perdioPlata ? p.critico : p.tinta,
                ),
              ),
              Icon(Icons.arrow_forward, size: 16, color: p.tinta3),
              Expanded(
                child: ValorAntesDespues(
                  etiqueta: 'Ganancia real (IPC)',
                  valor: Fmt.pesos(r.gananciaReal),
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
            etiqueta: 'Costo con gastos de cierre',
            valor: Fmt.pesos(r.costoConCierre),
          ),
          FilaDato(etiqueta: 'Margen nominal', valor: Fmt.porcentaje(r.margen)),
          FilaDato(
            etiqueta: 'Margen real',
            valor: Fmt.porcentaje(r.margenReal),
            valorColor: color,
            destacado: true,
          ),
          FilaDato(
            etiqueta: 'En dólares',
            valor: Fmt.dolares(r.gananciaRealUsd),
          ),
          const SizedBox(height: Esp.sm),
          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Text(
              r.perdioPlata
                  ? 'La operación cierra a pérdida: se vendió por debajo de lo '
                        'que costó ponerla en condiciones.'
                  : r.perdioContraInflacion
                  ? 'En pesos da ganancia, pero descontada la inflación del '
                        'período la operación perdió poder de compra. La '
                        'unidad estuvo ${Fmt.dias(v.diasEnStock)} en stock.'
                  : 'La inflación se llevó ${Fmt.pesos(r.erosion)} de la '
                        'ganancia nominal. Lo que queda de verdad es '
                        '${Fmt.pesos(r.gananciaReal)}.',
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
