import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/alta_vehiculo.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

/// Alta y edicion de una unidad.
///
/// Solo pide lo que el usuario sabe: que compro, cuando y a cuanto. Todo lo
/// demas —costo total, margenes, dias en stock, ganancia real ajustada por
/// inflacion— lo deriva la base a medida que se cargan gastos y precios.
class FormularioVehiculo extends ConsumerStatefulWidget {
  const FormularioVehiculo({super.key, this.inicial});

  final AltaVehiculo? inicial;

  @override
  ConsumerState<FormularioVehiculo> createState() => _FormularioVehiculoState();
}

class _FormularioVehiculoState extends ConsumerState<FormularioVehiculo> {
  late AltaVehiculo _v =
      widget.inicial ??
      AltaVehiculo(fechaCompra: _hoy(), fechaIngreso: _hoy(), anio: null);

  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;
  String? _codigoSugerido;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    if (widget.inicial == null) _pedirCodigo();
  }

  Future<void> _pedirCodigo() async {
    try {
      final c = await ref.read(repositorioProvider).siguienteCodigo();
      if (mounted) setState(() => _codigoSugerido = c);
    } catch (_) {
      // Que no se pueda sugerir el codigo no impide cargar la unidad: lo
      // asigna la base al insertar.
    }
  }

  Future<void> _guardar() async {
    final errores = _v.validar();
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      final repo = ref.read(repositorioProvider);
      if (_v.esEdicion) {
        await repo.actualizarVehiculo(_v);
      } else {
        await repo.crearVehiculo(_v);
      }
      // Invalidar hace que el inventario y el panel se recarguen solos: no
      // hay que avisarle a cada pantalla que algo cambio.
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

  /// Traduce los errores que devuelve Postgres a algo que un vendedor entienda.
  static String _mensajeDeError(Object e) {
    final t = e.toString();
    if (t.contains('vehiculos_agencia_id_codigo_key') ||
        t.contains('duplicate key')) {
      return 'Ya existe una unidad con ese código en tu agencia.';
    }
    if (t.contains('fecha_ingreso_coherente')) {
      return 'La fecha de ingreso no puede ser anterior a la de compra.';
    }
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para cargar unidades en esta agencia.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá internet y probá de nuevo.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final cfg = ref.watch(configProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho >= Corte.tablet;

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(
        title: Text(_v.esEdicion ? 'Editar unidad' : 'Nueva unidad'),
        actions: [
          if (_codigoSugerido != null && !_v.esEdicion)
            Padding(
              padding: const EdgeInsets.only(right: Esp.lg),
              child: Center(
                child: Text(
                  _codigoSugerido!,
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 13,
                    color: p.tinta3,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Esp.xl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Bloque(
                      titulo: 'El vehículo',
                      hijos: [
                        _grilla(dosColumnas, [
                          _texto(
                            'Marca',
                            _v.marca,
                            'marca',
                            (s) => setState(() => _v = _v.copiar(marca: s)),
                            capitalizar: true,
                          ),
                          _texto(
                            'Modelo',
                            _v.modelo,
                            'modelo',
                            (s) => setState(() => _v = _v.copiar(modelo: s)),
                            capitalizar: true,
                          ),
                        ]),
                        _grilla(dosColumnas, [
                          _numero(
                            'Año',
                            _v.anio?.toString() ?? '',
                            'anio',
                            (s) => setState(
                              () => _v = _v.copiar(anio: int.tryParse(s)),
                            ),
                          ),
                          _texto(
                            'Versión',
                            _v.version,
                            'version',
                            (s) => setState(() => _v = _v.copiar(version: s)),
                            ayuda: 'Opcional — ej: XEI 1.8 CVT',
                          ),
                        ]),
                        _grilla(dosColumnas, [
                          _numero(
                            'Kilómetros',
                            _v.km?.toString() ?? '',
                            'km',
                            (s) => setState(
                              () => _v = _v.copiar(km: int.tryParse(s)),
                            ),
                            ayuda: 'Opcional',
                          ),
                          _texto(
                            'Patente',
                            _v.patente,
                            'patente',
                            (s) => setState(() => _v = _v.copiar(patente: s)),
                            ayuda: 'Opcional',
                            mayusculas: true,
                          ),
                        ]),
                      ],
                    ),

                    const SizedBox(height: Esp.md),
                    _Bloque(
                      titulo: 'Cuándo entró',
                      hijos: [
                        _grilla(dosColumnas, [
                          _fecha(
                            'Fecha de compra',
                            _v.fechaCompra,
                            'fechaCompra',
                            (f) =>
                                setState(() => _v = _v.copiar(fechaCompra: f)),
                          ),
                          _fecha(
                            'Fecha de ingreso al predio',
                            _v.fechaIngreso,
                            'fechaIngreso',
                            (f) =>
                                setState(() => _v = _v.copiar(fechaIngreso: f)),
                            ayuda: 'Desde acá se cuentan los días en stock',
                          ),
                        ]),
                        _estado(),
                      ],
                    ),

                    const SizedBox(height: Esp.md),
                    _Bloque(
                      titulo: 'Plata',
                      hijos: [
                        _grilla(dosColumnas, [
                          _numero(
                            'Precio de compra',
                            _v.precioCompra?.toStringAsFixed(0) ?? '',
                            'precioCompra',
                            (s) => setState(
                              () => _v = _v.copiar(
                                precioCompra: double.tryParse(s),
                              ),
                            ),
                            prefijo: r'$',
                          ),
                          _numero(
                            'Precio de venta objetivo',
                            _v.precioObjetivo?.toStringAsFixed(0) ?? '',
                            'precioObjetivo',
                            (s) => setState(
                              () => _v = _v.copiar(
                                precioObjetivo: double.tryParse(s),
                              ),
                            ),
                            prefijo: r'$',
                          ),
                        ]),
                        _avisoMargen(cfg),
                      ],
                    ),

                    const SizedBox(height: Esp.md),
                    _Bloque(
                      titulo: 'Observaciones',
                      hijos: [
                        TextFormField(
                          initialValue: _v.observaciones,
                          maxLines: 3,
                          onChanged: (s) =>
                              setState(() => _v = _v.copiar(observaciones: s)),
                          decoration: const InputDecoration(
                            hintText:
                                'Detalles de chapa, service al día, motivo de '
                                'ingreso…',
                          ),
                        ),
                      ],
                    ),

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
                              onPressed: _guardando ? null : _guardar,
                              child: _guardando
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: p.acentoTinta,
                                      ),
                                    )
                                  : Text(
                                      _v.esEdicion
                                          ? 'Guardar cambios'
                                          : 'Dar de alta',
                                    ),
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

  // -------------------------------------------------------------------
  // Piezas del formulario
  // -------------------------------------------------------------------

  Widget _grilla(bool dosColumnas, List<Widget> hijos) {
    if (!dosColumnas) {
      return Column(
        children: [
          for (final h in hijos) ...[h, const SizedBox(height: Esp.lg)],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < hijos.length; i++) ...[
            Expanded(child: hijos[i]),
            if (i < hijos.length - 1) const SizedBox(width: Esp.md),
          ],
        ],
      ),
    );
  }

  Widget _campo(String etiqueta, String clave, Widget hijo, {String? ayuda}) {
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
          )
        else if (ayuda != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              ayuda,
              style: TextStyle(fontSize: 11.5, color: p.tinta3),
            ),
          ),
      ],
    );
  }

  Widget _texto(
    String etiqueta,
    String valor,
    String clave,
    ValueChanged<String> onChanged, {
    String? ayuda,
    bool capitalizar = false,
    bool mayusculas = false,
  }) => _campo(
    etiqueta,
    clave,
    TextFormField(
      initialValue: valor,
      onChanged: onChanged,
      textCapitalization: capitalizar
          ? TextCapitalization.words
          : TextCapitalization.none,
      inputFormatters: mayusculas
          ? [UpperCaseTextFormatter()]
          : const <TextInputFormatter>[],
      decoration: InputDecoration(
        errorText: null,
        enabledBorder: _errores[clave] != null ? _bordeError() : null,
      ),
    ),
    ayuda: ayuda,
  );

  Widget _numero(
    String etiqueta,
    String valor,
    String clave,
    ValueChanged<String> onChanged, {
    String? ayuda,
    String? prefijo,
  }) => _campo(
    etiqueta,
    clave,
    TextFormField(
      initialValue: valor,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      // En el celular el teclado numerico no trae signos: filtrar aca evita
      // que se cuele una coma o un punto que despues rompe el parseo.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontFamily: TemaApp.mono),
      decoration: InputDecoration(
        prefixText: prefijo,
        prefixStyle: TextStyle(
          fontFamily: TemaApp.mono,
          color: context.paleta.tinta3,
        ),
        enabledBorder: _errores[clave] != null ? _bordeError() : null,
      ),
    ),
    ayuda: ayuda,
  );

  Widget _fecha(
    String etiqueta,
    DateTime? valor,
    String clave,
    ValueChanged<DateTime> onChanged, {
    String? ayuda,
  }) {
    final p = context.paleta;
    return _campo(
      etiqueta,
      clave,
      InkWell(
        onTap: () async {
          final hoy = DateTime.now();
          final elegida = await showDatePicker(
            context: context,
            initialDate: valor ?? hoy,
            firstDate: DateTime(2000),
            lastDate: hoy,
            locale: const Locale('es', 'AR'),
          );
          if (elegida != null) onChanged(elegida);
        },
        borderRadius: BorderRadius.circular(Curva.md),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: Esp.md),
          decoration: BoxDecoration(
            color: p.superficieHundida,
            borderRadius: BorderRadius.circular(Curva.md),
            border: Border.all(
              color: _errores[clave] != null ? p.critico : p.borde,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 17, color: p.tinta3),
              const SizedBox(width: Esp.md),
              Text(
                valor == null ? 'Elegir fecha' : Fmt.fecha(valor),
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 14,
                  color: valor == null ? p.tinta3 : p.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
      ayuda: ayuda,
    );
  }

  Widget _estado() {
    final p = context.paleta;
    // Vendido y dado de baja no se eligen a mano: los pone el sistema al
    // cargar la venta o al dar de baja la unidad.
    const opciones = [
      EstadoVehiculo.enStock,
      EstadoVehiculo.enPreparacion,
      EstadoVehiculo.reservado,
    ];
    return _campo(
      'Estado',
      'estado',
      Wrap(
        spacing: Esp.sm,
        runSpacing: Esp.sm,
        children: [
          for (final e in opciones)
            Material(
              color: _v.estado == e ? p.acentoLavado : p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
              child: InkWell(
                onTap: () => setState(() => _v = _v.copiar(estado: e)),
                borderRadius: BorderRadius.circular(Curva.md),
                // Sin Center ni alignment: cualquiera de los dos estira el
                // Container hasta las constraints maximas y los tres botones
                // ocupan todo el ancho en vez de quedar uno al lado del otro.
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Esp.lg,
                    vertical: Esp.md - 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Curva.md),
                    border: Border.all(
                      color: _v.estado == e ? p.acento : p.borde,
                    ),
                  ),
                  child: Text(
                    e.etiqueta,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _v.estado == e
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: _v.estado == e ? p.acento : p.tinta2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Muestra el margen que dejaria la operacion antes de gastos.
  ///
  /// Es el momento en que sirve saberlo: todavia se puede negociar el precio
  /// de compra. Una vez cargada la unidad, el margen solo puede empeorar a
  /// medida que se le imputan gastos.
  Widget _avisoMargen(ConfigAgencia cfg) {
    final margen = _v.margenInicial;
    if (margen == null) return const SizedBox.shrink();

    final p = context.paleta;
    final bajoMinimo = margen < cfg.margenMinimo;
    final bajoObjetivo = margen < cfg.margenObjetivo;
    final color = bajoMinimo
        ? p.critico
        : bajoObjetivo
        ? p.observar
        : p.bien;

    final ganancia = (_v.precioObjetivo ?? 0) - (_v.precioCompra ?? 0);

    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bajoMinimo
                ? Icons.warning_amber_rounded
                : bajoObjetivo
                ? Icons.info_outline
                : Icons.check_circle_outline,
            size: 17,
            color: color,
          ),
          const SizedBox(width: Esp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Margen inicial ${Fmt.porcentaje(margen)} · '
                  '${Fmt.pesos(ganancia)}',
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bajoMinimo
                      ? 'Está por debajo del mínimo de '
                            '${Fmt.porcentaje(cfg.margenMinimo)}, y todavía no '
                            'cargaste ningún gasto.'
                      : bajoObjetivo
                      ? 'El objetivo de la agencia es '
                            '${Fmt.porcentaje(cfg.margenObjetivo)}. Los gastos '
                            'que vengan lo van a bajar más.'
                      : 'Arriba del objetivo de '
                            '${Fmt.porcentaje(cfg.margenObjetivo)}. Tenés aire '
                            'para los gastos de preparación.',
                  style: TextStyle(fontSize: 12, color: p.tinta2, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _bordeError() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Curva.md),
    borderSide: BorderSide(color: context.paleta.critico),
  );
}

/// Las patentes argentinas se escriben siempre en mayusculas.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) => TextEditingValue(
    text: nuevo.text.toUpperCase(),
    selection: nuevo.selection,
  );
}

class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.hijos});

  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Tarjeta(
    padding: const EdgeInsets.all(Esp.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EtiquetaSeccion(titulo),
        const SizedBox(height: Esp.lg),
        ...hijos,
      ],
    ),
  );
}
