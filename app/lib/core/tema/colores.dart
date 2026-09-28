import 'package:flutter/material.dart';

/// Paleta del sistema de diseno "Clarity Drive".
///
/// Viene del diseno que entrego el cliente (Stitch, 09/2026). Cuatro reglas
/// explican casi todas las decisiones de abajo:
///
/// 1. **El tema base es CLARO**: un blanco calido tipo papel (#FCF9F8) que no
///    encandila despues de ocho horas de pantalla, con tarjetas blancas puras
///    encima. El oscuro existe y se elige en Mas.
///
/// 2. **El ambar se usa como RELLENO, no como tinta.** Ambar sobre blanco no
///    se lee. Por eso hay dos colores de acento: [acento] para fondos
///    (botones, pastillas activas, indicadores) y [acentoTexto] para cuando el
///    acento tiene que leerse como texto o icono sobre una superficie. En
///    oscuro es el mismo ambar; en claro es el marron oscuro de la marca.
///
/// 3. **Los semaforos no se confunden con el acento.** El ambar de marca
///    siempre va de relleno con texto oscuro; el semaforo "observar" va como
///    pastilla lavada con punto y etiqueta. Nunca aparecen con la misma forma.
///
/// 4. **Hay superficies oscuras en los dos temas.** La barra lateral, la barra
///    inferior del movil, la pestana activa y las tarjetas destacadas son
///    oscuras tambien en claro: es lo que ancla la vista y le da caracter.
///
/// Contraste: el diseno pide superar AAA en los textos. Por eso la tinta
/// principal es casi negra (#1C1B1B, 15:1 sobre el fondo) y la secundaria es
/// un marron oscuro (#4F4634), nunca un gris claro.
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

  /// El mismo sistema en oscuro: carbon calido (no negro azulado) para que el
  /// ambar de marca se vea igual de calido que en claro. Los estados suben de
  /// luminosidad para mantener el contraste sobre fondo oscuro.
  static const oscura = Paleta(
    fondo: Color(0xFF15140F),
    superficie: Color(0xFF1E1D19),
    superficieElevada: Color(0xFF272620),
    superficieHundida: Color(0xFF1A1915),
    superficieHover: Color(0xFF2E2D26),
    borde: Color(0xFF322F28),
    bordeFuerte: Color(0xFF4A463C),
    tinta: Color(0xFFF3F0EF),
    tinta2: Color(0xFFCBC3B4),
    tinta3: Color(0xFF9A9183),
    acento: Color(0xFFFFC53D),
    acentoTinta: Color(0xFF261900),
    acentoLavado: Color(0x24FFC53D),
    acentoTexto: Color(0xFFF7BE36),
    negro: Color(0xFF1B1A16),
    negroElevado: Color(0xFF262521),
    negroBorde: Color(0xFF34322B),
    sobreNegro: Color(0xFFF3F0EF),
    sobreNegro2: Color(0xFFB4ADA0),
    sombra: Color(0x40000000),
    bien: Color(0xFF62DF7D),
    bienLavado: Color(0x1F62DF7D),
    observar: Color(0xFFF7BE36),
    observarLavado: Color(0x1FF7BE36),
    atencion: Color(0xFFFF9A52),
    atencionLavado: Color(0x1FFF9A52),
    critico: Color(0xFFFF5449),
    criticoLavado: Color(0x1FFF5449),
    neutro: Color(0xFF9E9A90),
    neutroLavado: Color(0x1F9E9A90),
  );

  /// Tema por defecto: el del diseno. Fondo papel calido, tarjetas blancas
  /// puras con borde marcado (nada de sombras difusas), tinta casi negra y
  /// detalles en carbon. Los colores de estado son los del diseno, elegidos
  /// para leerse sin esfuerzo sobre fondo claro.
  static const clara = Paleta(
    fondo: Color(0xFFFCF9F8),
    superficie: Color(0xFFFFFFFF),
    superficieElevada: Color(0xFFFFFFFF),
    superficieHundida: Color(0xFFF6F3F2),
    superficieHover: Color(0xFFF0EDED),
    borde: Color(0xFFE5E2E1),
    bordeFuerte: Color(0xFFD3C5AE),
    tinta: Color(0xFF1C1B1B),
    tinta2: Color(0xFF4F4634),
    tinta3: Color(0xFF817662),
    acento: Color(0xFFFFC53D),
    acentoTinta: Color(0xFF715200),
    acentoLavado: Color(0x38FFC53D),
    acentoTexto: Color(0xFF795900),
    negro: Color(0xFF313030),
    negroElevado: Color(0xFF3D3B3B),
    negroBorde: Color(0xFF4A4747),
    sobreNegro: Color(0xFFF3F0EF),
    sobreNegro2: Color(0xFFC8C6C5),
    sombra: Color(0x14161616),
    bien: Color(0xFF166534),
    bienLavado: Color(0xFFDCFCE7),
    observar: Color(0xFF78350F),
    observarLavado: Color(0xFFFEF3C7),
    atencion: Color(0xFF9A3412),
    atencionLavado: Color(0xFFFFEDD5),
    critico: Color(0xFFBA1A1A),
    criticoLavado: Color(0xFFFFDAD6),
    neutro: Color(0xFF1F2937),
    neutroLavado: Color(0xFFF3F4F6),
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
