import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'importacion.dart';

/// Convierte lo que el usuario eligio en algo que el modelo pueda leer.
///
/// La division es economica, no caprichosa: una planilla de cien filas pesa
/// 30 KB como texto y 2 MB como archivo. Mandar el .xlsx entero en base64
/// cuesta diez veces mas tokens y encima Gemini no lee .xlsx nativamente.
/// Las fotos y los PDF, en cambio, SI los lee, y convertirlos seria perder
/// justamente lo que hay que mirar.
class FormatoNoSoportado implements Exception {
  const FormatoNoSoportado(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Texto maximo por archivo. Una planilla de stock de una agencia entra
/// holgada; el tope existe para que un CSV exportado del sistema anterior con
/// diez anios de historia no reviente la llamada.
const _maximoTexto = 120000;

const _imagenes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

/// Lo que se le ofrece al usuario en el selector de archivos.
const extensionesSoportadas = [
  'xlsx',
  'xlsm',
  'csv',
  'txt',
  'pdf',
  'docx',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
];

/// Prepara un archivo. Tira [FormatoNoSoportado] con un mensaje que se le
/// puede mostrar tal cual al usuario.
ArchivoImportado prepararArchivo({
  required String nombre,
  required Uint8List bytes,
}) {
  final extension = nombre.contains('.')
      ? nombre.split('.').last.toLowerCase()
      : '';

  if (bytes.isEmpty) {
    throw const FormatoNoSoportado('El archivo está vacío.');
  }

  if (_imagenes.containsKey(extension)) {
    return ArchivoImportado(
      nombre: nombre,
      mime: _imagenes[extension]!,
      tipo: TipoContenido.binario,
      contenido: base64Encode(bytes),
      bytesOriginales: bytes.length,
    );
  }

  if (extension == 'pdf') {
    return ArchivoImportado(
      nombre: nombre,
      mime: 'application/pdf',
      tipo: TipoContenido.binario,
      contenido: base64Encode(bytes),
      bytesOriginales: bytes.length,
    );
  }

  final String texto;
  switch (extension) {
    case 'xlsx':
    case 'xlsm':
      texto = _planillaATexto(bytes);
    case 'csv':
    case 'txt':
      texto = _texto(bytes);
    case 'docx':
      texto = _wordATexto(bytes);
    case 'xls':
      throw const FormatoNoSoportado(
        'El .xls es el formato viejo de Excel. Abrilo y usá '
        '"Guardar como" → .xlsx.',
      );
    case 'doc':
      throw const FormatoNoSoportado(
        'El .doc es el formato viejo de Word. Abrilo y usá '
        '"Guardar como" → .docx.',
      );
    default:
      throw FormatoNoSoportado(
        extension.isEmpty
            ? 'No sé qué tipo de archivo es.'
            : 'No puedo leer archivos .$extension.',
      );
  }

  if (texto.trim().isEmpty) {
    throw const FormatoNoSoportado('El archivo no tiene texto adentro.');
  }

  return ArchivoImportado(
    nombre: nombre,
    mime: 'text/plain',
    tipo: TipoContenido.texto,
    contenido: texto.length > _maximoTexto
        ? texto.substring(0, _maximoTexto)
        : texto,
    bytesOriginales: bytes.length,
  );
}

String _texto(Uint8List bytes) {
  // allowMalformed: una planilla exportada de un sistema viejo suele venir en
  // Latin-1 y con acentos. Preferimos una "ó" rota antes que no leer nada.
  final t = utf8.decode(bytes, allowMalformed: true);
  // Sin el BOM, que se cuela como un caracter invisible en la primera celda.
  return t.startsWith('\u{FEFF}') ? t.substring(1) : t;
}

/// Planilla a texto separado por " | ", una linea por fila.
///
/// Se conserva el nombre de cada hoja y se saltean las filas vacias: el
/// modelo necesita ver los encabezados para saber que columna es cada cosa.
String _planillaATexto(Uint8List bytes) {
  final Excel libro;
  try {
    libro = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const FormatoNoSoportado('No pude abrir la planilla.');
  }

  final salida = StringBuffer();
  for (final nombreHoja in libro.tables.keys) {
    final hoja = libro.tables[nombreHoja];
    if (hoja == null || hoja.rows.isEmpty) continue;
    salida.writeln('# Hoja: $nombreHoja');
    for (final fila in hoja.rows) {
      final celdas = fila
          .map((c) => c?.value?.toString().trim() ?? '')
          .toList();
      if (celdas.every((c) => c.isEmpty)) continue;
      salida.writeln(celdas.join(' | '));
      if (salida.length > _maximoTexto) return salida.toString();
    }
  }
  return salida.toString();
}

/// Word a texto. Un .docx es un zip con el documento en XML adentro.
String _wordATexto(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatoNoSoportado('No pude abrir el documento de Word.');
  }

  final documento = zip.files.where((f) => f.name == 'word/document.xml');
  final datos = documento.isEmpty ? null : documento.first.content;
  if (datos is! List<int>) {
    throw const FormatoNoSoportado('El .docx no tiene documento adentro.');
  }

  final xml = utf8.decode(datos, allowMalformed: true);

  // Cada </w:p> es un parrafo y cada </w:tr> una fila de tabla: si no se
  // convierten en saltos de linea, el documento entero queda como un renglon
  // y se pierde justamente la estructura de la lista de autos.
  return xml
      .replaceAll(RegExp(r'</w:(p|tr)>'), '\n')
      .replaceAll(RegExp(r'</w:tc>'), ' | ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}
