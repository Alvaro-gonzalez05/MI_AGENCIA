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
    final elegidos = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: extensionesSoportadas,
    );
    if (elegidos == null) return;

    for (final f in elegidos.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        _rechazados.add('${f.name}: no se pudo leer.');
        continue;
      }
      _agregar(f.name, bytes);
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
        fallidas.add((
          f.titulo,
          e.toString().replaceFirst('Exception: ', ''),
        ));
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
          child: Tarjeta(
            destacada: true,
            padding: const EdgeInsets.all(Esp.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconoEnCirculo(
                      icono: Icons.auto_awesome_rounded,
                      tamano: 42,
                      color: p.acentoTinta,
                      fondo: p.acento,
                    ),
                    const SizedBox(width: Esp.md),
                    const Expanded(
                      child: CabeceraBloque(
                        titulo: 'Cargá todo el stock de una vez',
                        descripcion: 'Lo lee un modelo y vos lo revisás',
                        sobreNegro: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Esp.lg),
                Text(
                  'Sirve el Excel que ya usabas, un PDF, un Word, o una foto '
                  'de la hoja donde anotás el stock. Se leen los datos, los '
                  'revisás en pantalla y después se cargan.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: p.sobreNegro2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Esp.lg),

        Aparecer(
          indice: 1,
          child: Wrap(
            spacing: Esp.md,
            runSpacing: Esp.md,
            children: [
              FilledButton.icon(
                onPressed: leyendo ? null : onElegir,
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                label: const Text('Elegir archivos'),
              ),
              if (hayCamara)
                OutlinedButton.icon(
                  onPressed: leyendo ? null : onFoto,
                  icon: const Icon(Icons.photo_camera_rounded, size: 20),
                  label: const Text('Sacar una foto'),
                ),
            ],
          ),
        ),
        const SizedBox(height: Esp.sm),
        Text(
          'Excel (.xlsx), CSV, PDF, Word (.docx) y fotos.',
          style: TextStyle(fontSize: 12, color: p.tinta3),
        ),

        if (archivos.isNotEmpty) ...[
          const SizedBox(height: Esp.lg),
          for (var i = 0; i < archivos.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Esp.sm),
              child: Aparecer(
                indice: i,
                child: _FilaArchivo(
                  archivo: archivos[i],
                  onQuitar: leyendo ? null : () => onQuitar(archivos[i]),
                ),
              ),
            ),
        ],

        if (rechazados.isNotEmpty) ...[
          const SizedBox(height: Esp.sm),
          for (final r in rechazados)
            Padding(
              padding: const EdgeInsets.only(bottom: Esp.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block_rounded, size: 15, color: p.observar),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      r,
                      style: TextStyle(fontSize: 12.5, color: p.observar),
                    ),
                  ),
                ],
              ),
            ),
        ],

        if (error != null) ...[
          const SizedBox(height: Esp.lg),
          Container(
            padding: const EdgeInsets.all(Esp.md + 2),
            decoration: BoxDecoration(
              color: p.criticoLavado,
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: p.critico),
                const SizedBox(width: Esp.sm),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 13, color: p.critico),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: Esp.xl),
        if (leyendo)
          _Leyendo(tandas: tandas)
        else
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: archivos.isEmpty ? null : onLeer,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(
                archivos.isEmpty
                    ? 'Elegí al menos un archivo'
                    : 'Leer ${archivos.length} archivo'
                          '${archivos.length == 1 ? '' : 's'}',
              ),
            ),
          ),
        const SizedBox(height: Esp.md),
        Text(
          'Los archivos se mandan al servidor de la app solo para leerlos. No '
          'quedan guardados en ningún lado.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: p.tinta3, height: 1.4),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                Text(
                  '${_peso(archivo.bytesOriginales)} · '
                  '${archivo.tipo == TipoContenido.texto ? 'texto' : 'imagen o PDF'}',
                  style: TextStyle(fontSize: 11.5, color: p.tinta3),
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

class _Leyendo extends StatelessWidget {
  const _Leyendo({required this.tandas});

  final (int, int)? tandas;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final t = tandas;
    final varias = t != null && t.$2 > 1;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        children: [
          BarraProgreso(
            valor: varias ? t.$1 / t.$2 : 0.35,
            color: p.acento,
          ),
          const SizedBox(height: Esp.lg),
          Text(
            varias
                ? 'Leyendo… tanda ${t.$1 + 1} de ${t.$2}'
                : 'Leyendo los archivos…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.tinta,
            ),
          ),
          const SizedBox(height: Esp.xs),
          Text(
            'Puede tardar hasta un minuto si hay fotos o PDF largos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.tinta3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PASO 2 — revisar
// ---------------------------------------------------------------------------

class _Revision extends StatelessWidget {
  const _Revision({
    required this.filas,
    required this.cargando,
    required this.cargadas,
    required this.angosto,
    required this.onCambiar,
    required this.onCompletar,
    required this.onCargar,
  });

  final List<FilaImportada> filas;
  final bool cargando;
  final int cargadas;
  final bool angosto;
  final void Function(int indice, FilaImportada fila) onCambiar;
  final Future<void> Function(FilaImportada fila) onCompletar;
  final VoidCallback onCargar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final listas = filas.where((f) => f.incluir && f.completa).length;
    final incompletas = filas.where((f) => !f.completa).length;

    if (filas.isEmpty) {
      return EstadoVacio(
        icono: Icons.search_off_rounded,
        titulo: 'No encontré vehículos',
        descripcion:
            'En esos archivos no había una lista de autos que pudiera leer. '
            'Probá con la planilla o con una foto más nítida.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Esp.xl),
            children: [
              Aparecer(
                child: Row(
                  children: [
                    Expanded(
                      child: CabeceraBloque(
                        titulo:
                            'Encontré ${filas.length} '
                            'unidad${filas.length == 1 ? '' : 'es'}',
                        descripcion: incompletas == 0
                            ? 'Revisá los datos antes de cargarlas'
                            : '$incompletas necesita${incompletas == 1 ? '' : 'n'} '
                                  'que completes algo',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Esp.lg),
              for (var i = 0; i < filas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Esp.sm + 2),
                  child: Aparecer(
                    indice: i,
                    child: _TarjetaFila(
                      fila: filas[i],
                      angosto: angosto,
                      habilitada: !cargando,
                      onIncluir: (v) =>
                          onCambiar(i, filas[i].copiar(incluir: v)),
                      onCompletar: () => onCompletar(filas[i]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(Esp.lg),
          decoration: BoxDecoration(
            color: p.superficie,
            border: Border(top: BorderSide(color: p.borde)),
          ),
          child: Row(
            children: [
              Expanded(
                child: cargando
                    ? Text(
                        'Cargando… $cargadas de $listas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.tinta,
                        ),
                      )
                    : Text(
                        '$listas lista${listas == 1 ? '' : 's'} para cargar',
                        style: TextStyle(fontSize: 13, color: p.tinta2),
                      ),
              ),
              const SizedBox(width: Esp.md),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: cargando || listas == 0 ? null : onCargar,
                  icon: cargando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: p.tinta2,
                          ),
                        )
                      : const Icon(Icons.download_done_rounded, size: 20),
                  label: Text(
                    cargando
                        ? 'Cargando'
                        : angosto
                        ? 'Cargar $listas'
                        : 'Cargar $listas unidad${listas == 1 ? '' : 'es'}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
                        style: TextStyle(fontSize: 12, color: p.tinta3),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.sm),
              Pastilla(
                texto: fila.dudosa
                    ? 'Dudosa ${(fila.confianza * 100).round()}%'
                    : 'Segura ${(fila.confianza * 100).round()}%',
                color: fila.dudosa ? p.observar : p.bien,
                lavado: fila.dudosa ? p.observarLavado : p.bienLavado,
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
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        const SizedBox(width: Esp.sm - 2),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13,
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
            style: TextStyle(fontSize: 12, color: color, height: 1.35),
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
                    fontSize: 13.5,
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
                              style: const TextStyle(
                                fontSize: 12.5,
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
