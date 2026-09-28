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

/// Radios. Los del diseno "Clarity Drive": formas solidas, de boton fisico,
/// no pildoras. Botones y campos en [md], tarjetas en [lg], modales en [xl].
abstract final class Curva {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const completo = 999.0;
}

/// Duraciones de animacion. Cortas: la app se usa muchas horas y una
/// animacion lenta se vuelve una espera.
abstract final class Duracion {
  static const rapida = Duration(milliseconds: 160);
  static const media = Duration(milliseconds: 260);
  static const lenta = Duration(milliseconds: 420);
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

/// Transicion entre pantallas: fundido con un desplazamiento minimo hacia
/// arriba. Mas suave que el zoom de Material y igual en Windows y Android.
class TransicionSuave extends PageTransitionsBuilder {
  const TransicionSuave();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curva = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // Los formularios de pantalla completa suben un poco mas: se leen como
    // algo que se abre encima, no como otra seccion.
    final desde = route.fullscreenDialog
        ? const Offset(0, 0.06)
        : const Offset(0, 0.015);

    // La pantalla que queda atras se apaga y retrocede un poco mientras la
    // nueva la tapa. Sin esto las dos se ven igual de vivas y la de adelante
    // parece pegada encima en vez de estar adelante.
    final tapada = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.65).animate(tapada),
      child: SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: const Offset(0, -0.012),
        ).animate(tapada),
        child: FadeTransition(
          opacity: curva,
          child: SlideTransition(
            position: Tween(begin: desde, end: Offset.zero).animate(curva),
            child: child,
          ),
        ),
      ),
    );
  }
}

abstract final class TemaApp {
  /// Todo lo que se lee: formularios, tablas, botones, descripciones.
  ///
  /// Atkinson Hyperlegible Next esta disenada para que no se confundan los
  /// caracteres parecidos (0 y O, 1 y l y I). En una app donde se tipean
  /// patentes, CUIT y precios, eso no es un detalle estetico.
  static const _sans = 'Atkinson';

  /// Titulos y cifras grandes. Mas estrecha y con mas caracter que la de
  /// texto: marca la jerarquia sin subir el tamano.
  static const titulo = 'WorkSans';

  /// Mono para TODO numero: precios, porcentajes, dias, fechas.
  ///
  /// No es capricho tipografico. En una tabla de inventario los precios se
  /// comparan en vertical, y con ancho variable las columnas de cifras quedan
  /// desalineadas y el ojo no puede escanearlas.
  static const mono = 'IBMPlexMono';

  static ThemeData oscuro() => _construir(Paleta.oscura, Brightness.dark);
  static ThemeData claro() => _construir(Paleta.clara, Brightness.light);

  /// Los botones del diseno no son pildoras: son rectangulos redondeados,
  /// con aspecto de tecla. El alto minimo (52) tambien es del diseno: apunta
  /// a que no se falle el toque en una tablet en el playon.
  static final _boton = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Curva.md),
  );
  static const _altoBoton = Size(0, 52);

  static ThemeData _construir(Paleta p, Brightness brillo) {
    final base = ThemeData(brightness: brillo, useMaterial3: true);

    final esquema =
        ColorScheme.fromSeed(seedColor: p.acento, brightness: brillo).copyWith(
          primary: p.acento,
          onPrimary: p.acentoTinta,
          secondary: p.negro,
          onSecondary: p.sobreNegro,
          surface: p.superficie,
          onSurface: p.tinta,
          error: p.critico,
          outline: p.borde,
        );

    final texto = _tipografia(p, base.textTheme);

    // label-lg del diseno: 16 px en negrita. Un boton que dice "Registrar
    // venta" tiene que leerse desde parado al lado del escritorio.
    const textoBoton = TextStyle(
      fontFamily: _sans,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );

    return base.copyWith(
      colorScheme: esquema,
      scaffoldBackgroundColor: p.fondo,
      canvasColor: p.fondo,
      dividerColor: p.borde,
      textTheme: texto,
      extensions: [TemaPaleta(p)],

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final plataforma in TargetPlatform.values)
            plataforma: const TransicionSuave(),
        },
      ),

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

      appBarTheme: AppBarTheme(
        backgroundColor: p.fondo,
        foregroundColor: p.tinta,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: brillo == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: texto.titleLarge,
      ),

      // Campos de 52 px de alto, borde de 2 px y texto de 16: el diseno los
      // quiere "de switch fisico", no de formulario web apretado.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brillo == Brightness.dark
            ? p.superficieHundida
            : p.superficieElevada,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Esp.lg,
          vertical: Esp.lg,
        ),
        hintStyle: TextStyle(color: p.tinta3, fontSize: 16),
        labelStyle: TextStyle(color: p.tinta2, fontSize: 15),
        floatingLabelStyle: TextStyle(color: p.acentoTexto, fontSize: 15),
        prefixIconColor: p.tinta3,
        suffixIconColor: p.tinta3,
        border: _borde(p.bordeFuerte, ancho: 1.6),
        enabledBorder: _borde(p.bordeFuerte, ancho: 1.6),
        focusedBorder: _borde(p.tinta, ancho: 2),
        errorBorder: _borde(p.critico, ancho: 1.6),
        focusedErrorBorder: _borde(p.critico, ancho: 2),
        errorStyle: TextStyle(color: p.critico, fontSize: 14),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.acentoTexto,
        selectionColor: p.acento.withValues(alpha: 0.35),
        selectionHandleColor: p.acento,
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
          shape: _boton,
          minimumSize: _altoBoton,
          textStyle: textoBoton,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.negro,
          foregroundColor: p.sobreNegro,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.xl,
            vertical: Esp.lg,
          ),
          shape: _boton,
          minimumSize: _altoBoton,
          textStyle: textoBoton,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.tinta,
          side: BorderSide(color: p.tinta, width: 1.6),
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.lg + 2,
            vertical: Esp.md,
          ),
          minimumSize: _altoBoton,
          shape: _boton,
          textStyle: textoBoton.copyWith(fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.acentoTexto,
          shape: _boton,
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.md + 2,
            vertical: Esp.sm + 2,
          ),
          textStyle: textoBoton.copyWith(fontWeight: FontWeight.w500),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.tinta2),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.acento,
        foregroundColor: p.acentoTinta,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        extendedTextStyle: textoBoton,
      ),

      iconTheme: IconThemeData(color: p.tinta2, size: 20),

      sliderTheme: SliderThemeData(
        activeTrackColor: p.acento,
        inactiveTrackColor: p.superficieHundida,
        thumbColor: p.acentoTexto,
        overlayColor: p.acento.withValues(alpha: 0.18),
        trackHeight: 6,
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        valueIndicatorColor: p.negro,
        valueIndicatorTextStyle: TextStyle(
          color: p.sobreNegro,
          fontFamily: mono,
          fontSize: 13,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acentoTinta : p.tinta3,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (e) =>
              e.contains(WidgetState.selected) ? p.acento : p.superficieHundida,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected)
              ? Colors.transparent
              : p.bordeFuerte,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acento : null,
        ),
        checkColor: WidgetStatePropertyAll(p.acentoTinta),
        side: BorderSide(color: p.tinta, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.sm - 2),
        ),
        visualDensity: VisualDensity.standard,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.negro,
        contentTextStyle: TextStyle(
          color: p.sobreNegro,
          fontFamily: _sans,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: p.acento,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const StadiumBorder(),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.superficieElevada,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.xl),
        ),
        titleTextStyle: texto.titleLarge,
        contentTextStyle: texto.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.superficieElevada,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.bordeFuerte,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Curva.xl)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: p.superficieElevada,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.md),
          side: BorderSide(color: p.borde),
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.superficieElevada,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.negro,
        headerForegroundColor: p.sobreNegro,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.xl),
        ),
        dayShape: const WidgetStatePropertyAll(CircleBorder()),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acento : null,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acentoTinta : null,
        ),
        todayBorder: BorderSide(color: p.acentoTexto),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acentoTinta : p.tinta,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.selected) ? p.acento : null,
        ),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.tinta),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.tinta2),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.negro,
          borderRadius: BorderRadius.circular(Curva.sm),
        ),
        textStyle: TextStyle(
          color: p.sobreNegro,
          fontFamily: _sans,
          fontSize: 13,
        ),
        waitDuration: const Duration(milliseconds: 400),
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

  /// La escala del diseno. Dos reglas que no se negocian:
  ///
  /// - **Nada por debajo de 14 px.** Los usuarios de una agencia son, muchas
  ///   veces, gente grande mirando una pantalla todo el dia.
  /// - **Los datos que importan, 16 o mas.** Un precio, un nombre o una
  ///   patente nunca van en letra chica.
  ///
  /// Los titulos van en Work Sans; todo lo demas, en Atkinson.
  static TextTheme _tipografia(Paleta p, TextTheme base) => base
      .apply(fontFamily: _sans, bodyColor: p.tinta, displayColor: p.tinta)
      .copyWith(
        // headline-xl: el titulo de una pantalla.
        displaySmall: TextStyle(
          fontFamily: titulo,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
          height: 1.2,
          color: p.tinta,
        ),
        // headline-lg
        headlineMedium: TextStyle(
          fontFamily: titulo,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          height: 1.25,
          color: p.tinta,
        ),
        // headline-md: titulo de tarjeta o de bloque.
        titleLarge: TextStyle(
          fontFamily: titulo,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.3,
          color: p.tinta,
        ),
        // headline-sm
        titleMedium: TextStyle(
          fontFamily: titulo,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: p.tinta,
        ),
        // body-lg
        bodyLarge: TextStyle(
          fontFamily: _sans,
          fontSize: 16,
          height: 1.45,
          color: p.tinta,
        ),
        // body-md: el tamano por defecto de la app.
        bodyMedium: TextStyle(
          fontFamily: _sans,
          fontSize: 15,
          height: 1.45,
          color: p.tinta2,
        ),
        // label-md: ayudas y metadatos. El piso de toda la app.
        bodySmall: TextStyle(
          fontFamily: _sans,
          fontSize: 14,
          height: 1.4,
          color: p.tinta3,
        ),
        // Etiquetas de seccion: con tracking, para que se lean como
        // estructura y no compitan con los datos.
        labelSmall: TextStyle(
          fontFamily: _sans,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: p.tinta3,
        ),
      );
}
