/// Estado de una campaña de email.
enum EstadoCampana {
  borrador('Borrador', 'borrador'),
  programada('Programada', 'programada'),
  enviando('Enviando', 'enviando'),
  enviada('Enviada', 'enviada'),
  cancelada('Cancelada', 'cancelada');

  const EstadoCampana(this.etiqueta, this.valorBd);
  final String etiqueta;
  final String valorBd;

  static EstadoCampana desde(String? s) => EstadoCampana.values.firstWhere(
    (e) => e.valorBd == s,
    orElse: () => EstadoCampana.borrador,
  );

  /// Una campaña enviada no se edita ni se reenvía: quedó en la casilla de
  /// la gente y reescribirla sería reescribir la historia.
  bool get editable => this == borrador || this == programada;
}

/// Una campaña.
class Campana {
  const Campana({
    required this.id,
    required this.nombre,
    required this.asunto,
    required this.estado,
    this.cuerpoHtml = '',
    this.destinatarios = 0,
    this.enviados = 0,
    this.aperturas = 0,
    this.clicks = 0,
    this.enviadaEl,
    this.creadaEl,
  });

  final String id;
  final String nombre;
  final String asunto;
  final EstadoCampana estado;
  final String cuerpoHtml;
  final int destinatarios;
  final int enviados;
  final int aperturas;
  final int clicks;
  final DateTime? enviadaEl;
  final DateTime? creadaEl;

  double? get tasaApertura => enviados == 0 ? null : aperturas / enviados;

  double? get tasaClick => enviados == 0 ? null : clicks / enviados;
}

/// Lo que se carga al armar una campaña.
class AltaCampana {
  const AltaCampana({
    this.nombre = '',
    this.asunto = '',
    this.cuerpo = '',
    this.soloConEmail = true,
  });

  final String nombre;
  final String asunto;

  /// Texto plano que escribe el usuario. Se convierte a HTML al guardar:
  /// pedirle HTML a un vendedor no tiene ningún sentido.
  final String cuerpo;

  final bool soloConEmail;

  AltaCampana copiar({
    String? nombre,
    String? asunto,
    String? cuerpo,
    bool? soloConEmail,
  }) => AltaCampana(
    nombre: nombre ?? this.nombre,
    asunto: asunto ?? this.asunto,
    cuerpo: cuerpo ?? this.cuerpo,
    soloConEmail: soloConEmail ?? this.soloConEmail,
  );

  /// Variables que el usuario puede usar en el asunto y el cuerpo.
  static const variables = {
    '{{nombre}}': 'Nombre del destinatario',
    '{{agencia}}': 'Nombre de la agencia',
  };

  Map<String, String> validar() {
    final e = <String, String>{};

    if (nombre.trim().isEmpty) {
      e['nombre'] = 'Poné un nombre para identificar la campaña.';
    }

    if (asunto.trim().isEmpty) {
      e['asunto'] = 'Poné el asunto del mail.';
    } else if (asunto.trim().length > 120) {
      // Los clientes de mail cortan más o menos ahí; un asunto que se corta
      // a la mitad baja la apertura.
      e['asunto'] = 'Es muy largo: se va a cortar en la bandeja de entrada.';
    }

    if (cuerpo.trim().length < 20) {
      e['cuerpo'] = 'Escribí el mensaje.';
    }

    // Una variable mal escrita se manda literal al cliente: "Hola {{nombe}}".
    final usadas = RegExp(r'\{\{\s*\w+\s*\}\}')
        .allMatches('$asunto $cuerpo')
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s'), ''));
    final desconocidas = usadas.where((v) => !variables.containsKey(v)).toSet();
    if (desconocidas.isNotEmpty) {
      e['cuerpo'] =
          'Estas variables no existen y se van a enviar tal cual: '
          '${desconocidas.join(', ')}';
    }

    return e;
  }

  /// Convierte el texto plano en el HTML del mail.
  ///
  /// Se escapa primero y se arman los párrafos después: si alguien escribe
  /// `<b>` en el cuerpo tiene que verse `<b>`, no ponerse en negrita.
  String get html {
    final escapado = cuerpo
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final parrafos = escapado
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .map(
          (p) =>
              '<p style="margin:0 0 16px;line-height:1.6">'
              '${p.trim().replaceAll('\n', '<br>')}</p>',
        )
        .join('\n    ');

    return '''
<!doctype html>
<html lang="es"><body style="margin:0;padding:24px;background:#f3f3f0;
  font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#111112">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:14px;padding:32px">
    $parrafos
    <hr style="border:none;border-top:1px solid #e8e8e3;margin:24px 0">
    <p style="margin:0;font-size:12px;color:#8b8b90">
      Recibís este mail porque dejaste tus datos en {{agencia}}.
      Si no querés recibir más, respondé este mail con la palabra BAJA.
    </p>
  </div>
</body></html>''';
  }
}
