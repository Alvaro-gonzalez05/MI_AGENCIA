import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/tema/colores.dart';
import '../core/tema/tema.dart';

/// Pastilla de estado. Es el componente mas repetido de la app: aparece en
/// cada fila del inventario, en cada ficha y en cada interesado.
class Pastilla extends StatelessWidget {
  const Pastilla({
    super.key,
    required this.texto,
    required this.color,
    required this.lavado,
    this.conPunto = true,
  });

  final String texto;
  final Color color;
  final Color lavado;
  final bool conPunto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.md, vertical: 6),
      decoration: BoxDecoration(
        color: lavado,
        borderRadius: BorderRadius.circular(Curva.completo),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conPunto) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Esp.sm - 2),
          ],
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta base. Todo panel de la app sale de aca, para que el radio, el
/// borde y el relleno sean identicos en todas las pantallas.
///
/// Cuando es tocable se eleva un poco al pasar el mouse y se hunde al
/// presionarla: es la respuesta que hace que la app se sienta viva.
class Tarjeta extends StatefulWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Esp.lg + 2),
    this.onTap,
    this.destacada = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Tarjeta negra, en los dos temas. Para el dato mas importante de la
  /// pantalla. El contenido tiene que usar `sobreNegro` como color de texto.
  final bool destacada;

  /// Relleno propio (por ejemplo, amarillo). Sin borde.
  final Color? color;

  @override
  State<Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<Tarjeta> {
  bool _hover = false;
  bool _presionada = false;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final oscuro = context.esOscuro;
    final interactiva = widget.onTap != null;
    final elevada = interactiva && _hover;
    final radio = BorderRadius.circular(Curva.lg);

    final fondo = widget.color ?? (widget.destacada ? p.negro : p.superficie);
    final borde = widget.color != null
        ? widget.color!
        : widget.destacada
        ? p.negroBorde
        : elevada
        ? p.bordeFuerte
        : (oscuro ? p.borde : p.borde.withValues(alpha: 0.7));

    return AnimatedScale(
      scale: _presionada ? 0.985 : 1,
      duration: Duracion.rapida,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: Duracion.media,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, elevada ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: radio,
          border: Border.all(color: borde),
          boxShadow: [
            BoxShadow(
              color: oscuro ? Colors.transparent : p.sombra,
              blurRadius: elevada ? 30 : 18,
              offset: Offset(0, elevada ? 12 : 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHover: interactiva ? (h) => setState(() => _hover = h) : null,
            onHighlightChanged: interactiva
                ? (h) => setState(() => _presionada = h)
                : null,
            borderRadius: radio,
            hoverColor: Colors.transparent,
            splashColor: p.acento.withValues(alpha: 0.10),
            highlightColor: Colors.transparent,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Aparicion con fundido y desplazamiento hacia arriba.
///
/// [indice] escalona la entrada de los elementos de una lista: cada uno
/// arranca un poco despues del anterior, hasta un tope para que una lista
/// larga no tarde en terminar de aparecer.
class Aparecer extends StatelessWidget {
  const Aparecer({
    super.key,
    required this.child,
    this.indice = 0,
    this.desplazamiento = 18,
  });

  final Widget child;
  final int indice;
  final double desplazamiento;

  @override
  Widget build(BuildContext context) {
    final demora = (indice > 8 ? 8 : indice) * 45;
    final total = 380 + demora;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(demora / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, hijo) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * desplazamiento),
          child: hijo,
        ),
      ),
      child: child,
    );
  }
}

/// Etiqueta de seccion: chica, con tracking, en el color mas tenue.
class EtiquetaSeccion extends StatelessWidget {
  const EtiquetaSeccion(this.texto, {super.key, this.color});
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    texto.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
  );
}

/// Titulo de bloque con accion opcional a la derecha ("Ver todo").
class CabeceraBloque extends StatelessWidget {
  const CabeceraBloque({
    super.key,
    required this.titulo,
    this.descripcion,
    this.accion,
    this.onAccion,
    this.sobreNegro = false,
  });

  final String titulo;
  final String? descripcion;
  final String? accion;
  final VoidCallback? onAccion;
  final bool sobreNegro;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: sobreNegro ? p.sobreNegro : p.tinta,
                ),
              ),
              if (descripcion != null) ...[
                const SizedBox(height: 2),
                Text(
                  descripcion!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: sobreNegro ? p.sobreNegro2 : p.tinta3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (accion != null)
          TextButton(
            onPressed: onAccion,
            style: TextButton.styleFrom(
              foregroundColor: sobreNegro ? p.acento : p.tinta2,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(accion!),
          ),
      ],
    );
  }
}

/// Icono dentro de un circulo de color suave.
class IconoEnCirculo extends StatelessWidget {
  const IconoEnCirculo({
    super.key,
    required this.icono,
    this.color,
    this.fondo,
    this.tamano = 40,
  });

  final IconData icono;
  final Color? color;
  final Color? fondo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo ?? p.superficieHundida,
        shape: BoxShape.circle,
      ),
      child: Icon(icono, size: tamano * 0.46, color: color ?? p.tinta2),
    );
  }
}

/// Boton de icono redondo, con borde. Para acciones secundarias de cabecera.
class BotonCircular extends StatelessWidget {
  const BotonCircular({
    super.key,
    required this.icono,
    required this.onTap,
    this.tooltip,
    this.tamano = 42,
    this.relleno,
    this.colorIcono,
    this.conBorde = true,
  });

  final IconData icono;
  final VoidCallback? onTap;
  final String? tooltip;
  final double tamano;
  final Color? relleno;
  final Color? colorIcono;
  final bool conBorde;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final boton = Material(
      color: relleno ?? p.superficie,
      shape: CircleBorder(
        side: conBorde ? BorderSide(color: p.borde) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: tamano,
          height: tamano,
          child: Icon(icono, size: tamano * 0.44, color: colorIcono ?? p.tinta),
        ),
      ),
    );
    return tooltip == null ? boton : Tooltip(message: tooltip, child: boton);
  }
}

/// Chip seleccionable en pildora.
///
/// Sin [color], el estado activo es amarillo con texto negro (seleccion
/// comun). Con [color] (un semaforo), el activo toma ese color lavado: asi un
/// filtro "Critico" nunca se ve amarillo.
class ChipSeleccion extends StatelessWidget {
  const ChipSeleccion({
    super.key,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
    this.color,
    this.icono,
  });

  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = color;

    final Color fondo;
    final Color tinta;
    final Color borde;
    if (!activo) {
      fondo = p.superficie;
      tinta = p.tinta2;
      borde = p.borde;
    } else if (c == null) {
      fondo = p.acento;
      tinta = p.acentoTinta;
      borde = p.acento;
    } else {
      fondo = c.withValues(alpha: 0.16);
      tinta = c;
      borde = c.withValues(alpha: 0.55);
    }

    return AnimatedContainer(
      duration: Duracion.media,
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: fondo,
        shape: StadiumBorder(side: BorderSide(color: borde)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          // Sin `alignment` ni Center: estirarian el chip hasta las
          // constraints maximas y en movil cada uno ocuparia todo el ancho.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Esp.lg - 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c != null) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Esp.sm - 1),
                  ],
                  if (icono != null) ...[
                    Icon(icono, size: 16, color: activo ? tinta : p.tinta3),
                    const SizedBox(width: Esp.sm - 2),
                  ],
                  Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                      color: tinta,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de metrica del dashboard: un numero grande y su contexto.
///
/// El numero va en mono y en tamano grande porque es lo unico que el usuario
/// realmente viene a leer; todo lo demas es andamiaje.
class TarjetaMetrica extends StatelessWidget {
  const TarjetaMetrica({
    super.key,
    required this.titulo,
    required this.valor,
    this.detalle,
    this.detalleColor,
    this.icono,
    this.onTap,
    this.resaltada = false,
  });

  final String titulo;
  final String valor;
  final String? detalle;
  final Color? detalleColor;
  final IconData? icono;
  final VoidCallback? onTap;

  /// Fondo amarillo. Una sola por pantalla: es la metrica principal.
  final bool resaltada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final tinta = resaltada ? p.acentoTinta : p.tinta;
    final tenue = resaltada ? p.acentoTinta.withValues(alpha: 0.62) : p.tinta3;

    return Tarjeta(
      onTap: onTap,
      color: resaltada ? p.acento : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icono != null)
                IconoEnCirculo(
                  icono: icono!,
                  tamano: 38,
                  color: resaltada ? p.acento : p.tinta,
                  fondo: resaltada ? p.acentoTinta : p.superficieHundida,
                ),
              const Spacer(),
              if (onTap != null)
                Icon(Icons.arrow_outward_rounded, size: 18, color: tenue),
            ],
          ),
          const SizedBox(height: Esp.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: tenue,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.8,
                    color: tinta,
                  ),
                ),
              ),
              if (detalle != null) ...[
                const SizedBox(height: 2),
                Text(
                  detalle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: resaltada ? tinta : (detalleColor ?? p.tinta3),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor, para fichas y paneles de detalle.
class FilaDato extends StatelessWidget {
  const FilaDato({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.valorColor,
    this.destacado = false,
    this.mono = true,
  });

  final String etiqueta;
  final String valor;
  final Color? valorColor;
  final bool destacado;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Esp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 13, color: p.tinta2),
            ),
          ),
          const SizedBox(width: Esp.md),
          Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: mono ? TemaApp.mono : null,
              fontSize: destacado ? 16 : 13.5,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
              color: valorColor ?? p.tinta,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de progreso gruesa y redondeada. Anima hasta su valor.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({
    super.key,
    required this.valor,
    this.color,
    this.fondo,
    this.alto = 8,
  });

  final double valor;
  final Color? color;
  final Color? fondo;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor.clamp(0.0, 1.0)),
      duration: Duracion.lenta,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(Curva.completo),
        child: LinearProgressIndicator(
          value: v,
          minHeight: alto,
          backgroundColor: fondo ?? p.superficieHundida,
          valueColor: AlwaysStoppedAnimation(color ?? p.acento),
        ),
      ),
    );
  }
}

/// Estado vacio. Existe como componente propio porque una app de gestion pasa
/// mucho tiempo sin datos (agencia recien dada de alta, filtro sin resultados)
/// y esas pantallas son las que definen si se siente terminada o a medio hacer.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? descripcion;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Esp.xl),
        child: Aparecer(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: p.acentoLavado,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, color: p.acentoTexto, size: 30),
                ),
                const SizedBox(height: Esp.lg + 2),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (descripcion != null) ...[
                  const SizedBox(height: Esp.sm),
                  Text(
                    descripcion!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: p.tinta3,
                      height: 1.5,
                    ),
                  ),
                ],
                if (accion != null) ...[
                  const SizedBox(height: Esp.xl),
                  accion!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartel de modo demo. Deliberadamente visible: nadie tiene que confundir
/// datos de ejemplo con datos reales de la agencia.
class CintaDemo extends StatelessWidget {
  const CintaDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: 6),
      color: p.acento,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined, size: 14, color: p.acentoTinta),
          const SizedBox(width: Esp.sm),
          Flexible(
            child: Text(
              'Modo demo — datos de ejemplo, sin conexión a la base',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.acentoTinta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra un monto en pesos y, debajo, su equivalente en dolares.
class MontoDual extends StatelessWidget {
  const MontoDual({
    super.key,
    required this.pesos,
    required this.tipoCambio,
    this.tamano = 20,
    this.color,
    this.colorSecundario,
  });

  final double pesos;
  final double tipoCambio;
  final double tamano;
  final Color? color;
  final Color? colorSecundario;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Fmt.pesos(pesos),
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: tamano,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: color ?? p.tinta,
            ),
          ),
        ),
        Text(
          Fmt.dolares(tipoCambio > 0 ? pesos / tipoCambio : 0),
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 12,
            color: colorSecundario ?? p.tinta3,
          ),
        ),
      ],
    );
  }
}
