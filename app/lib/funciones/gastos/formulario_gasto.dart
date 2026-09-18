import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/gastos.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

/// Carga de un gasto imputado a una unidad.
class FormularioGasto extends ConsumerStatefulWidget {
  const FormularioGasto({super.key, this.vehiculoFijo});

  /// Cuando se abre desde la ficha de un vehiculo, la unidad ya esta decidida
  /// y no tiene sentido volver a preguntarla.
  final VehiculoInventario? vehiculoFijo;

  @override
  ConsumerState<FormularioGasto> createState() => _FormularioGastoState();
}

class _FormularioGastoState extends ConsumerState<FormularioGasto> {
  late AltaGasto _g = AltaGasto(
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

  VehiculoInventario? _vehiculo(List<VehiculoInventario> inv) {
    if (_g.vehiculoId == null) return null;
    return inv.where((v) => v.id == _g.vehiculoId).firstOrNull;
  }

  Future<void> _guardar(List<VehiculoInventario> inv) async {
    final v = _vehiculo(inv);
    final errores = _g.validar(fechaIngreso: v?.fechaIngreso);
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearGasto(_g);
      // El gasto cambia el costo total, y con el los margenes y las alertas de
      // toda la app: hay que recargar el inventario, no solo esta lista.
      ref.invalidate(gastosProvider);
      ref.invalidate(inventarioProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorGeneral = _mensajeDeError(e);
      });
    }
  }

  static String _mensajeDeError(Object e) {
    final t = e.toString();
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para cargar gastos en esta agencia.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá internet y probá de nuevo.';
    }
    if (t.contains('violates foreign key')) {
      return 'La unidad elegida ya no existe. Actualizá la lista.';
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
      appBar: AppBar(title: const Text('Nuevo gasto')),
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
                    if (widget.vehiculoFijo == null) _selectorVehiculo(inv),
                    if (widget.vehiculoFijo == null)
                      const SizedBox(height: Esp.md),
                    _bloqueGasto(),
                    const SizedBox(height: Esp.md),
                    if (vehiculo != null) _impacto(vehiculo),

                    if (_errorGeneral != null) ...[
                      const SizedBox(height: Esp.md),
                      Container(
                        padding: const EdgeInsets.all(Esp.md),
                        decoration: BoxDecoration(
                          color: p.criticoLavado,
                          borderRadius: BorderRadius.circular(Curva.md),
                          border: Border.all(
                            color: p.critico.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 16,
                              color: p.critico,
                            ),
                            const SizedBox(width: Esp.sm),
                            Expanded(
                              child: Text(
                                _errorGeneral!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.critico,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: Esp.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _guardando
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: Esp.md),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 46,
                            child: FilledButton(
                              onPressed: _guardando
                                  ? null
                                  : () => _guardar(inv),
                              child: _guardando
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: p.acentoTinta,
                                      ),
                                    )
                                  : const Text('Cargar gasto'),
                            ),
                          ),
                        ),
                      ],
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

  Widget _selectorVehiculo(List<VehiculoInventario> inv) {
    final p = context.paleta;
    final enStock = inv.where((v) => !v.vendido).toList()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    final error = _errores['vehiculo'];

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('A qué unidad'),
          const SizedBox(height: Esp.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Esp.md),
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
              border: Border.all(color: error != null ? p.critico : p.borde),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _g.vehiculoId,
                isExpanded: true,
                hint: Text(
                  'Elegí la unidad',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                dropdownColor: p.superficieElevada,
                borderRadius: BorderRadius.circular(Curva.md),
                padding: const EdgeInsets.symmetric(vertical: Esp.sm),
                items: [
                  for (final v in enStock)
                    DropdownMenuItem(
                      value: v.id,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 46,
                            child: Text(
                              v.codigo,
                              style: TextStyle(
                                fontFamily: TemaApp.mono,
                                fontSize: 12,
                                color: p.tinta3,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              v.titulo,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: p.tinta),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _g = _g.copiar(vehiculoId: id);
                  _errores.remove('vehiculo');
                }),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Esp.xs, left: 2),
              child: Text(
                error,
                style: TextStyle(fontSize: 11.5, color: p.critico),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: Esp.xs, left: 2),
              child: Text(
                'Las unidades vendidas no aparecen: sus costos ya están cerrados.',
                style: TextStyle(fontSize: 11.5, color: p.tinta3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bloqueGasto() {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetaSeccion('El gasto'),
          const SizedBox(height: Esp.lg),

          Text(
            'Categoría',
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
              for (final c in CategoriaGasto.values)
                _ChipCategoria(
                  categoria: c,
                  activa: _g.categoria == c,
                  onTap: () => setState(() => _g = _g.copiar(categoria: c)),
                ),
            ],
          ),

          const SizedBox(height: Esp.lg),
          _campo(
            'Importe',
            'importe',
            TextFormField(
              onChanged: (s) => setState(() {
                _g = _g.copiar(importe: double.tryParse(s));
                _errores.remove('importe');
              }),
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
          _campo(
            'Fecha',
            'fecha',
            InkWell(
              onTap: () async {
                final elegida = await showDatePicker(
                  context: context,
                  initialDate: _g.fecha ?? _hoy(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  locale: const Locale('es', 'AR'),
                );
                if (elegida != null) {
                  setState(() {
                    _g = _g.copiar(fecha: elegida);
                    _errores.remove('fecha');
                  });
                }
              },
              borderRadius: BorderRadius.circular(Curva.md),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: Esp.md),
                decoration: BoxDecoration(
                  color: p.superficieHundida,
                  borderRadius: BorderRadius.circular(Curva.md),
                  border: Border.all(
                    color: _errores['fecha'] != null ? p.critico : p.borde,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 17, color: p.tinta3),
                    const SizedBox(width: Esp.md),
                    Text(
                      Fmt.fecha(_g.fecha),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 14,
                        color: p.tinta,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          _campo(
            'Detalle',
            'descripcion',
            TextFormField(
              onChanged: (s) => setState(() => _g = _g.copiar(descripcion: s)),
              decoration: const InputDecoration(
                hintText: 'Service completo 60.000 km',
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          _campo(
            'Proveedor',
            'proveedor',
            TextFormField(
              onChanged: (s) => setState(() => _g = _g.copiar(proveedor: s)),
              decoration: const InputDecoration(
                hintText: 'Opcional — taller, gomería, gestoría…',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(String etiqueta, String clave, Widget hijo) {
    final p = context.paleta;
    final error = _errores[clave];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: p.tinta2,
          ),
        ),
        const SizedBox(height: Esp.sm),
        hijo,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              error,
              style: TextStyle(fontSize: 11.5, color: p.critico),
            ),
          ),
      ],
    );
  }

  /// Lo que este gasto le hace al margen de la unidad.
  ///
  /// Es la razon de ser de esta pantalla: cargar un gasto no es contabilidad,
  /// es una decision. Ver que un service de $400.000 deja el auto en rojo
  /// mientras se escribe el importe cambia lo que se hace despues.
  Widget _impacto(VehiculoInventario v) {
    final p = context.paleta;
    final cfg = ref.watch(configProvider);
    final importe = _g.importe;

    if (importe == null || importe <= 0) {
      return Tarjeta(
        padding: const EdgeInsets.all(Esp.xl),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, size: 17, color: p.tinta3),
            const SizedBox(width: Esp.md),
            Expanded(
              child: Text(
                'Escribí el importe y te muestro cómo queda el margen de '
                '${v.titulo}.',
                style: TextStyle(fontSize: 13, color: p.tinta3, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final i = ImpactoGasto.calcular(
      costoTotal: v.costoTotal,
      precioActual: v.precioActual,
      importe: importe,
    );

    final quedaEnRojo = i.margenDespues < 0;
    final bajoMinimo = i.margenDespues < cfg.margenMinimo;
    final color = quedaEnRojo
        ? p.critico
        : bajoMinimo
        ? p.observar
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EtiquetaSeccion('Impacto en ${v.codigo} · ${v.titulo}'),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: _Antes(
                  etiqueta: 'Margen antes',
                  valor: Fmt.porcentaje(i.margenAntes),
                  color: p.tinta2,
                ),
              ),
              Icon(Icons.arrow_forward, size: 16, color: p.tinta3),
              Expanded(
                child: _Antes(
                  etiqueta: 'Margen después',
                  valor: Fmt.porcentaje(i.margenDespues),
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
            etiqueta: 'Costo total',
            valor:
                '${Fmt.pesos(i.costoAntes)}  →  ${Fmt.pesos(i.costoDespues)}',
          ),
          FilaDato(
            etiqueta: 'Cae el margen',
            valor: Fmt.porcentaje(i.caidaDeMargen),
            valorColor: color,
          ),
          const SizedBox(height: Esp.sm),
          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Text(
              quedaEnRojo
                  ? 'Con este gasto la unidad pasa a perder plata al precio '
                        'publicado. Habría que revisar el precio antes de '
                        'seguir invirtiendo en ella.'
                  : bajoMinimo
                  ? 'Queda por debajo del margen mínimo de '
                        '${Fmt.porcentaje(cfg.margenMinimo)}. Para sostenerlo '
                        'habría que publicarla a '
                        '${Fmt.pesos(i.costoDespues / (1 - cfg.margenMinimo))}.'
                  : 'La unidad sigue arriba del margen mínimo.',
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Antes extends StatelessWidget {
  const _Antes({
    required this.etiqueta,
    required this.valor,
    required this.color,
    this.destacado = false,
  });

  final String etiqueta, valor;
  final Color color;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: destacado ? 22 : 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  const _ChipCategoria({
    required this.categoria,
    required this.activa,
    required this.onTap,
  });

  final CategoriaGasto categoria;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChipSeleccion(
    etiqueta: categoria.etiqueta,
    icono: categoria.icono,
    activo: activa,
    onTap: onTap,
  );
}
