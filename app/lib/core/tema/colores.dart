import 'package:flutter/material.dart';

/// Paleta del sistema de diseno.
///
/// Dos reglas que explican casi todas las decisiones de abajo:
///
/// 1. **El acento nunca es verde, amarillo ni rojo.** Esos tres colores estan
///    reservados para los semaforos (rotacion del vehiculo y riesgo crediticio
///    del cliente). Si el boton primario fuera verde, un usuario apurado leeria
///    "todo bien" donde solo dice "guardar". Por eso el acento es azul.
///
/// 2. **Los colores de estado se definen dos veces, no se reutilizan.** Un verde
///    que funciona sobre fondo claro se apaga sobre fondo oscuro. Cada tema
///    tiene su propia version calibrada para mantener el contraste.
class Paleta {
  const Paleta({
    required this.fondo,
    required this.superficie,
    required this.superficieElevada,
    required this.superficieHundida,
    required this.superficieHover,
    required this.borde,
    required this.bordeFuerte,
    required this.tinta,
    required this.tinta2,
    required this.tinta3,
    required this.acento,
    required this.acentoTinta,
    required this.acentoLavado,
    required this.bien,
    required this.bienLavado,
    required this.observar,
    required this.observarLavado,
    required this.atencion,
    required this.atencionLavado,
    required this.critico,
    required this.criticoLavado,
    required this.neutro,
    required this.neutroLavado,
  });

  /// Lienzo de la app, detras de todo.
  final Color fondo;

  /// Tarjetas y paneles.
  final Color superficie;

  /// Menus, dialogos y todo lo que flota por encima de una tarjeta.
  final Color superficieElevada;

  /// Campos de formulario y celdas de tabla: se hunden respecto de la tarjeta.
  final Color superficieHundida;

  final Color superficieHover;

  final Color borde;
  final Color bordeFuerte;

  /// Texto principal.
  final Color tinta;

  /// Texto secundario: etiquetas, descripciones.
  final Color tinta2;

  /// Texto terciario: encabezados de tabla, ayudas, texto deshabilitado.
  final Color tinta3;

  final Color acento;
  final Color acentoTinta;
  final Color acentoLavado;

  /// Semaforo: dentro de plazo / situacion crediticia normal.
  final Color bien;
  final Color bienLavado;

  /// Semaforo: empieza a demorarse.
  final Color observar;
  final Color observarLavado;

  /// Semaforo: demorado / cumplimiento deficiente.
  final Color atencion;
  final Color atencionLavado;

  /// Semaforo: muy demorado / riesgo alto. Tambien errores destructivos.
  final Color critico;
  final Color criticoLavado;

  /// Estado terminal sin carga emocional: vendido, cerrado, archivado.
  final Color neutro;
  final Color neutroLavado;

  /// Tema por defecto. Oscuro porque la app se usa muchas horas seguidas
  /// mirando tablas densas, y porque es donde el acento y los semaforos
  /// tienen mas presencia.
  static const oscura = Paleta(
    fondo: Color(0xFF0A0C10),
    superficie: Color(0xFF13171E),
    superficieElevada: Color(0xFF1A1F28),
    superficieHundida: Color(0xFF0E1116),
    superficieHover: Color(0xFF1E2430),
    borde: Color(0xFF222834),
    bordeFuerte: Color(0xFF323A4A),
    tinta: Color(0xFFE9EDF4),
    tinta2: Color(0xFF9BA6B7),
    tinta3: Color(0xFF6C7789),
    acento: Color(0xFF4D8BFF),
    acentoTinta: Color(0xFF06122B),
    acentoLavado: Color(0x1F4D8BFF),
    bien: Color(0xFF35D08A),
    bienLavado: Color(0x1F35D08A),
    observar: Color(0xFFF0B23F),
    observarLavado: Color(0x1FF0B23F),
    atencion: Color(0xFFF5874A),
    atencionLavado: Color(0x1FF5874A),
    critico: Color(0xFFF46A6A),
    criticoLavado: Color(0x1FF46A6A),
    neutro: Color(0xFF7E8BA0),
    neutroLavado: Color(0x1F7E8BA0),
  );

  /// Tema claro. No es el oscuro invertido: los colores de estado se oscurecen
  /// y saturan para no perder contraste sobre blanco.
  static const clara = Paleta(
    fondo: Color(0xFFF3F5F9),
    superficie: Color(0xFFFFFFFF),
    superficieElevada: Color(0xFFFFFFFF),
    superficieHundida: Color(0xFFF0F3F8),
    superficieHover: Color(0xFFE9EEF6),
    borde: Color(0xFFDFE5EE),
    bordeFuerte: Color(0xFFC3CCDB),
    tinta: Color(0xFF10151E),
    tinta2: Color(0xFF4E5969),
    tinta3: Color(0xFF7C8698),
    acento: Color(0xFF1D5FE0),
    acentoTinta: Color(0xFFFFFFFF),
    acentoLavado: Color(0x141D5FE0),
    bien: Color(0xFF0E9F63),
    bienLavado: Color(0x140E9F63),
    observar: Color(0xFFB07908),
    observarLavado: Color(0x14B07908),
    atencion: Color(0xFFC75F22),
    atencionLavado: Color(0x14C75F22),
    critico: Color(0xFFD03B3B),
    criticoLavado: Color(0x14D03B3B),
    neutro: Color(0xFF64748B),
    neutroLavado: Color(0x1464748B),
  );
}

/// Hace la paleta accesible con `Theme.of(context).paleta`.
///
/// Sin esto habria que pasar la paleta a mano por cada constructor, o leer
/// `ColorScheme`, que no tiene lugar para "superficieHundida" ni para los
/// cinco estados del semaforo.
class TemaPaleta extends ThemeExtension<TemaPaleta> {
  const TemaPaleta(this.paleta);
  final Paleta paleta;

  @override
  TemaPaleta copyWith({Paleta? paleta}) => TemaPaleta(paleta ?? this.paleta);

  /// La interpolacion no tiene sentido aca: al cambiar de tema queremos un
  /// corte limpio, no una paleta intermedia a mitad de camino.
  @override
  TemaPaleta lerp(ThemeExtension<TemaPaleta>? otro, double t) =>
      t < 0.5 ? this : (otro as TemaPaleta? ?? this);
}

extension PaletaDelContexto on BuildContext {
  Paleta get paleta => Theme.of(this).extension<TemaPaleta>()!.paleta;
  bool get esOscuro => Theme.of(this).brightness == Brightness.dark;
}
