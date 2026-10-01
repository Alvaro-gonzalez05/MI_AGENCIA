import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/importacion.dart';
import '../../dominio/lector_archivos.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';
import 'formulario_vehiculo.dart';

/// Carga masiva de unidades leyendo los archivos que ya tiene la agencia.
///
/// Tres pasos, y el del medio es el que importa: elegir archivos, REVISAR lo
/// que se entendio, y recien ahi cargar. Nunca se guarda nada sin que alguien
/// lo haya visto: un precio mal leido de una foto entra al sistema como
/// verdad y despues se vende un auto abajo del costo.
class ImportarVehiculos extends ConsumerStatefulWidget {
  const ImportarVehiculos({super.key});

  @override
  ConsumerState<ImportarVehiculos> createState() => _ImportarVehiculosState();
}

class _ImportarVehiculosState extends ConsumerState<ImportarVehiculos> {
  final _archivos = <ArchivoImportado>[];
  final _rechazados = <String>[];

  bool _leyendo = false;
  String? _error;
  (int, int)? _tandas;

  List<FilaImportada>? _filas;

  bool _cargando = false;
  int _cargadas = 0;

  /// Las que se completaron a mano desde el formulario, de a una. Van por
  /// separado del contador del lote, que se reinicia en cada carga.
  int _sueltas = 0;
  ResultadoCarga? _resultado;

  bool get _hayCamara =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // -------------------------------------------------------------------
  // Elegir archivos
  // -------------------------------------------------------------------

  Future<void> _elegirArchivos() async {
    final elegidos = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensionesSoportadas,
    );
    // Lista vacia = el usuario cerro el selector sin elegir nada.
    if (elegidos.isEmpty) return;

    for (final f in elegidos) {
      try {
        _agregar(f.name, await f.readAsBytes());
      } catch (_) {
        _rechazados.add('${f.name}: no se pudo abrir.');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _sacarFoto() async {
    final foto = await ImagePicker().pickImage(
      source: ImageSource.camera,
      // Suficiente para leer una planilla escrita a mano y liviano para
      // mandar por los datos del celular de un vendedor.
      maxWidth: 2200,
      imageQuality: 85,
    );
    if (foto == null) return;
    _agregar(foto.name, await foto.readAsBytes());
    if (mounted) setState(() {});
  }

  void _agregar(String nombre, Uint8List bytes) {
    try {
      _archivos.add(prepararArchivo(nombre: nombre, bytes: bytes));
    } on FormatoNoSoportado catch (e) {
      _rechazados.add('$nombre: ${e.mensaje}');
    }
  }

  // -------------------------------------------------------------------
  // Leer con el modelo
  // -------------------------------------------------------------------

  Future<void> _leer() async {
    setState(() {
      _leyendo = true;
      _error = null;
      _tandas = null;
    });
    try {
      final filas = await ref
          .read(repositorioProvider)
          .leerVehiculosDeArchivos(
            _archivos,
            alAvanzar: (hechas, totales) {
              if (mounted) setState(() => _tandas = (hechas, totales));
            },
          );
      if (!mounted) return;

      final inventario = ref.read(inventarioProvider).value ?? const [];
      setState(() {
        _filas = marcarDuplicados(filas, inventario);
        _leyendo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _leyendo = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // -------------------------------------------------------------------
  // Cargar
  // -------------------------------------------------------------------

  Future<void> _cargar() async {
    final aCargar = (_filas ?? [])
        .where((f) => f.incluir && f.completa)
        .toList();
    if (aCargar.isEmpty) return;

    setState(() {
      _cargando = true;
      _cargadas = 0;
    });

    final repo = ref.read(repositorioProvider);
    final fallidas = <(String, String)>[];
    for (final f in aCargar) {
      try {
        await repo.crearVehiculo(f.alta);
        if (mounted) setState(() => _cargadas++);
      } catch (e) {
        fallidas.add((f.titulo, e.toString().replaceFirst('Exception: ', '')));
      }
    }

    ref.invalidate(inventarioProvider);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _resultado = ResultadoCarga(
        cargadas: aCargar.length - fallidas.length,
        fallidas: fallidas,
      );
    });
  }

  /// Abre el formulario comun con la fila precargada. Sirve para completar lo
  /// que falto: el formulario ya sabe validar y guardar, no hay por que
  /// escribir otro editor.
  Future<void> _completar(FilaImportada fila) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FormularioVehiculo(inicial: fila.alta),
      ),
    );
    if (guardado != true || !mounted) return;
    setState(() {
      _filas = [..._filas!]..remove(fila);
      _sueltas++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(
        title: const Text('Importar unidades'),
        actions: [
          if (_filas != null && _resultado == null && !_cargando)
            TextButton(
              onPressed: () => setState(() => _filas = null),
              child: const Text('Elegir otros archivos'),
            ),
          const SizedBox(width: Esp.sm),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _resultado != null
                ? _Resumen(
                    resultado: _resultado!,
                    extra: _sueltas,
                    onCerrar: () => Navigator.of(context).pop(true),
                  )
                : _filas != null
                ? _Revision(
                    filas: _filas!,
                    cargando: _cargando,
                    cargadas: _cargadas,
                    angosto: angosto,
                    onCambiar: (i, f) =>
                        setState(() => _filas = [..._filas!]..[i] = f),
                    onCompletar: _completar,
                    onCargar: _cargar,
                    onOtroArchivo: () => setState(() => _filas = null),
                  )
                : _Seleccion(
                    archivos: _archivos,
                    rechazados: _rechazados,
                    leyendo: _leyendo,
                    tandas: _tandas,
                    error: _error,
                    hayCamara: _hayCamara,
                    onElegir: _elegirArchivos,
                    onFoto: _sacarFoto,
                    onQuitar: (a) => setState(() => _archivos.remove(a)),
                    onLeer: _leer,
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PASO 1 — elegir
// ---------------------------------------------------------------------------

class _Seleccion extends StatelessWidget {
  const _Seleccion({
    required this.archivos,
    required this.rechazados,
    required this.leyendo,
    required this.tandas,
    required this.error,
    required this.hayCamara,
    required this.onElegir,
    required this.onFoto,
    required this.onQuitar,
    required this.onLeer,
  });

  final List<ArchivoImportado> archivos;
  final List<String> rechazados;
  final bool leyendo;
  final (int, int)? tandas;
  final String? error;
  final bool hayCamara;
  final VoidCallback onElegir;
  final VoidCallback onFoto;
  final void Function(ArchivoImportado) onQuitar;
  final VoidCallback onLeer;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return ListView(
      padding: const EdgeInsets.all(Esp.xl),
      children: [
        Aparecer(
          child: CabeceraPantalla(
            titulo: 'Cargar varios autos de una vez',
            subtitulo:
                'Subí tus listas o fotos y el sistema lee los vehículos solo.',
          ),
        ),
        const SizedBox(height: Esp.lg),

        Aparecer(indice: 1, child: const _PasosImportacion(actual: 0)),
        const SizedBox(height: Esp.lg),

        if (error != null) ...[
          Aparecer(indice: 2, child: AvisoError(mensaje: error!)),
          const SizedBox(height: Esp.lg),
        ],

        // Panel dividido, como en el diseño: a la izquierda de dónde sacar
        // los archivos, a la derecha los que ya se eligieron.
        LayoutBuilder(
          builder: (context, r) {
            final izquierda = _ZonaArchivos(
              leyendo: leyendo,
              hayCamara: hayCamara,
              onElegir: onElegir,
              onFoto: onFoto,
            );
            final derecha = _Elegidos(
              archivos: archivos,
              rechazados: rechazados,
              leyendo: leyendo,
              tandas: tandas,
              onQuitar: onQuitar,
              onLeer: onLeer,
            );
            if (r.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Aparecer(indice: 3, child: izquierda),
                  const SizedBox(height: Esp.lg),
                  Aparecer(indice: 4, child: derecha),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Aparecer(indice: 3, child: izquierda)),
                const SizedBox(width: Esp.lg),
                Expanded(flex: 2, child: Aparecer(indice: 4, child: derecha)),
              ],
            );
          },
        ),

        const SizedBox(height: Esp.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 20, color: p.bien),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Text(
                'Tus archivos solo se usan para leer los datos. No se guardan '
                'ni se comparten.',
                style: TextStyle(fontSize: 14, color: p.tinta2, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Los tres pasos de la importación, arriba de todo.
class _PasosImportacion extends StatelessWidget {
  const _PasosImportacion({required this.actual});

  final int actual;

  static const _pasos = [
    ('Paso 1', 'Elegir archivo'),
    ('Paso 2', 'Revisar'),
    ('Paso 3', 'Listo'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.lg),
        border: Border.all(color: p.borde, width: 1.5),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _pasos.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: Esp.sm),
                  decoration: BoxDecoration(
                    color: i <= actual ? p.acento : p.borde,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: i <= actual ? p.acento : p.superficie,
                shape: BoxShape.circle,
                border: Border.all(
                  color: i <= actual ? p.acento : p.borde,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontFamily: TemaApp.titulo,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: i <= actual ? p.acentoTinta : p.tinta3,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Esp.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pasos[i].$1,
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                Text(
                  _pasos[i].$2,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: i == actual ? FontWeight.w700 : FontWeight.w400,
                    color: i == actual ? p.tinta : p.tinta2,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// La zona de arrastre con los formatos que entienden.
class _ZonaArchivos extends StatelessWidget {
  const _ZonaArchivos({
    required this.leyendo,
    required this.hayCamara,
    required this.onElegir,
    required this.onFoto,
  });

  final bool leyendo, hayCamara;
  final VoidCallback onElegir, onFoto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        children: [
          BordePunteado(
            radio: Curva.lg,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Esp.xxl),
              child: Column(
                children: [
                  IconoEnCirculo(
                    icono: Icons.cloud_upload_outlined,
                    tamano: 64,
                    color: p.acentoTexto,
                    fondo: p.acentoLavado,
                  ),
                  const SizedBox(height: Esp.md),
                  Text(
                    'Traé tu archivo acá',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Esp.xs),
                  Text(
                    'o si preferís:',
                    style: TextStyle(fontSize: 15, color: p.tinta2),
                  ),
                  const SizedBox(height: Esp.md),
                  Wrap(
                    spacing: Esp.sm,
                    runSpacing: Esp.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: leyendo ? null : onElegir,
                        icon: const Icon(Icons.folder_open_rounded, size: 22),
                        label: const Text('Elegir archivo'),
                      ),
                      if (hayCamara)
                        OutlinedButton.icon(
                          onPressed: leyendo ? null : onFoto,
                          icon: const Icon(
                            Icons.photo_camera_rounded,
                            size: 22,
                          ),
                          label: const Text('Sacar una foto'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Esp.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'FORMATOS QUE ENTIENDE',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const SizedBox(height: Esp.sm),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: const [
              _Formato(
                icono: Icons.table_chart_outlined,
                titulo: 'Excel',
                detalle: '.xlsx, .csv',
              ),
              _Formato(
                icono: Icons.picture_as_pdf_outlined,
                titulo: 'PDF',
                detalle: 'Documento',
              ),
              _Formato(
                icono: Icons.description_outlined,
                titulo: 'Word',
                detalle: '.docx',
              ),
              _Formato(
                icono: Icons.photo_camera_outlined,
                titulo: 'Foto',
                detalle: 'Del cuaderno',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Formato extends StatelessWidget {
  const _Formato({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo, detalle;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.md,
        vertical: Esp.sm + 2,
      ),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 22, color: p.tinta2),
          const SizedBox(width: Esp.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
              Text(detalle, style: TextStyle(fontSize: 14, color: p.tinta3)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Los archivos elegidos y el botón para leerlos.
class _Elegidos extends StatelessWidget {
  const _Elegidos({
    required this.archivos,
    required this.rechazados,
    required this.leyendo,
    required this.tandas,
    required this.onQuitar,
    required this.onLeer,
  });

  final List<ArchivoImportado> archivos;
  final List<String> rechazados;
  final bool leyendo;
  final (int, int)? tandas;
  final void Function(ArchivoImportado) onQuitar;
  final VoidCallback onLeer;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tarjeta(
          padding: const EdgeInsets.all(Esp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Archivos elegidos (${archivos.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (archivos.isNotEmpty)
                    Pastilla(
                      texto: 'Listos',
                      color: p.bien,
                      lavado: p.bienLavado,
                    ),
                ],
              ),
              const SizedBox(height: Esp.md),
              if (archivos.isEmpty)
                Text(
                  'Todavía no elegiste ninguno.',
                  style: TextStyle(fontSize: 15, color: p.tinta2),
                )
              else
                for (final a in archivos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Esp.sm),
                    child: _FilaArchivo(
                      archivo: a,
                      onQuitar: leyendo ? null : () => onQuitar(a),
                    ),
                  ),
              if (rechazados.isNotEmpty) ...[
                const SizedBox(height: Esp.sm),
                for (final r in rechazados)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: p.critico,
                        ),
                        const SizedBox(width: Esp.sm - 2),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(fontSize: 14, color: p.critico),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Esp.md),
        FilledButton.icon(
          onPressed: archivos.isEmpty || leyendo ? null : onLeer,
          icon: leyendo
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(Icons.document_scanner_outlined, size: 22),
          label: Text(
            leyendo
                ? (tandas == null
                      ? 'Leyendo...'
                      : 'Leyendo ${tandas!.$1} de ${tandas!.$2}')
                : 'Leer los archivos',
          ),
        ),
      ],
    );
  }
}

class _FilaArchivo extends StatelessWidget {
  const _FilaArchivo({required this.archivo, required this.onQuitar});

  final ArchivoImportado archivo;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final esFoto = archivo.mime.startsWith('image/');
    final esPdf = archivo.mime == 'application/pdf';

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.md),
      child: Row(
        children: [
          IconoEnCirculo(
            icono: esFoto
                ? Icons.image_rounded
                : esPdf
                ? Icons.picture_as_pdf_rounded
                : Icons.table_chart_rounded,
            tamano: 40,
            color: p.tinta,
            fondo: p.superficieHundida,
          ),
          const SizedBox(width: Esp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  archivo.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                Text(
                  '${_peso(archivo.bytesOriginales)} · '
                  '${archivo.tipo == TipoContenido.texto ? 'texto' : 'imagen o PDF'}',
                  style: TextStyle(fontSize: 13, color: p.tinta3),
                ),
              ],
            ),
          ),
          if (onQuitar != null)
            BotonCircular(
              icono: Icons.close_rounded,
              tooltip: 'Quitar',
              tamano: 36,
              relleno: p.superficieHundida,
              conBorde: false,
              onTap: onQuitar,
            ),
        ],
      ),
    );
  }

  static String _peso(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).round()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Revision extends StatelessWidget {
  const _Revision({
    required this.filas,
    required this.cargando,
    required this.cargadas,
    required this.angosto,
    required this.onCambiar,
    required this.onCompletar,
    required this.onCargar,
    required this.onOtroArchivo,
  });

  final List<FilaImportada> filas;
  final bool cargando;
  final int cargadas;
  final bool angosto;
  final void Function(int indice, FilaImportada fila) onCambiar;
  final Future<void> Function(FilaImportada fila) onCompletar;
  final VoidCallback onCargar;
  final VoidCallback onOtroArchivo;

  @override
  Widget build(BuildContext context) {
    final listas = filas.where((f) => f.incluir && f.completa).length;
    final incompletas = filas.where((f) => !f.completa).length;

    if (filas.isEmpty) {
      return EstadoVacio(
        icono: Icons.search_off_rounded,
        titulo: 'No encontré vehículos',
        descripcion:
            'En esos archivos no había una lista de autos que pudiera leer. '
            'Probá con la planilla o con una foto más nítida.',
        accion: OutlinedButton.icon(
          onPressed: onOtroArchivo,
          icon: const Icon(Icons.folder_open_rounded, size: 22),
          label: const Text('Elegir otro archivo'),
        ),
      );
    }

    final lista = ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < filas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Esp.sm + 2),
            child: Aparecer(
              indice: i,
              child: _TarjetaFila(
                fila: filas[i],
                angosto: angosto,
                habilitada: !cargando,
                onIncluir: (v) => onCambiar(i, filas[i].copiar(incluir: v)),
                onCompletar: () => onCompletar(filas[i]),
              ),
            ),
          ),
      ],
    );

    final panel = _PanelResumen(
      total: filas.length,
      listas: listas,
      incompletas: incompletas,
      cargando: cargando,
      cargadas: cargadas,
      onCargar: onCargar,
      onOtroArchivo: onOtroArchivo,
    );

    return ListView(
      padding: const EdgeInsets.all(Esp.xl),
      children: [
        Aparecer(
          child: CabeceraPantalla(
            titulo: 'Cargar varios autos de una vez',
            subtitulo:
                'Revisá que los datos leídos sean correctos antes de '
                'guardarlos en tu inventario.',
          ),
        ),
        const SizedBox(height: Esp.lg),
        Aparecer(indice: 1, child: const _PasosImportacion(actual: 1)),
        const SizedBox(height: Esp.lg),

        LayoutBuilder(
          builder: (context, r) {
            if (r.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  panel,
                  const SizedBox(height: Esp.lg),
                  lista,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: lista),
                const SizedBox(width: Esp.lg),
                SizedBox(width: 320, child: panel),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// El panel lateral del diseño: cuántos están bien, cuántos hay que mirar y
/// el botón para cargarlos.
class _PanelResumen extends StatelessWidget {
  const _PanelResumen({
    required this.total,
    required this.listas,
    required this.incompletas,
    required this.cargando,
    required this.cargadas,
    required this.onCargar,
    required this.onOtroArchivo,
  });

  final int total, listas, incompletas, cargadas;
  final bool cargando;
  final VoidCallback onCargar, onOtroArchivo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final bien = total - incompletas;
    final porcentaje = total == 0 ? 0.0 : bien / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tarjeta(
          padding: const EdgeInsets.all(Esp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_car_filled_rounded,
                    size: 24,
                    color: p.tinta2,
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      'Encontramos $total '
                      '${total == 1 ? 'auto' : 'autos'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Esp.md),
              _Renglon(
                texto: '$bien ${bien == 1 ? 'está bien' : 'están bien'}',
                color: p.bien,
                lavado: p.bienLavado,
                icono: Icons.check_circle_outline_rounded,
              ),
              if (incompletas > 0) ...[
                const SizedBox(height: Esp.sm),
                _Renglon(
                  texto:
                      '$incompletas '
                      '${incompletas == 1 ? 'necesita que lo mires' : 'necesitan que los mires'}',
                  color: p.observar,
                  lavado: p.observarLavado,
                  icono: Icons.warning_amber_rounded,
                ),
              ],
              const SizedBox(height: Esp.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${(porcentaje * 100).round()}% sin errores',
                      style: TextStyle(fontSize: 14, color: p.tinta2),
                    ),
                  ),
                  Text(
                    '$bien / $total',
                    style: TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 14,
                      color: p.tinta2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Esp.sm - 2),
              BarraProgreso(valor: porcentaje, color: p.bien),
              const SizedBox(height: Esp.md),
              Container(
                padding: const EdgeInsets.all(Esp.md),
                decoration: BoxDecoration(
                  color: p.superficieHundida,
                  borderRadius: BorderRadius.circular(Curva.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: p.tinta3),
                    const SizedBox(width: Esp.sm),
                    Expanded(
                      child: Text(
                        'Podés corregir o completar cualquier dato tocando la '
                        'fila.',
                        style: TextStyle(
                          fontSize: 14,
                          color: p.tinta2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Esp.md),
        FilledButton.icon(
          onPressed: cargando || listas == 0 ? null : onCargar,
          icon: cargando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(Icons.arrow_forward_rounded, size: 22),
          label: Text(
            cargando
                ? 'Cargando $cargadas de $listas'
                : 'Cargar ${listas == 1 ? 'el auto' : 'los $listas autos'}',
          ),
        ),
        const SizedBox(height: Esp.sm),
        OutlinedButton.icon(
          onPressed: cargando ? null : onOtroArchivo,
          icon: const Icon(Icons.folder_open_rounded, size: 22),
          label: const Text('Elegir otro archivo'),
        ),
      ],
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon({
    required this.texto,
    required this.color,
    required this.lavado,
    required this.icono,
  });

  final String texto;
  final Color color, lavado;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.md,
        vertical: Esp.sm + 2,
      ),
      decoration: BoxDecoration(
        color: lavado,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Esp.sm),
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 15, color: p.tinta)),
          ),
          Icon(icono, size: 20, color: color),
        ],
      ),
    );
  }
}

class _TarjetaFila extends StatelessWidget {
  const _TarjetaFila({
    required this.fila,
    required this.angosto,
    required this.habilitada,
    required this.onIncluir,
    required this.onCompletar,
  });

  final FilaImportada fila;
  final bool angosto;
  final bool habilitada;
  final ValueChanged<bool> onIncluir;
  final VoidCallback onCompletar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final a = fila.alta;
    final errores = fila.errores;

    final subtitulo = [
      if (a.anio != null) '${a.anio}',
      if (a.km != null) Fmt.km(a.km),
      if (a.patente.isNotEmpty) a.patente,
      if (fila.origen != null) fila.origen!,
    ].join(' · ');

    // Un 100% leido de una foto no vale lo mismo que un 100% leido de una
    // celda: se muestra distinto para que nadie lo mire por arriba.
    final porcentaje = (fila.confianza * 100).round();
    final (textoConfianza, colorConfianza, lavadoConfianza) = fila.dudosa
        ? ('Dudosa $porcentaje%', p.observar, p.observarLavado)
        : fila.desdeFoto
        ? ('De foto $porcentaje%', p.neutro, p.neutroLavado)
        : ('Segura $porcentaje%', p.bien, p.bienLavado);

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: fila.incluir,
                onChanged: !habilitada || !fila.completa
                    ? null
                    : (v) => onIncluir(v ?? false),
              ),
              const SizedBox(width: Esp.sm - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fila.titulo,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: p.tinta,
                      ),
                    ),
                    if (subtitulo.isNotEmpty)
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.tinta3),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.sm),
              Pastilla(
                texto: textoConfianza,
                color: colorConfianza,
                lavado: lavadoConfianza,
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          Padding(
            padding: const EdgeInsets.only(left: Esp.xl + Esp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Esp.lg,
                  runSpacing: Esp.xs,
                  children: [
                    _Dato(
                      etiqueta: 'Compra',
                      valor: Fmt.pesos(a.precioCompra),
                      falta: a.precioCompra == null,
                    ),
                    _Dato(
                      etiqueta: 'Venta',
                      valor: Fmt.pesos(a.precioObjetivo),
                      falta: a.precioObjetivo == null,
                    ),
                    _Dato(
                      etiqueta: 'Ingreso',
                      valor: Fmt.fecha(a.fechaIngreso),
                      falta: a.fechaIngreso == null,
                    ),
                  ],
                ),
                for (final texto in fila.advertencias)
                  _Aviso(texto: texto, color: p.observar),
                for (final e in errores.values)
                  _Aviso(texto: e, color: p.critico),
                if (!fila.completa) ...[
                  const SizedBox(height: Esp.sm),
                  OutlinedButton.icon(
                    onPressed: habilitada ? onCompletar : null,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Completar y cargar'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    required this.falta,
  });

  final String etiqueta, valor;
  final bool falta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 13, color: p.tinta3)),
        const SizedBox(width: Esp.sm - 2),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: falta ? p.tinta3 : p.tinta,
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Esp.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: color),
        const SizedBox(width: Esp.sm - 2),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(fontSize: 13, color: color, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// PASO 3 — resumen
// ---------------------------------------------------------------------------

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.resultado,
    required this.extra,
    required this.onCerrar,
  });

  final ResultadoCarga resultado;

  /// Las que se cargaron una por una desde el formulario, antes del lote.
  final int extra;

  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final total = resultado.cargadas + extra;

    return ListView(
      padding: const EdgeInsets.all(Esp.xl),
      children: [
        Aparecer(
          child: Tarjeta(
            destacada: true,
            padding: const EdgeInsets.all(Esp.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconoEnCirculo(
                  icono: resultado.todoBien
                      ? Icons.check_rounded
                      : Icons.warning_amber_rounded,
                  tamano: 64,
                  color: p.acentoTinta,
                  fondo: p.acento,
                ),
                const SizedBox(height: Esp.lg),
                Text(
                  '$total unidad${total == 1 ? '' : 'es'} cargada'
                  '${total == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: p.sobreNegro,
                  ),
                ),
                const SizedBox(height: Esp.xs),
                Text(
                  'Ya están en el inventario con sus días en stock contando '
                  'desde la fecha de ingreso.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: p.sobreNegro2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (resultado.fallidas.isNotEmpty) ...[
          const SizedBox(height: Esp.lg),
          Aparecer(
            indice: 1,
            child: Tarjeta(
              padding: const EdgeInsets.all(Esp.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CabeceraBloque(
                    titulo: '${resultado.fallidas.length} no entraron',
                    descripcion: 'Cargalas a mano desde "Nueva unidad"',
                  ),
                  const SizedBox(height: Esp.md),
                  for (final (titulo, motivo) in resultado.fallidas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Esp.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: p.critico,
                          ),
                          const SizedBox(width: Esp.sm),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$titulo: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: p.tinta,
                                    ),
                                  ),
                                  TextSpan(
                                    text: motivo,
                                    style: TextStyle(color: p.tinta2),
                                  ),
                                ],
                              ),
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Esp.xl),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: onCerrar,
            child: const Text('Ver el inventario'),
          ),
        ),
      ],
    );
  }
}
