import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/alta_vehiculo.dart';
import '../../dominio/modelos.dart';
import '../../dominio/papeles.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Cargar un auto, en los cuatro pasos del diseño: el auto, el precio, los
/// papeles y las fotos.
///
/// Se guarda al terminar el paso 2, no al final: a partir de ahí la unidad ya
/// existe y los papeles y las fotos se le cuelgan. Es lo que hace la agencia
/// en la vida real —el auto entra, se anota, y los papeles y las fotos llegan
/// después—, y evita perder media carga si suena el teléfono en el paso 3.
class FormularioVehiculo extends ConsumerStatefulWidget {
  const FormularioVehiculo({super.key, this.inicial});

  final AltaVehiculo? inicial;

  @override
  ConsumerState<FormularioVehiculo> createState() => _FormularioVehiculoState();
}

class _FormularioVehiculoState extends ConsumerState<FormularioVehiculo> {
  static const _pasos = ['El auto', 'Precio', 'Papeles', 'Fotos'];

  late AltaVehiculo _v =
      widget.inicial ??
      AltaVehiculo(fechaCompra: _hoy(), fechaIngreso: _hoy(), anio: null);

  /// El id de la unidad una vez guardada (paso 2). Al editar ya viene.
  String? _idGuardado;

  int _paso = 0;
  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;
  String? _codigoSugerido;

  PapelesVehiculo? _papeles;
  List<FotoVehiculo> _fotos = const [];
  bool _subiendo = false;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _idGuardado = widget.inicial?.id;
    if (widget.inicial == null) {
      _pedirCodigo();
    } else {
      _cargarPapelesYFotos();
    }
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

  Future<void> _cargarPapelesYFotos() async {
    final id = _idGuardado;
    if (id == null) return;
    try {
      final repo = ref.read(repositorioProvider);
      final papeles = await repo.papeles(id);
      final fotos = await repo.fotos(id);
      if (mounted) {
        setState(() {
          _papeles = papeles;
          _fotos = fotos;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorGeneral = _mensajeDeError(e));
    }
  }

  /// Qué campos mira cada paso: no se puede frenar a alguien en el paso 1 por
  /// un precio que todavía no cargó.
  static const _camposPorPaso = {
    0: ['marca', 'modelo', 'anio', 'km', 'patente'],
    1: ['precioCompra', 'precioObjetivo', 'fechaCompra', 'fechaIngreso'],
  };

  Map<String, String> _erroresDelPaso(int paso) {
    final todos = _v.validar();
    final campos = _camposPorPaso[paso];
    if (campos == null) return const {};
    return {
      for (final e in todos.entries)
        if (campos.contains(e.key)) e.key: e.value,
    };
  }

  Future<void> _siguiente() async {
    final errores = _erroresDelPaso(_paso);
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    // Al terminar el precio, la unidad se guarda: los papeles y las fotos
    // necesitan un vehículo al que colgarse.
    if (_paso == 1 && _idGuardado == null) {
      setState(() => _guardando = true);
      try {
        final repo = ref.read(repositorioProvider);
        final id = await repo.crearVehiculo(_v);
        ref.invalidate(inventarioProvider);
        if (!mounted) return;
        setState(() {
          _idGuardado = id;
          _papeles = PapelesVehiculo(vehiculoId: id);
          _guardando = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _errorGeneral = _mensajeDeError(e);
        });
        return;
      }
    } else if (_paso == 1 && _idGuardado != null) {
      // Edición: se actualiza lo que se haya tocado.
      setState(() => _guardando = true);
      try {
        await ref.read(repositorioProvider).actualizarVehiculo(_v);
        ref.invalidate(inventarioProvider);
        if (!mounted) return;
        setState(() => _guardando = false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _guardando = false;
          _errorGeneral = _mensajeDeError(e);
        });
        return;
      }
    }

    if (_paso == 2) await _guardarPapeles();

    setState(() => _paso = (_paso + 1).clamp(0, _pasos.length - 1));
  }

  Future<void> _guardarPapeles() async {
    final p = _papeles;
    if (p == null) return;
    try {
      await ref.read(repositorioProvider).guardarPapeles(p);
    } catch (e) {
      if (mounted) setState(() => _errorGeneral = _mensajeDeError(e));
    }
  }

  Future<void> _terminar() async {
    if (_paso == 2) await _guardarPapeles();
    ref.invalidate(inventarioProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Elegir fotos. En el escritorio abre el explorador; en el teléfono, la
  /// galería o la cámara, que es de donde salen las fotos de verdad.
  Future<void> _elegirFotos({bool camara = false}) async {
    final id = _idGuardado;
    if (id == null) return;

    setState(() => _subiendo = true);
    try {
      final repo = ref.read(repositorioProvider);
      final nuevas = <FotoVehiculo>[];

      if (camara) {
        final foto = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2000,
          imageQuality: 82,
        );
        if (foto != null) {
          nuevas.add(
            await repo.subirFoto(
              vehiculoId: id,
              nombreArchivo: foto.name,
              bytes: await foto.readAsBytes(),
            ),
          );
        }
      } else {
        final elegidas = await FilePicker.pickFiles(type: FileType.image);
        for (final archivo in elegidas) {
          nuevas.add(
            await repo.subirFoto(
              vehiculoId: id,
              nombreArchivo: archivo.name,
              bytes: await archivo.readAsBytes(),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _fotos = [..._fotos, ...nuevas];
        _subiendo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _errorGeneral = _mensajeDeError(e);
      });
    }
  }

  Future<void> _borrarFoto(FotoVehiculo f) async {
    try {
      await ref.read(repositorioProvider).eliminarFoto(f);
      if (mounted) {
        setState(() => _fotos = _fotos.where((x) => x.id != f.id).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _errorGeneral = _mensajeDeError(e));
    }
  }

  Future<void> _hacerPortada(FotoVehiculo f) async {
    try {
      await ref.read(repositorioProvider).marcarPortada(f);
      if (!mounted) return;
      setState(
        () => _fotos = [
          for (final x in _fotos)
            FotoVehiculo(
              id: x.id,
              vehiculoId: x.vehiculoId,
              ruta: x.ruta,
              url: x.url,
              orden: x.orden,
              esPortada: x.id == f.id,
            ),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _errorGeneral = _mensajeDeError(e));
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

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(
        title: Text(_v.esEdicion ? 'Editar unidad' : 'Cargar auto'),
        actions: [
          if (_codigoSugerido != null && !_v.esEdicion)
            Padding(
              padding: const EdgeInsets.only(right: Esp.lg),
              child: Center(
                child: Text(
                  _codigoSugerido!,
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 14,
                    color: p.tinta3,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Pasos(actual: _paso, pasos: _pasos),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Esp.xl,
                  Esp.lg,
                  Esp.xl,
                  Esp.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_paso > 0) ...[
                            _ResumenUnidad(
                              vehiculo: _v,
                              estado: switch (_paso) {
                                1 => 'Paso 1 listo',
                                2 => 'Precio guardado',
                                _ => 'Papeles completados',
                              },
                            ),
                            const SizedBox(height: Esp.lg),
                          ],

                          if (_errorGeneral != null) ...[
                            AvisoError(mensaje: _errorGeneral!),
                            const SizedBox(height: Esp.lg),
                          ],

                          switch (_paso) {
                            0 => _PasoAuto(
                              v: _v,
                              errores: _errores,
                              onCambio: (x) => setState(() => _v = x),
                            ),
                            1 => _PasoPrecio(
                              v: _v,
                              cfg: cfg,
                              errores: _errores,
                              onCambio: (x) => setState(() => _v = x),
                            ),
                            2 => _PasoPapeles(
                              papeles:
                                  _papeles ??
                                  PapelesVehiculo(
                                    vehiculoId: _idGuardado ?? '',
                                  ),
                              onCambio: (x) => setState(() => _papeles = x),
                            ),
                            _ => _PasoFotos(
                              fotos: _fotos,
                              subiendo: _subiendo,
                              onElegir: _elegirFotos,
                              onBorrar: _borrarFoto,
                              onPortada: _hacerPortada,
                            ),
                          },
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _BarraPasos(
              paso: _paso,
              total: _pasos.length,
              guardando: _guardando,
              onAtras: _paso == 0
                  ? () => Navigator.of(context).pop(false)
                  : () => setState(() => _paso--),
              onSiguiente: _paso == _pasos.length - 1 ? _terminar : _siguiente,
            ),
          ],
        ),
      ),
    );
  }
}

/// La barra de pasos de arriba: dónde estoy y cuánto falta.
class _Pasos extends StatelessWidget {
  const _Pasos({required this.actual, required this.pasos});

  final int actual;
  final List<String> pasos;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      color: p.superficieHundida,
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            children: [
              for (var i = 0; i < pasos.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: Esp.xs),
                      color: i <= actual ? p.bien : p.borde,
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Duracion.media,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: i < actual
                            ? p.bien
                            : i == actual
                            ? p.acento
                            : p.superficie,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i <= actual ? Colors.transparent : p.borde,
                          width: 1.5,
                        ),
                      ),
                      child: i < actual
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.white,
                            )
                          : Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontFamily: TemaApp.titulo,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: i == actual ? p.acentoTinta : p.tinta3,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pasos[i],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: i == actual
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i == actual ? p.tinta : p.tinta3,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La tira de abajo: atrás y siguiente, siempre a la vista.
class _BarraPasos extends StatelessWidget {
  const _BarraPasos({
    required this.paso,
    required this.total,
    required this.guardando,
    required this.onAtras,
    required this.onSiguiente,
  });

  final int paso, total;
  final bool guardando;
  final VoidCallback onAtras;
  final VoidCallback onSiguiente;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final ultimo = paso == total - 1;
    return Container(
      padding: const EdgeInsets.all(Esp.lg),
      decoration: BoxDecoration(
        color: p.superficie,
        border: Border(top: BorderSide(color: p.borde, width: 1.5)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: guardando ? null : onAtras,
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                label: Text(paso == 0 ? 'Cancelar' : 'Atrás'),
              ),
              const Spacer(),
              FilledButton.icon(
                style: ultimo
                    ? FilledButton.styleFrom(
                        backgroundColor: p.bien,
                        foregroundColor: Colors.white,
                      )
                    : null,
                onPressed: guardando ? null : onSiguiente,
                icon: guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        ultimo
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 22,
                      ),
                label: Text(ultimo ? 'Guardar auto' : 'Siguiente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La cinta con la unidad que se está cargando, como en el diseño.
class _ResumenUnidad extends StatelessWidget {
  const _ResumenUnidad({required this.vehiculo, required this.estado});

  final AltaVehiculo vehiculo;
  final String estado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Row(
        children: [
          IconoEnCirculo(
            icono: Icons.directions_car_filled_rounded,
            tamano: 40,
            color: p.acentoTexto,
            fondo: p.acentoLavado,
          ),
          const SizedBox(width: Esp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    v.marca,
                    v.modelo,
                    if (v.version.isNotEmpty) v.version,
                  ].where((s) => s.isNotEmpty).join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  [
                    if (v.anio != null) '${v.anio}',
                    if (v.patente.isNotEmpty) v.patente.toUpperCase(),
                    if (v.km != null) Fmt.km(v.km),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.tinta2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Esp.sm),
          Pastilla(texto: estado, color: p.bien, lavado: p.bienLavado),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 1 — el auto
// ---------------------------------------------------------------------------

class _PasoAuto extends StatelessWidget {
  const _PasoAuto({
    required this.v,
    required this.errores,
    required this.onCambio,
  });

  final AltaVehiculo v;
  final Map<String, String> errores;
  final ValueChanged<AltaVehiculo> onCambio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BloqueFormulario(
          titulo: 'El vehículo',
          descripcion: 'Lo que identifica la unidad',
          hijos: [
            FilaCampos(
              children: [
                CampoTexto(
                  etiqueta: 'Marca',
                  obligatorio: true,
                  valor: v.marca,
                  error: errores['marca'],
                  onCambio: (x) => onCambio(v.copiar(marca: x)),
                ),
                CampoTexto(
                  etiqueta: 'Modelo',
                  obligatorio: true,
                  valor: v.modelo,
                  error: errores['modelo'],
                  onCambio: (x) => onCambio(v.copiar(modelo: x)),
                ),
              ],
            ),
            FilaCampos(
              children: [
                CampoTexto(
                  etiqueta: 'Versión',
                  ayuda: 'Opcional — ej: XEI 1.8 CVT',
                  valor: v.version,
                  onCambio: (x) => onCambio(v.copiar(version: x)),
                ),
                CampoNumero(
                  etiqueta: 'Año',
                  obligatorio: true,
                  valor: v.anio?.toString() ?? '',
                  error: errores['anio'],
                  onCambio: (x) => onCambio(v.copiar(anio: int.tryParse(x))),
                ),
              ],
            ),
            FilaCampos(
              children: [
                CampoTexto(
                  etiqueta: 'Patente',
                  ayuda: 'AB123CD o ABC123',
                  valor: v.patente,
                  error: errores['patente'],
                  mayusculas: true,
                  onCambio: (x) => onCambio(v.copiar(patente: x)),
                ),
                CampoNumero(
                  etiqueta: 'Kilómetros',
                  sufijo: 'km',
                  valor: v.km?.toString() ?? '',
                  error: errores['km'],
                  onCambio: (x) => onCambio(v.copiar(km: int.tryParse(x))),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Esp.lg),

        BloqueFormulario(
          titulo: 'Ficha técnica',
          descripcion: 'Lo que pregunta el comprador antes de verlo',
          hijos: [
            CampoFormulario(
              etiqueta: 'Combustible',
              hijo: Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [
                  for (final c in Combustible.values)
                    ChipSeleccion(
                      etiqueta: c.etiqueta,
                      activo: v.combustible == c,
                      onTap: () => onCambio(
                        v.combustible == c
                            ? AltaVehiculo(
                                id: v.id,
                                codigo: v.codigo,
                                marca: v.marca,
                                modelo: v.modelo,
                                anio: v.anio,
                                version: v.version,
                                km: v.km,
                                patente: v.patente,
                                fechaCompra: v.fechaCompra,
                                fechaIngreso: v.fechaIngreso,
                                precioCompra: v.precioCompra,
                                precioObjetivo: v.precioObjetivo,
                                estado: v.estado,
                                observaciones: v.observaciones,
                                color: v.color,
                                transmision: v.transmision,
                                puertas: v.puertas,
                                origen: v.origen,
                              )
                            : v.copiar(combustible: c),
                      ),
                    ),
                ],
              ),
            ),
            FilaCampos(
              children: [
                CampoFormulario(
                  etiqueta: 'Caja',
                  hijo: Wrap(
                    spacing: Esp.sm,
                    runSpacing: Esp.sm,
                    children: [
                      for (final t in Transmision.values)
                        ChipSeleccion(
                          etiqueta: t.etiqueta,
                          activo: v.transmision == t,
                          onTap: () => onCambio(v.copiar(transmision: t)),
                        ),
                    ],
                  ),
                ),
                CampoFormulario(
                  etiqueta: 'Puertas',
                  hijo: Wrap(
                    spacing: Esp.sm,
                    runSpacing: Esp.sm,
                    children: [
                      for (final n in [2, 3, 4, 5])
                        ChipSeleccion(
                          etiqueta: '$n',
                          activo: v.puertas == n,
                          onTap: () => onCambio(v.copiar(puertas: n)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            CampoTexto(
              etiqueta: 'Color',
              ayuda: 'Como figura en la cédula',
              valor: v.color,
              onCambio: (x) => onCambio(v.copiar(color: x)),
            ),
          ],
        ),
        const SizedBox(height: Esp.lg),

        BloqueFormulario(
          titulo: '¿Cómo ingresó el vehículo?',
          descripcion: 'Cambia cómo se lee la ganancia de la unidad',
          hijos: [
            for (final o in OrigenVehiculo.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.sm),
                child: _OpcionOrigen(
                  origen: o,
                  activo: v.origen == o,
                  onTap: () => onCambio(v.copiar(origen: o)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _OpcionOrigen extends StatelessWidget {
  const _OpcionOrigen({
    required this.origen,
    required this.activo,
    required this.onTap,
  });

  final OrigenVehiculo origen;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Curva.md),
      side: BorderSide(color: activo ? p.acento : p.borde, width: 1.6),
    );
    return Material(
      color: activo ? p.acentoLavado : p.superficie,
      shape: forma,
      child: InkWell(
        onTap: onTap,
        customBorder: forma,
        child: Padding(
          padding: const EdgeInsets.all(Esp.md),
          child: Row(
            children: [
              Icon(
                activo
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: activo ? p.acentoTexto : p.tinta3,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  origen.etiqueta,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                    color: p.tinta,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 2 — precio
// ---------------------------------------------------------------------------

class _PasoPrecio extends StatelessWidget {
  const _PasoPrecio({
    required this.v,
    required this.cfg,
    required this.errores,
    required this.onCambio,
  });

  final AltaVehiculo v;
  final ConfigAgencia cfg;
  final Map<String, String> errores;
  final ValueChanged<AltaVehiculo> onCambio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final margen = v.margenInicial;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El valor de revista del diseño. La guía todavía no está conectada:
        // el lugar está y lo dice, en vez de mostrar un número inventado.
        Container(
          padding: const EdgeInsets.all(Esp.md + 2),
          decoration: BoxDecoration(
            color: p.acentoLavado,
            borderRadius: BorderRadius.circular(Curva.md),
            border: Border.all(color: p.acento, width: 1.5),
          ),
          child: Row(
            children: [
              IconoEnCirculo(
                icono: Icons.menu_book_outlined,
                tamano: 40,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valor de revista',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'La guía oficial todavía no está conectada: por ahora el '
                      'precio lo ponés vos.',
                      style: TextStyle(fontSize: 14, color: p.tinta2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Esp.lg),

        BloqueFormulario(
          titulo: 'Plata',
          descripcion: 'Lo que costó y lo que se va a pedir',
          hijos: [
            FilaCampos(
              children: [
                CampoMonto(
                  etiqueta: 'Precio de compra',
                  ayuda: 'Solo lo ve el dueño',
                  obligatorio: true,
                  valor: v.precioCompra,
                  error: errores['precioCompra'],
                  onCambio: (x) => onCambio(v.copiar(precioCompra: x)),
                ),
                CampoMonto(
                  etiqueta: 'Precio de venta',
                  ayuda: 'El que se publica en el salón',
                  obligatorio: true,
                  valor: v.precioObjetivo,
                  error: errores['precioObjetivo'],
                  onCambio: (x) => onCambio(v.copiar(precioObjetivo: x)),
                ),
              ],
            ),
            if (margen != null)
              Container(
                padding: const EdgeInsets.all(Esp.md),
                decoration: BoxDecoration(
                  color: margen < cfg.margenMinimo
                      ? p.criticoLavado
                      : p.bienLavado,
                  borderRadius: BorderRadius.circular(Curva.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      margen < cfg.margenMinimo
                          ? Icons.trending_down_rounded
                          : Icons.trending_up_rounded,
                      size: 22,
                      color: margen < cfg.margenMinimo ? p.critico : p.bien,
                    ),
                    const SizedBox(width: Esp.sm),
                    Expanded(
                      child: Text(
                        margen < cfg.margenMinimo
                            ? 'Margen proyectado ${Fmt.porcentaje(margen)}: '
                                  'está por debajo del mínimo de la agencia '
                                  '(${Fmt.porcentaje(cfg.margenMinimo)}), y '
                                  'todavía no contás los gastos.'
                            : 'Margen proyectado ${Fmt.porcentaje(margen)} '
                                  'antes de gastos.',
                        style: TextStyle(
                          fontSize: 15,
                          color: margen < cfg.margenMinimo
                              ? p.critico
                              : p.tinta2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: Esp.lg),

        BloqueFormulario(
          titulo: 'Cuándo entró',
          descripcion: 'Desde esta fecha corren los días en stock',
          hijos: [
            FilaCampos(
              children: [
                CampoFecha(
                  etiqueta: 'Fecha de compra',
                  obligatorio: true,
                  valor: v.fechaCompra,
                  error: errores['fechaCompra'],
                  onCambio: (x) => onCambio(v.copiar(fechaCompra: x)),
                ),
                CampoFecha(
                  etiqueta: 'Ingreso al inventario',
                  obligatorio: true,
                  valor: v.fechaIngreso,
                  error: errores['fechaIngreso'],
                  onCambio: (x) => onCambio(v.copiar(fechaIngreso: x)),
                ),
              ],
            ),
            CampoFormulario(
              etiqueta: 'Estado del vehículo',
              hijo: Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [
                  for (final e in [
                    EstadoVehiculo.enStock,
                    EstadoVehiculo.reservado,
                    EstadoVehiculo.enPreparacion,
                  ])
                    ChipSeleccion(
                      etiqueta: e == EstadoVehiculo.enStock
                          ? 'Disponible'
                          : e.etiqueta,
                      activo: v.estado == e,
                      color: switch (e) {
                        EstadoVehiculo.enStock => p.bien,
                        EstadoVehiculo.reservado => p.observar,
                        _ => null,
                      },
                      onTap: () => onCambio(v.copiar(estado: e)),
                    ),
                ],
              ),
            ),
            CampoTexto(
              etiqueta: 'Observaciones',
              ayuda: 'Detalles, faltantes, lo que haya que saber',
              valor: v.observaciones,
              lineas: 3,
              onCambio: (x) => onCambio(v.copiar(observaciones: x)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 3 — papeles
// ---------------------------------------------------------------------------

class _PasoPapeles extends StatelessWidget {
  const _PasoPapeles({required this.papeles, required this.onCambio});

  final PapelesVehiculo papeles;
  final ValueChanged<PapelesVehiculo> onCambio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final x = papeles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Marcá lo que ya tenés. Lo que falte lo podés completar después.',
          style: TextStyle(fontSize: 15, color: p.tinta2),
        ),
        const SizedBox(height: Esp.lg),

        _FilaPapel(
          icono: Icons.description_outlined,
          titulo: 'Título del auto',
          descripcion: 'Título digital o formato físico original',
          marcado: x.titulo,
          onCambio: (v) => onCambio(x.copiar(titulo: v)),
        ),
        _FilaPapel(
          icono: Icons.badge_outlined,
          titulo: 'Cédula verde',
          descripcion: 'Cédula de identificación vigente',
          marcado: x.cedula,
          onCambio: (v) => onCambio(x.copiar(cedula: v)),
        ),
        _FilaPapel(
          icono: Icons.verified_user_outlined,
          titulo: 'VTV (Verificación Técnica Vehicular)',
          descripcion: x.vtvVence == null
              ? 'Marcá hasta cuándo está vigente'
              : 'Vence el ${Fmt.fecha(x.vtvVence)}'
                    '${x.vtvVencida ? ' — ya vencida' : ''}',
          descripcionEnRojo: x.vtvVencida,
          marcado: x.vtv,
          onCambio: (v) => onCambio(x.copiar(vtv: v)),
          extra: x.vtv
              ? TextButton.icon(
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final f = await showDatePicker(
                      context: context,
                      initialDate: x.vtvVence ?? hoy,
                      firstDate: DateTime(hoy.year - 5),
                      lastDate: DateTime(hoy.year + 10),
                      helpText: '¿Hasta cuándo vale la VTV?',
                    );
                    if (f != null) onCambio(x.copiar(vtvVence: f));
                  },
                  icon: const Icon(Icons.event_rounded, size: 20),
                  label: Text(
                    x.vtvVence == null ? 'Poner vencimiento' : 'Cambiar',
                  ),
                )
              : null,
        ),
        _FilaPapel(
          icono: Icons.fact_check_outlined,
          titulo: 'Informe de dominio',
          descripcion: 'Estado registral DNRPA verificado',
          marcado: x.informeDominio,
          onCambio: (v) => onCambio(x.copiar(informeDominio: v)),
        ),
        _FilaMonto(
          icono: Icons.receipt_long_outlined,
          titulo: 'Deuda de patentes',
          descripcion: 'Rentas provincial o municipal',
          valor: x.patentesDeuda,
          onCambio: (v) => onCambio(
            v == null
                ? x.copiar(limpiarPatentes: true)
                : x.copiar(patentesDeuda: v),
          ),
        ),
        _FilaMonto(
          icono: Icons.gpp_maybe_outlined,
          titulo: 'Multas e infracciones',
          descripcion: 'Lo que quedó impago',
          valor: x.multasMonto,
          cantidad: x.multasCantidad,
          onCantidad: (n) => onCambio(x.copiar(multasCantidad: n)),
          onCambio: (v) => onCambio(
            v == null
                ? x.copiar(limpiarMultas: true)
                : x.copiar(multasMonto: v),
          ),
        ),

        const SizedBox(height: Esp.md),
        Container(
          padding: const EdgeInsets.all(Esp.md),
          decoration: BoxDecoration(
            color: x.completo ? p.bienLavado : p.superficieHundida,
            borderRadius: BorderRadius.circular(Curva.md),
          ),
          child: Row(
            children: [
              Icon(
                x.completo
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 22,
                color: x.completo ? p.bien : p.tinta3,
              ),
              const SizedBox(width: Esp.sm),
              Expanded(
                child: Text(
                  x.completo
                      ? 'Los papeles están completos: la unidad se puede '
                            'transferir sin sorpresas.'
                      : '${x.completos} de ${PapelesVehiculo.total} puntos '
                            'resueltos. Lo que falta queda anotado en la ficha.',
                  style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilaPapel extends StatelessWidget {
  const _FilaPapel({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.marcado,
    required this.onCambio,
    this.extra,
    this.descripcionEnRojo = false,
  });

  final IconData icono;
  final String titulo, descripcion;
  final bool marcado, descripcionEnRojo;
  final ValueChanged<bool> onCambio;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.sm),
      child: Container(
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: BorderRadius.circular(Curva.md),
          border: Border.all(
            color: marcado ? p.bien : p.borde,
            width: marcado ? 1.6 : 1.5,
          ),
        ),
        child: Row(
          children: [
            IconoEnCirculo(
              icono: icono,
              tamano: 42,
              color: marcado ? p.bien : p.tinta3,
              fondo: marcado ? p.bienLavado : p.superficieHundida,
            ),
            const SizedBox(width: Esp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    descripcion,
                    style: TextStyle(
                      fontSize: 14,
                      color: descripcionEnRojo ? p.critico : p.tinta2,
                    ),
                  ),
                  ?extra,
                ],
              ),
            ),
            const SizedBox(width: Esp.sm),
            Checkbox(value: marcado, onChanged: (v) => onCambio(v ?? false)),
          ],
        ),
      ),
    );
  }
}

/// Una fila de papeles que además lleva plata (patentes, multas).
class _FilaMonto extends StatelessWidget {
  const _FilaMonto({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onCambio,
    this.cantidad,
    this.onCantidad,
  });

  final IconData icono;
  final String titulo, descripcion;
  final double? valor;
  final ValueChanged<double?> onCambio;
  final int? cantidad;
  final ValueChanged<int>? onCantidad;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final alDia = valor != null && valor == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.sm),
      child: Container(
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: BorderRadius.circular(Curva.md),
          border: Border.all(
            color: valor == null
                ? p.borde
                : alDia
                ? p.bien
                : p.observar,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconoEnCirculo(
                  icono: icono,
                  tamano: 42,
                  color: valor == null
                      ? p.tinta3
                      : alDia
                      ? p.bien
                      : p.observar,
                  fondo: valor == null
                      ? p.superficieHundida
                      : alDia
                      ? p.bienLavado
                      : p.observarLavado,
                ),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        descripcion,
                        style: TextStyle(fontSize: 14, color: p.tinta2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Esp.sm),
                if (valor == null)
                  OutlinedButton(
                    onPressed: () => onCambio(0),
                    child: const Text('Al día'),
                  )
                else
                  Pastilla(
                    texto: alDia ? 'Al día' : Fmt.pesos(valor),
                    color: alDia ? p.bien : p.observar,
                    lavado: alDia ? p.bienLavado : p.observarLavado,
                  ),
              ],
            ),
            if (valor != null) ...[
              const SizedBox(height: Esp.sm),
              Row(
                children: [
                  Expanded(
                    child: CampoMonto(
                      etiqueta: 'Monto adeudado',
                      valor: valor == 0 ? null : valor,
                      onCambio: (x) => onCambio(x ?? 0),
                    ),
                  ),
                  if (onCantidad != null) ...[
                    const SizedBox(width: Esp.md),
                    Expanded(
                      child: CampoNumero(
                        etiqueta: 'Cuántas',
                        valor: (cantidad ?? 0) == 0 ? '' : '${cantidad!}',
                        onCambio: (x) => onCantidad!(int.tryParse(x) ?? 0),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 4 — fotos
// ---------------------------------------------------------------------------

class _PasoFotos extends StatelessWidget {
  const _PasoFotos({
    required this.fotos,
    required this.subiendo,
    required this.onElegir,
    required this.onBorrar,
    required this.onPortada,
  });

  final List<FotoVehiculo> fotos;
  final bool subiendo;
  final Future<void> Function({bool camara}) onElegir;
  final Future<void> Function(FotoVehiculo) onBorrar;
  final Future<void> Function(FotoVehiculo) onPortada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final enTelefono =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BordePunteado(
          radio: Curva.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Esp.xxl),
            child: Column(
              children: [
                IconoEnCirculo(
                  icono: Icons.photo_camera_outlined,
                  tamano: 56,
                  color: p.tinta2,
                  fondo: p.superficieHundida,
                ),
                const SizedBox(height: Esp.md),
                Text(
                  'Sumá las fotos del auto',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  'Fotos claras del exterior y del interior. La primera es la '
                  'que se ve en el inventario.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: p.tinta2),
                ),
                const SizedBox(height: Esp.lg),
                Wrap(
                  spacing: Esp.sm,
                  runSpacing: Esp.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: subiendo ? null : () => onElegir(),
                      icon: subiendo
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Icon(Icons.image_outlined, size: 22),
                      label: Text(subiendo ? 'Subiendo...' : 'Elegir fotos'),
                    ),
                    if (enTelefono)
                      OutlinedButton.icon(
                        onPressed: subiendo
                            ? null
                            : () => onElegir(camara: true),
                        icon: const Icon(Icons.photo_camera_rounded, size: 22),
                        label: const Text('Sacar una foto'),
                      ),
                  ],
                ),
                const SizedBox(height: Esp.sm),
                Text(
                  'Podés agregarlas después, desde la ficha.',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Esp.lg),

        if (fotos.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'Fotos cargadas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: Esp.sm),
              Pastilla(
                texto: '${fotos.length}',
                color: p.tinta2,
                lavado: p.superficieHundida,
                conPunto: false,
              ),
              const Spacer(),
              Text(
                'Tocá una para hacerla portada',
                style: TextStyle(fontSize: 14, color: p.tinta3),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final f in fotos)
                _Miniatura(
                  foto: f,
                  onBorrar: () => onBorrar(f),
                  onPortada: () => onPortada(f),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({
    required this.foto,
    required this.onBorrar,
    required this.onPortada,
  });

  final FotoVehiculo foto;
  final VoidCallback onBorrar, onPortada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return SizedBox(
      width: 132,
      height: 100,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Curva.md),
            child: GestureDetector(
              onTap: onPortada,
              child: Image.network(
                foto.url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: p.superficieHundida,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: p.tinta3,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          if (foto.esPortada)
            Positioned(
              top: 4,
              left: 4,
              child: Pastilla(
                texto: 'Portada',
                color: p.acentoTinta,
                lavado: p.acento,
                conPunto: false,
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: 'Quitar esta foto',
              icon: const Icon(Icons.close_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: p.negro.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
                minimumSize: const Size(28, 28),
                padding: EdgeInsets.zero,
              ),
              onPressed: onBorrar,
            ),
          ),
        ],
      ),
    );
  }
}
