/// Una agencia cliente. Solo la ve y la administra la cuenta de desarrollador.
class Agencia {
  const Agencia({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.activa,
    required this.plan,
    this.cuit,
    this.emailContacto,
    this.telefono,
    this.localidad,
    this.provincia,
    this.vigenteHasta,
    this.creadaEl,
    this.miembros = 0,
    this.vehiculos = 0,
  });

  final String id;
  final String nombre;
  final String slug;
  final bool activa;
  final String plan;
  final String? cuit;
  final String? emailContacto;
  final String? telefono;
  final String? localidad;
  final String? provincia;
  final DateTime? vigenteHasta;
  final DateTime? creadaEl;

  /// Uso real de la cuenta, para saber si el cliente la esta usando.
  final int miembros;
  final int vehiculos;

  /// Vencida pero no suspendida: sigue entrando y ya deberia haber pagado.
  bool get vencida =>
      vigenteHasta != null && vigenteHasta!.isBefore(DateTime.now());

  String get ubicacion => [
    localidad,
    provincia,
  ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
}

/// Rol de un usuario dentro de una agencia.
enum RolMembresia {
  owner('Dueño', 'owner', 'Todo, incluida la configuración y los usuarios'),
  admin('Administrador', 'admin', 'Todo menos transferir la cuenta'),
  vendedor('Vendedor', 'vendedor', 'Carga unidades, gastos, precios y ventas'),
  soloLectura('Solo lectura', 'solo_lectura', 'Mira, no toca');

  const RolMembresia(this.etiqueta, this.valorBd, this.descripcion);

  final String etiqueta;
  final String valorBd;
  final String descripcion;

  static RolMembresia desde(String? s) => RolMembresia.values.firstWhere(
    (r) => r.valorBd == s,
    orElse: () => RolMembresia.vendedor,
  );
}

/// Alta de una agencia cliente.
class AltaAgencia {
  const AltaAgencia({
    this.nombre = '',
    this.cuit = '',
    this.emailContacto = '',
    this.telefono = '',
    this.localidad = '',
    this.provincia = '',
    this.plan = 'basico',
    this.vigenteHasta,
    this.emailDueno = '',
  });

  final String nombre;
  final String cuit;
  final String emailContacto;
  final String telefono;
  final String localidad;
  final String provincia;
  final String plan;
  final DateTime? vigenteHasta;

  /// A quién se invita como dueño. Al registrarse con ese email, el trigger
  /// de la base lo vincula solo a esta agencia.
  final String emailDueno;

  /// El identificador corto que se deriva del nombre. Se calcula acá y no lo
  /// escribe el usuario: un slug a mano termina con espacios y mayúsculas.
  String get slug => nombre
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  AltaAgencia copiar({
    String? nombre,
    String? cuit,
    String? emailContacto,
    String? telefono,
    String? localidad,
    String? provincia,
    String? plan,
    DateTime? vigenteHasta,
    String? emailDueno,
  }) => AltaAgencia(
    nombre: nombre ?? this.nombre,
    cuit: cuit ?? this.cuit,
    emailContacto: emailContacto ?? this.emailContacto,
    telefono: telefono ?? this.telefono,
    localidad: localidad ?? this.localidad,
    provincia: provincia ?? this.provincia,
    plan: plan ?? this.plan,
    vigenteHasta: vigenteHasta ?? this.vigenteHasta,
    emailDueno: emailDueno ?? this.emailDueno,
  );

  Map<String, String> validar() {
    final e = <String, String>{};

    if (nombre.trim().length < 3) {
      e['nombre'] = 'Poné el nombre de la agencia.';
    } else if (slug.isEmpty) {
      // Pasa con nombres hechos solo de símbolos: el slug queda vacío y la
      // base lo rechaza por el unique.
      e['nombre'] = 'El nombre tiene que tener letras o números.';
    }

    // El CUIT es opcional, pero si lo cargan tiene que ser un CUIT.
    final soloDigitos = cuit.replaceAll(RegExp(r'[^0-9]'), '');
    if (cuit.trim().isNotEmpty && soloDigitos.length != 11) {
      e['cuit'] = 'Un CUIT tiene 11 dígitos.';
    }

    if (emailContacto.trim().isNotEmpty && !_esEmail(emailContacto)) {
      e['emailContacto'] = 'Ese email no parece válido.';
    }

    if (emailDueno.trim().isEmpty) {
      e['emailDueno'] = 'Poné el email de quien va a administrar la agencia.';
    } else if (!_esEmail(emailDueno)) {
      e['emailDueno'] = 'Ese email no parece válido.';
    }

    return e;
  }

  static bool _esEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  String get cuitLimpio => cuit.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Invitación pendiente a una agencia.
class Invitacion {
  const Invitacion({
    required this.id,
    required this.email,
    required this.rol,
    required this.expiraEl,
    this.agenciaNombre,
  });

  final String id;
  final String email;
  final RolMembresia rol;
  final DateTime expiraEl;
  final String? agenciaNombre;

  bool get vencida => expiraEl.isBefore(DateTime.now());
}
