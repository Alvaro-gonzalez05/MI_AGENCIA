import 'alta_vehiculo.dart';
import 'modelos.dart';

/// Carga masiva de unidades a partir de lo que la agencia ya tiene.
///
/// El caso real: una agencia que arranca con el sistema tiene su stock en un
/// Excel, en un PDF que le pasó el contador, o anotado a mano en una hoja
/// pegada a la pared. Tipear cuarenta unidades a mano es el motivo más común
/// por el que un sistema nuevo se abandona en la primera semana.
///
/// Este archivo tiene la parte que se puede probar sin red: como se normaliza
/// lo que devuelve el modelo y como se detectan los duplicados. La llamada al
/// modelo vive en la Edge Function `importar-vehiculos`.

/// Como viaja el contenido de un archivo hasta el modelo.
enum TipoContenido {
  /// Planillas y documentos que la app ya convirtio a texto plano.
  texto,

  /// Fotos y PDF: van tal cual, en base64, y los lee el modelo.
  binario,
}

/// Un archivo listo para mandar a leer.
class ArchivoImportado {
  const ArchivoImportado({
    required this.nombre,
    required this.mime,
    required this.tipo,
    required this.contenido,
    required this.bytesOriginales,
  });

  final String nombre;
  final String mime;
  final TipoContenido tipo;

  /// Texto plano, o base64 si [tipo] es binario.
  final String contenido;

  /// Peso del archivo original, para mostrarselo al usuario.
  final int bytesOriginales;

  /// Lo que pesa YA CODIFICADO, que es lo que viaja. El base64 agrega un
  /// tercio: repartir tandas por el tamano original mandaria de mas.
  int get peso => contenido.length;

  Map<String, dynamic> aJson() => {
    'nombre': nombre,
    'mime': mime,
    'tipo': tipo.name,
    'contenido': contenido,
  };
}

/// Una fila devuelta por el modelo, ya convertida a lo que entiende la app.
class FilaImportada {
  const FilaImportada({
    required this.alta,
    required this.confianza,
    this.origen,
    this.advertencias = const [],
    this.incluir = true,
  });

  final AltaVehiculo alta;

  /// Entre 0 y 1: que tan seguro estaba el modelo de ESTA fila. Una foto
  /// borrosa o una letra manuscrita dudosa la bajan.
  final double confianza;

  /// De donde salio, para poder ir a mirar el papel original.
  final String? origen;

  /// Lo que hay que avisar aunque la fila sea valida: fechas puestas por
  /// defecto, precios que faltan, patentes repetidas.
  final List<String> advertencias;

  /// Si entra en la carga. El usuario puede destildar filas en la revision.
  final bool incluir;

  Map<String, String> get errores => alta.validar();
  bool get completa => errores.isEmpty;

  /// Por debajo de esto conviene que un humano la mire antes de guardarla.
  bool get dudosa => confianza < 0.75;

  String get titulo {
    final partes = [
      alta.marca.trim(),
      alta.modelo.trim(),
      if (alta.version.trim().isNotEmpty) alta.version.trim(),
    ].where((x) => x.isNotEmpty);
    return partes.isEmpty ? 'Sin identificar' : partes.join(' ');
  }

  FilaImportada copiar({
    AltaVehiculo? alta,
    bool? incluir,
    List<String>? advertencias,
  }) => FilaImportada(
    alta: alta ?? this.alta,
    confianza: confianza,
    origen: origen,
    advertencias: advertencias ?? this.advertencias,
    incluir: incluir ?? this.incluir,
  );

  /// Convierte una fila del modelo en un alta.
  ///
  /// Devuelve null cuando no hay ni marca ni modelo: eso no es un vehiculo,
  /// es una fila de totales o un encabezado que se coló.
  ///
  /// [hoy] se inyecta para poder probar el relleno de fechas.
  static FilaImportada? desdeJson(Map<String, dynamic> j, {DateTime? hoy}) {
    final marca = _texto(j['marca']);
    final modelo = _texto(j['modelo']);
    if (marca.isEmpty && modelo.isEmpty) return null;

    final ahora = hoy ?? DateTime.now();
    final dia = DateTime(ahora.year, ahora.month, ahora.day);
    final advertencias = <String>[];

    var compra = _fecha(j['fecha_compra']);
    var ingreso = _fecha(j['fecha_ingreso']);
    // El alta pide las dos fechas y la base las valida. Cuando el papel trae
    // una sola, la otra es la misma; cuando no trae ninguna, hoy, y se avisa.
    // Poner "hoy" sin avisar seria inventarle antiguedad cero a una unidad
    // que capaz lleva seis meses parada.
    if (compra == null && ingreso == null) {
      compra = dia;
      ingreso = dia;
      advertencias.add('Sin fecha en el archivo: se puso la de hoy.');
    } else {
      compra ??= ingreso;
      ingreso ??= compra;
    }
    if (compra != null && compra.isAfter(dia)) {
      compra = dia;
      advertencias.add('La fecha de compra venía en el futuro.');
    }
    if (ingreso != null && ingreso.isAfter(dia)) ingreso = dia;

    final patente = _patente(j['patente']);
    if (patente.isEmpty && _texto(j['patente']).isNotEmpty) {
      advertencias.add('La patente no tenía formato argentino y se descartó.');
    }

    final compraPrecio = _numero(j['precio_compra']);
    final objetivo = _numero(j['precio_objetivo']);
    if (compraPrecio == null) {
      advertencias.add('Falta el precio de compra.');
    }
    if (objetivo == null) {
      advertencias.add('Falta el precio de venta.');
    }

    return FilaImportada(
      alta: AltaVehiculo(
        marca: marca,
        modelo: modelo,
        version: _texto(j['version']),
        anio: _entero(j['anio']),
        km: _entero(j['km']),
        patente: patente,
        fechaCompra: compra,
        fechaIngreso: ingreso,
        precioCompra: compraPrecio,
        precioObjetivo: objetivo,
        observaciones: _texto(j['observaciones']),
      ),
      confianza: _confianza(j['confianza']),
      origen: _texto(j['origen']).isEmpty ? null : _texto(j['origen']),
      advertencias: advertencias,
    );
  }

  static String _texto(Object? v) => v == null ? '' : v.toString().trim();

  /// Aparte de [_numero] porque ahi el cero significa "no hay dato" y aca
  /// significa "no le creo nada a esta fila".
  static double _confianza(Object? v) {
    if (v is num) return v.toDouble().clamp(0.0, 1.0);
    final n = double.tryParse(_texto(v).replaceAll(',', '.'));
    return n == null ? 0.5 : n.clamp(0.0, 1.0);
  }

  static double? _numero(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    // Por si el modelo devuelve "1.250.000" o "$ 1.250.000,50" igual.
    var t = v.toString().replaceAll(RegExp(r'[^\d,.-]'), '');
    if (t.isEmpty) return null;
    if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
      // 1.250.000 son puntos de miles, no un decimal.
      t = t.replaceAll('.', '');
    }
    final n = double.tryParse(t);
    return n == null || n <= 0 ? null : n;
  }

  static int? _entero(Object? v) => _numero(v)?.round();

  static DateTime? _fecha(Object? v) {
    final t = _texto(v);
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    // Red de seguridad: si el modelo ignoro el formato ISO y mando dd/mm/aaaa.
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(t);
    if (m == null) return null;
    var anio = int.parse(m.group(3)!);
    if (anio < 100) anio += 2000;
    final mes = int.parse(m.group(2)!);
    final dia = int.parse(m.group(1)!);
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    return DateTime(anio, mes, dia);
  }

  static String _patente(Object? v) {
    final t = _texto(v).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final vieja = RegExp(r'^[A-Z]{3}\d{3}$');
    final nueva = RegExp(r'^[A-Z]{2}\d{3}[A-Z]{2}$');
    return vieja.hasMatch(t) || nueva.hasMatch(t) ? t : '';
  }
}

/// Marca las filas que ya existen en el inventario y las repetidas dentro de
/// la misma importacion.
///
/// Sin esto, importar dos veces la misma planilla —que es lo que va a pasar—
/// duplica el stock entero. Se compara por patente, que es lo unico
/// verdaderamente unico de un auto; si no hay patente, por marca + modelo +
/// año, que alcanza para avisar.
List<FilaImportada> marcarDuplicados(
  List<FilaImportada> filas,
  List<VehiculoInventario> inventario,
) {
  String clave(String patente, String marca, String modelo, int? anio) =>
      patente.isNotEmpty
      ? 'P:$patente'
      : 'M:${marca.toLowerCase()}|${modelo.toLowerCase()}|${anio ?? ''}';

  final existentes = <String, String>{};
  for (final v in inventario) {
    if (v.vendido) continue;
    existentes[clave(
          (v.patente ?? '').toUpperCase(),
          v.marca,
          v.modelo,
          v.anio,
        )] =
        v.codigo;
  }

  final vistas = <String>{};
  final resultado = <FilaImportada>[];
  for (final f in filas) {
    final k = clave(f.alta.patente, f.alta.marca, f.alta.modelo, f.alta.anio);
    final yaEstaba = existentes[k];
    final repetida = !vistas.add(k);

    if (yaEstaba == null && !repetida) {
      resultado.add(f);
      continue;
    }
    resultado.add(
      f.copiar(
        // Destildada, no borrada: el usuario decide. Puede ser un segundo
        // auto igual, que en una agencia pasa.
        incluir: false,
        advertencias: [
          ...f.advertencias,
          if (yaEstaba != null) 'Ya está en el inventario ($yaEstaba).',
          if (repetida) 'Aparece más de una vez en el archivo.',
        ],
      ),
    );
  }
  return resultado;
}

/// Resultado de cargar las filas elegidas.
class ResultadoCarga {
  const ResultadoCarga({required this.cargadas, required this.fallidas});

  final int cargadas;

  /// Titulo de la fila y por que no entro.
  final List<(String, String)> fallidas;

  bool get todoBien => fallidas.isEmpty;
}
