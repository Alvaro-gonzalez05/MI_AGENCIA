/// Un precio de la guía: una versión, un año y lo que vale.
///
/// La app no le pregunta a la guía: lee nuestra copia, que llena el
/// cosechador de a poco. Por eso buscar es instantáneo y funciona aunque la
/// guía esté caída o se haya acabado el cupo del día.
class PrecioRevista {
  const PrecioRevista({
    required this.versionId,
    required this.anio,
    required this.precioArs,
    this.marca = '',
    this.modelo = '',
    this.version = '',
    this.versionCompleta = '',
    this.actualizado,
  });

  final int versionId;
  final int anio;
  final double precioArs;

  final String marca;
  final String modelo;
  final String version;

  /// El nombre tal cual lo escribe la guía, que es largo y con mayúsculas.
  final String versionCompleta;

  final DateTime? actualizado;

  /// "Ford Ranger Pick - Up", listo para un título.
  String get titulo => [marca, modelo].where((s) => s.isNotEmpty).join(' ');
}

/// Qué años tiene la guía para lo que se buscó.
class AnioRevista {
  const AnioRevista({required this.anio, required this.versiones});

  final int anio;
  final int versiones;
}
