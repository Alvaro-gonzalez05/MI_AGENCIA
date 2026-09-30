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
    this.icono,
  });

  final String texto;
  final Color color;
  final Color lavado;
  final bool conPunto;

  /// Reemplaza al punto cuando la pastilla dice una tendencia ("viene mejor
  /// que agosto" con su flechita, como en el diseno).
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.sm),
      decoration: BoxDecoration(
        color: lavado,
        borderRadius: BorderRadius.circular(Curva.completo),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // El punto solido es la tercera senal del diseno, despues del
          // color de fondo y del texto: quien no distingue verde de rojo
          // igual lee la etiqueta, y quien mira de lejos ve el punto.
          if (icono != null) ...[
            Icon(icono, size: 18, color: color),
            const SizedBox(width: Esp.sm - 2),
          ] else if (conPunto) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Esp.sm),
          ],
          // Flexible y no Text pelado: con mainAxisSize.min la pastilla
          // toma su ancho natural cuando hay lugar, pero adentro de una
          // columna angosta (el desglose por entidad en un celular) el texto
          // desbordaba la pastilla en vez de recortarse.
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
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
        ? p.tinta
        : p.borde;

    return AnimatedScale(
      scale: _presionada ? 0.985 : 1,
      duration: Duracion.rapida,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: Duracion.media,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, elevada ? -3 : 0, 0),
        // El diseno evita las sombras difusas: la profundidad la da el
        // borde (1,5 px en reposo, 2 px y oscuro al pasar el mouse) mas una
        // sombra corta y direccional. Con un monitor mal calibrado, un borde
        // se ve siempre; una sombra suave, no.
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: radio,
          border: Border.all(color: borde, width: elevada ? 2 : 1.5),
          boxShadow: [
            BoxShadow(
              color: oscuro ? Colors.transparent : p.sombra,
              blurRadius: elevada ? 12 : 6,
              offset: Offset(0, elevada ? 4 : 2),
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
    // Un poco mas rapido y con menos escalones que antes: ahora que el cambio
    // de seccion no tiene animacion de pagina propia, esta es LA animacion que
    // se ve al entrar, y la lista entera tiene que terminar de acomodarse
    // antes de que uno vaya a tocar algo. Con el tope en 6, una lista de
    // treinta unidades no tarda mas que una de seis.
    final demora = (indice > 6 ? 6 : indice) * 38;
    final total = 320 + demora;

    if (MediaQuery.disableAnimationsOf(context)) return child;

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
                    fontSize: 13,
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

/// Chip / pestana seleccionable.
///
/// Sin [color], el activo es la pestana oscura del diseno: fondo carbon y
/// texto claro, que se distingue de un vistazo aunque la pantalla este
/// lavada por el sol. Con [color] (un semaforo), el activo toma ese color
/// lavado: asi un filtro "Riesgo alto" nunca se ve ambar.
///
/// [contador] es el numero entre parentesis del diseno. Va en su propia
/// burbuja y no pegado al texto: se lee como dato, no como parte del nombre.
class ChipSeleccion extends StatelessWidget {
  const ChipSeleccion({
    super.key,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
    this.color,
    this.icono,
    this.contador,
  });

  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icono;
  final int? contador;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = color;

    final Color fondo;
    final Color tinta;
    final Color borde;
    final Color fondoContador;
    if (!activo) {
      fondo = p.superficieHundida;
      tinta = p.tinta2;
      borde = p.borde;
      fondoContador = p.superficieHover;
    } else if (c == null) {
      // En claro, la pestana activa es la oscura del diseno. En oscuro esa
      // misma pastilla se confundiria con el fondo, asi que manda el ambar.
      final oscuro = context.esOscuro;
      fondo = oscuro ? p.acento : p.negro;
      tinta = oscuro ? p.acentoTinta : p.sobreNegro;
      borde = fondo;
      fondoContador = (oscuro ? p.acentoTinta : p.sobreNegro).withValues(
        alpha: 0.16,
      );
    } else {
      fondo = c.withValues(alpha: 0.16);
      tinta = c;
      borde = c.withValues(alpha: 0.55);
      fondoContador = c.withValues(alpha: 0.18);
    }

    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Curva.md),
      side: BorderSide(color: borde, width: 1.5),
    );

    return AnimatedContainer(
      duration: Duracion.media,
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(color: fondo, shape: forma),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: forma,
          // Sin `alignment` ni Center: estirarian el chip hasta las
          // constraints maximas y en movil cada uno ocuparia todo el ancho.
          child: ConstrainedBox(
            // 48: el toque minimo comodo que pide el diseno.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Esp.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Esp.sm),
                  ],
                  if (icono != null) ...[
                    Icon(icono, size: 20, color: activo ? tinta : p.tinta3),
                    const SizedBox(width: Esp.sm - 2),
                  ],
                  Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                      color: tinta,
                    ),
                  ),
                  if (contador != null) ...[
                    const SizedBox(width: Esp.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Esp.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: fondoContador,
                        borderRadius: BorderRadius.circular(Curva.completo),
                      ),
                      child: Text(
                        '$contador',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tinta,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buscador del diseno: alto de 54, lupa grande y texto de 16.
///
/// Aparece igual en inventario, clientes y ventas: buscar es lo primero que
/// hace alguien que ya tiene datos cargados.
class Buscador extends StatelessWidget {
  const Buscador({
    super.key,
    required this.texto,
    required this.onCambio,
    this.pista = 'Buscar...',
    this.controlador,
  });

  final String texto;
  final ValueChanged<String> onCambio;
  final String pista;
  final TextEditingController? controlador;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.lg),
        border: Border.all(color: p.borde, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 26, color: p.tinta2),
          const SizedBox(width: Esp.md),
          Expanded(
            child: TextField(
              controller: controlador,
              onChanged: onCambio,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 16, color: p.tinta),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: Esp.lg),
                hintText: pista,
                hintStyle: TextStyle(fontSize: 16, color: p.tinta3),
              ),
            ),
          ),
          if (texto.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close_rounded, size: 22),
              onPressed: () {
                controlador?.clear();
                onCambio('');
              },
            ),
        ],
      ),
    );
  }
}

/// Encabezado de pantalla: titulo grande, cuanto hay y la accion principal.
///
/// El subtitulo con el conteo ("24 clientes en total") es del diseno y no es
/// decorativo: responde de entrada la pregunta con la que uno entra a una
/// pantalla de listado.
class CabeceraPantalla extends StatelessWidget {
  const CabeceraPantalla({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.accion,
  });

  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final textos = Theme.of(context).textTheme;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final titulos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: textos.displaySmall),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(subtitulo!, style: TextStyle(fontSize: 16, color: p.tinta2)),
        ],
      ],
    );

    if (accion == null) return titulos;

    // En celular la accion baja a su propia linea y ocupa el ancho: un boton
    // de 52 px al alcance del pulgar vale mas que una fila prolija.
    return angosto
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titulos,
              const SizedBox(height: Esp.md),
              accion!,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titulos),
              const SizedBox(width: Esp.lg),
              accion!,
            ],
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
          // Flexible por si el alto del grid queda corto: preferimos que el
          // bloque encoja antes que ver la franja de overflow de Flutter.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: resaltada ? tinta : (detalleColor ?? p.tinta3),
                    ),
                  ),
                ],
              ],
            ),
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
      // Los dos lados son flexibles y el valor se queda con la porcion mas
      // grande. Antes el valor era un Text suelto y tomaba su ancho natural:
      // alcanzaba con un dato largo ("V007 Toyota Hilux SRX 4x4 automatica")
      // para desbordar la fila en un celular. Como el valor ya iba alineado a
      // la derecha, los datos cortos se siguen viendo igual que siempre.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 14, color: p.tinta2),
            ),
          ),
          const SizedBox(width: Esp.md),
          Flexible(
            flex: 6,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: mono ? TemaApp.mono : null,
                fontSize: destacado ? 16 : 13.5,
                fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
                color: valorColor ?? p.tinta,
              ),
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
            constraints: const BoxConstraints(maxWidth: 420),
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
                      fontSize: 16,
                      color: p.tinta2,
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
                fontSize: 14,
                fontWeight: FontWeight.w700,
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
            fontSize: 14,
            color: colorSecundario ?? p.tinta3,
          ),
        ),
      ],
    );
  }
}

/// Caja con el borde punteado, como la de "Agendar una tarea" en el diseño.
///
/// Flutter no trae bordes punteados, así que se dibuja a mano: un trazo,
/// un hueco, y vuelta a empezar, sobre un rectángulo redondeado.
class BordePunteado extends StatelessWidget {
  const BordePunteado({
    super.key,
    required this.child,
    this.color,
    this.radio = Curva.md,
  });

  final Widget child;
  final Color? color;
  final double radio;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PintorPunteado(
      color: color ?? context.paleta.bordeFuerte,
      radio: radio,
    ),
    child: child,
  );
}

class _PintorPunteado extends CustomPainter {
  _PintorPunteado({required this.color, required this.radio});

  final Color color;
  final double radio;

  @override
  void paint(Canvas canvas, Size size) {
    final lapiz = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final camino = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6),
          Radius.circular(radio),
        ),
      );

    for (final tramo in camino.computeMetrics()) {
      var d = 0.0;
      while (d < tramo.length) {
        canvas.drawPath(
          tramo.extractPath(d, (d + 6).clamp(0, tramo.length)),
          lapiz,
        );
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_PintorPunteado otro) => otro.color != color;
}
