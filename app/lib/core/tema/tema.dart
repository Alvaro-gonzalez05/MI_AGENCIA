import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colores.dart';

/// Escala de espaciado. Todo margen y padding sale de aca: nada de numeros
/// sueltos en los widgets. Es lo que hace que dos pantallas escritas en
/// momentos distintos se vean parte del mismo producto.
abstract final class Esp {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

abstract final class Curva {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const completo = 999.0;
}

/// Puntos de corte para el layout adaptativo.
///
/// El de 900 es el que importa: por debajo la navegacion va abajo (al alcance
/// del pulgar) y por encima va a la izquierda (al alcance del mouse).
abstract final class Corte {
  static const movil = 600.0;
  static const tablet = 900.0;
  static const escritorio = 1280.0;
}

abstract final class TemaApp {
  static const _sans = 'IBMPlexSans';

  /// Mono para TODO numero: precios, porcentajes, dias, fechas.
  ///
  /// No es capricho tipografico. En una tabla de inventario los precios se
  /// comparan en vertical, y con ancho variable las columnas de cifras quedan
  /// desalineadas y el ojo no puede escanearlas.
  static const mono = 'IBMPlexMono';

  static ThemeData oscuro() => _construir(Paleta.oscura, Brightness.dark);
  static ThemeData claro() => _construir(Paleta.clara, Brightness.light);

  static ThemeData _construir(Paleta p, Brightness brillo) {
    final base = ThemeData(brightness: brillo, useMaterial3: true);

    final esquema =
        ColorScheme.fromSeed(seedColor: p.acento, brightness: brillo).copyWith(
          primary: p.acento,
          onPrimary: p.acentoTinta,
          surface: p.superficie,
          onSurface: p.tinta,
          error: p.critico,
          outline: p.borde,
        );

    final texto = _tipografia(p, base.textTheme);

    return base.copyWith(
      colorScheme: esquema,
      scaffoldBackgroundColor: p.fondo,
      canvasColor: p.fondo,
      dividerColor: p.borde,
      textTheme: texto,
      extensions: [TemaPaleta(p)],

      dividerTheme: DividerThemeData(color: p.borde, thickness: 1, space: 1),

      cardTheme: CardThemeData(
        color: p.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.lg),
          side: BorderSide(color: p.borde),
        ),
      ),

      // Sin sombras en ningun lado: la jerarquia se construye con el color de
      // la superficie y el borde. Las sombras sobre fondo oscuro son casi
      // invisibles y solo ensucian.
      appBarTheme: AppBarTheme(
        backgroundColor: p.fondo,
        foregroundColor: p.tinta,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: brillo == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: texto.titleMedium,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.superficieHundida,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Esp.md,
          vertical: Esp.md,
        ),
        hintStyle: TextStyle(color: p.tinta3, fontSize: 14),
        labelStyle: TextStyle(color: p.tinta2, fontSize: 13),
        floatingLabelStyle: TextStyle(color: p.acento, fontSize: 13),
        prefixIconColor: p.tinta3,
        suffixIconColor: p.tinta3,
        border: _borde(p.borde),
        enabledBorder: _borde(p.borde),
        focusedBorder: _borde(p.acento, ancho: 1.6),
        errorBorder: _borde(p.critico),
        focusedErrorBorder: _borde(p.critico, ancho: 1.6),
        errorStyle: TextStyle(color: p.critico, fontSize: 12),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.acento,
          foregroundColor: p.acentoTinta,
          disabledBackgroundColor: p.bordeFuerte,
          disabledForegroundColor: p.tinta3,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.xl,
            vertical: Esp.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Curva.md),
          ),
          textStyle: const TextStyle(
            fontFamily: _sans,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.tinta,
          side: BorderSide(color: p.bordeFuerte),
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.lg,
            vertical: Esp.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Curva.md),
          ),
          textStyle: const TextStyle(
            fontFamily: _sans,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.acento,
          textStyle: const TextStyle(
            fontFamily: _sans,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      iconTheme: IconThemeData(color: p.tinta2, size: 20),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.superficieElevada,
        contentTextStyle: TextStyle(
          color: p.tinta,
          fontFamily: _sans,
          fontSize: 13.5,
        ),
        actionTextColor: p.acento,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.md),
          side: BorderSide(color: p.borde),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.superficieElevada,
          borderRadius: BorderRadius.circular(Curva.sm),
          border: Border.all(color: p.bordeFuerte),
        ),
        textStyle: TextStyle(color: p.tinta, fontFamily: _sans, fontSize: 12),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.acento,
        linearTrackColor: p.superficieHundida,
        circularTrackColor: p.superficieHundida,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.bordeFuerte),
        radius: const Radius.circular(Curva.completo),
        thickness: const WidgetStatePropertyAll(6),
      ),

      splashFactory: InkSparkle.splashFactory,
    );
  }

  static OutlineInputBorder _borde(Color color, {double ancho = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Curva.md),
        borderSide: BorderSide(color: color, width: ancho),
      );

  static TextTheme _tipografia(Paleta p, TextTheme base) => base
      .apply(fontFamily: _sans, bodyColor: p.tinta, displayColor: p.tinta)
      .copyWith(
        displaySmall: TextStyle(
          fontFamily: _sans,
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: p.tinta,
        ),
        headlineMedium: TextStyle(
          fontFamily: _sans,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: p.tinta,
        ),
        titleLarge: TextStyle(
          fontFamily: _sans,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: p.tinta,
        ),
        titleMedium: TextStyle(
          fontFamily: _sans,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: p.tinta,
        ),
        bodyLarge: TextStyle(fontFamily: _sans, fontSize: 14.5, color: p.tinta),
        bodyMedium: TextStyle(
          fontFamily: _sans,
          fontSize: 13.5,
          color: p.tinta2,
        ),
        bodySmall: TextStyle(
          fontFamily: _sans,
          fontSize: 12.5,
          color: p.tinta3,
        ),
        // Encabezados de tabla y etiquetas de seccion: chicas, en versalitas
        // falsas y con mucho tracking, para que se lean como estructura y no
        // compitan con los datos.
        labelSmall: TextStyle(
          fontFamily: _sans,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: p.tinta3,
        ),
      );
}
