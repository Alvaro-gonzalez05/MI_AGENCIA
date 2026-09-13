import 'package:flutter/material.dart';

/// Paleta del sistema de diseno.
///
/// Identidad: blanco y negro con acento amarillo. Tres reglas explican casi
/// todas las decisiones de abajo:
///
/// 1. **El amarillo se usa como RELLENO, no como tinta.** Amarillo sobre blanco
///    no se lee. Por eso hay dos colores de acento: [acento] para fondos
///    (botones, pastillas activas, indicadores) y [acentoTexto] para cuando el
///    acento tiene que leerse como texto o icono sobre una superficie. En
///    oscuro es el mismo amarillo; en claro es negro.
///
/// 2. **Los semaforos no se confunden con el acento.** El amarillo de marca es
///    un limon saturado y siempre va de relleno con texto negro; el semaforo
///    "observar" es ambar, siempre va como pastilla lavada con punto y
///    etiqueta. Nunca aparecen con la misma forma.
///
/// 3. **Hay superficies negras en los dos temas.** La barra lateral, la barra
///    inferior del movil y las tarjetas destacadas son negras tambien en claro:
///    es lo que le da caracter al tema claro y ancla la vista.
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
    required this.acentoTexto,
    required this.negro,
    required this.negroElevado,
    required this.negroBorde,
    required this.sobreNegro,
    required this.sobreNegro2,
    required this.sombra,
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

  /// Campos de formulario y celdas: se hunden respecto de la tarjeta.
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

  /// Amarillo de marca. Solo como relleno.
  final Color acento;

  /// Texto e iconos SOBRE el amarillo.
  final Color acentoTinta;

  /// Amarillo muy suave, para fondos de estados seleccionados.
  final Color acentoLavado;

  /// El acento cuando tiene que leerse como texto o icono sobre la superficie.
  final Color acentoTexto;

  /// Superficies negras: barra lateral, barra inferior, tarjetas destacadas.
  final Color negro;
  final Color negroElevado;
  final Color negroBorde;

  /// Texto sobre [negro].
  final Color sobreNegro;
  final Color sobreNegro2;

  /// Sombra de las tarjetas. En oscuro casi no se ve, asi que la jerarquia
  /// la sigue marcando el borde.
  final Color sombra;

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

  /// Tema por defecto. Negro casi puro con un toque calido, para que el
  /// amarillo no quede estridente.
  static const oscura = Paleta(
    fondo: Color(0xFF0A0A0B),
    superficie: Color(0xFF151517),
    superficieElevada: Color(0xFF1D1D20),
    superficieHundida: Color(0xFF101012),
    superficieHover: Color(0xFF222226),
    borde: Color(0xFF242428),
    bordeFuerte: Color(0xFF3A3A40),
    tinta: Color(0xFFF6F6F3),
    tinta2: Color(0xFFA6A6A3),
    tinta3: Color(0xFF707070),
    acento: Color(0xFFFFC83D),
    acentoTinta: Color(0xFF111111),
    acentoLavado: Color(0x24FFC83D),
    acentoTexto: Color(0xFFFFC83D),
    negro: Color(0xFF131315),
    negroElevado: Color(0xFF1F1F22),
    negroBorde: Color(0xFF28282C),
    sobreNegro: Color(0xFFF6F6F3),
    sobreNegro2: Color(0xFF8E8E8C),
    sombra: Color(0x40000000),
    bien: Color(0xFF3DD68C),
    bienLavado: Color(0x1F3DD68C),
    observar: Color(0xFFF29D38),
    observarLavado: Color(0x1FF29D38),
    atencion: Color(0xFFFF7A45),
    atencionLavado: Color(0x1FFF7A45),
    critico: Color(0xFFF4555E),
    criticoLavado: Color(0x1FF4555E),
    neutro: Color(0xFF8A8A8F),
    neutroLavado: Color(0x1F8A8A8F),
  );

  /// Tema claro: blanco calido, tarjetas blancas con sombra suave y detalles
  /// en negro. Los colores de estado se oscurecen para no perder contraste.
  static const clara = Paleta(
    fondo: Color(0xFFF3F3F0),
    superficie: Color(0xFFFFFFFF),
    superficieElevada: Color(0xFFFFFFFF),
    superficieHundida: Color(0xFFF2F2EF),
    superficieHover: Color(0xFFEAEAE6),
    borde: Color(0xFFE8E8E3),
    bordeFuerte: Color(0xFFD3D3CD),
    tinta: Color(0xFF111112),
    tinta2: Color(0xFF55555A),
    tinta3: Color(0xFF8B8B90),
    acento: Color(0xFFFFC83D),
    acentoTinta: Color(0xFF111111),
    acentoLavado: Color(0x38FFC83D),
    acentoTexto: Color(0xFF111112),
    negro: Color(0xFF111112),
    negroElevado: Color(0xFF222225),
    negroBorde: Color(0xFF2C2C30),
    sobreNegro: Color(0xFFFFFFFF),
    sobreNegro2: Color(0xFF9A9A9E),
    sombra: Color(0x14000000),
    bien: Color(0xFF0E9A5E),
    bienLavado: Color(0x170E9A5E),
    observar: Color(0xFFC27400),
    observarLavado: Color(0x17C27400),
    atencion: Color(0xFFD9591C),
    atencionLavado: Color(0x17D9591C),
    critico: Color(0xFFD7373F),
    criticoLavado: Color(0x17D7373F),
    neutro: Color(0xFF6B6B72),
    neutroLavado: Color(0x176B6B72),
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
