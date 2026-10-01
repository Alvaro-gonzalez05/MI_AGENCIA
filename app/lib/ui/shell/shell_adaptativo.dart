import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../datos/repositorio.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/control_tema.dart';
import '../../core/tema/preferencias.dart';
import '../../core/tema/tema.dart';
import '../componentes.dart';
import 'secciones.dart';

/// Cascara de la app.
///
/// Un solo widget resuelve las tres formas porque la navegacion es la misma
/// en todas; lo unico que cambia es donde se dibuja:
///
///   < 900 px  -> barra inferior flotante (al alcance del pulgar) + hoja "Más"
///   900-1280  -> barra lateral negra, solo iconos
///   > 1280 px -> barra lateral negra completa con etiquetas y grupos
class ShellAdaptativo extends ConsumerWidget {
  const ShellAdaptativo({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esMovil = ancho < Corte.tablet;
    final compacta = ancho < Corte.escritorio;

    final usuario = ref.watch(usuarioProvider);
    final rutaActual = GoRouterState.of(context).uri.path;
    final seccion = Secciones.porRuta(rutaActual) ?? Secciones.panel;

    if (esMovil) {
      return _ShellMovil(seccion: seccion, usuario: usuario, child: child);
    }

    return Scaffold(
      body: Column(
        children: [
          if (Config.modoDemo) const CintaDemo(),
          Expanded(
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Esp.md, Esp.md, 0, Esp.md),
                  child: _BarraLateral(
                    seccionActual: seccion,
                    usuario: usuario,
                    compacta: compacta,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _EncabezadoPantalla(seccion: seccion, usuario: usuario),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Hola, Álvaro 👋" para el panel; el titulo de la seccion para el resto.
String _tituloDe(Seccion seccion, Usuario? usuario) {
  if (seccion.id != Secciones.panel.id) return seccion.titulo;
  final nombre = usuario?.nombre.trim().split(RegExp(r'\s+')).first ?? '';
  return nombre.isEmpty ? 'Hola 👋' : 'Hola, $nombre 👋';
}

/// Cambio animado de titulos al pasar de una seccion a otra.
Widget _transicionTitulo(Widget hijo, Animation<double> animacion) =>
    FadeTransition(
      opacity: animacion,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(animacion),
        child: hijo,
      ),
    );

Widget _apilarIzquierda(Widget? actual, List<Widget> previos) =>
    Stack(alignment: Alignment.centerLeft, children: [...previos, ?actual]);

// ---------------------------------------------------------------------------
// ESCRITORIO
// ---------------------------------------------------------------------------

class _BarraLateral extends ConsumerWidget {
  const _BarraLateral({
    required this.seccionActual,
    required this.usuario,
    required this.compacta,
  });

  final Seccion seccionActual;
  final Usuario? usuario;
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final secciones = Secciones.visibles(
      esDesarrollador: usuario?.esDesarrollador ?? false,
    );

    String? grupoAnterior;
    final items = <Widget>[];
    for (final s in secciones) {
      if (s.grupo != grupoAnterior) {
        grupoAnterior = s.grupo;
        items.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              compacta ? Esp.md : Esp.lg,
              items.isEmpty ? Esp.sm : Esp.xl,
              Esp.md,
              Esp.sm,
            ),
            child: compacta
                ? Divider(color: p.negroBorde, height: 1)
                : EtiquetaSeccion(s.grupo, color: p.sobreNegro2),
          ),
        );
      }
      items.add(
        _EnlaceNav(
          seccion: s,
          activo: s.id == seccionActual.id,
          compacta: compacta,
        ),
      );
    }

    // Sin animar el ancho: a mitad de camino las etiquetas no entran y Flutter
    // marca desborde en cada cuadro.
    return Container(
      width: compacta ? 80 : 252,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.negro,
        borderRadius: BorderRadius.circular(Curva.xl),
        border: Border.all(color: p.negroBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Marca(compacta: compacta, agencia: usuario?.agenciaNombre),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: Esp.md,
                vertical: Esp.sm,
              ),
              children: items,
            ),
          ),
          _PieUsuario(usuario: usuario, compacta: compacta),
        ],
      ),
    );
  }
}

/// Logo: cuadrado amarillo redondeado con el auto en negro.
class _Logo extends StatelessWidget {
  const _Logo();

  static const tamano = 40.0;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: p.acento,
        borderRadius: BorderRadius.circular(tamano * 0.32),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/icono/icono.png', semanticLabel: 'Mi Agencia'),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.compacta, this.agencia});

  final bool compacta;
  final String? agencia;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: compacta ? Esp.sm : Esp.lg + 4),
      alignment: compacta ? Alignment.center : Alignment.centerLeft,
      child: compacta
          ? const _Logo()
          : Row(
              children: [
                const _Logo(),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Mi ',
                              style: TextStyle(color: p.sobreNegro),
                            ),
                            TextSpan(
                              text: 'Agencia',
                              style: TextStyle(color: p.acento),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          height: 1.2,
                        ),
                      ),
                      if (agencia != null)
                        Text(
                          agencia!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.sobreNegro2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _EnlaceNav extends StatefulWidget {
  const _EnlaceNav({
    required this.seccion,
    required this.activo,
    required this.compacta,
  });

  final Seccion seccion;
  final bool activo;
  final bool compacta;

  @override
  State<_EnlaceNav> createState() => _EnlaceNavState();
}

class _EnlaceNavState extends State<_EnlaceNav> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final activo = widget.activo;
    final compacta = widget.compacta;
    final color = activo
        ? p.acentoTinta
        : (_hover ? p.sobreNegro : p.sobreNegro2);

    final contenido = compacta
        ? Center(child: Icon(widget.seccion.icono, size: 21, color: color))
        : Row(
            children: [
              AnimatedSlide(
                duration: Duracion.media,
                curve: Curves.easeOutCubic,
                offset: Offset(_hover && !activo ? 0.12 : 0, 0),
                child: Icon(widget.seccion.icono, size: 20, color: color),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  widget.seccion.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          );

    final boton = AnimatedContainer(
      duration: Duracion.media,
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: activo
            ? p.acento
            : (_hover ? p.negroElevado : p.negro.withValues(alpha: 0)),
        shape: const StadiumBorder(),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.go(widget.seccion.ruta),
          onHover: (h) => setState(() => _hover = h),
          customBorder: const StadiumBorder(),
          hoverColor: Colors.transparent,
          splashColor: p.acento.withValues(alpha: 0.18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compacta ? Esp.sm : Esp.lg,
              vertical: Esp.md,
            ),
            child: contenido,
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.xs),
      child: compacta
          ? Tooltip(message: widget.seccion.etiqueta, child: boton)
          : boton,
    );
  }
}

/// Alterna claro/oscuro con el icono girando al cambiar.
class _BotonTema extends ConsumerWidget {
  const _BotonTema({required this.colorIcono});

  final Color colorIcono;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oscuro = ref.watch(temaProvider) == ThemeMode.dark;

    return Tooltip(
      message: oscuro ? 'Tema claro' : 'Tema oscuro',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => ref.read(temaProvider.notifier).alternar(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: AnimatedSwitcher(
              duration: Duracion.lenta,
              transitionBuilder: (hijo, animacion) => RotationTransition(
                turns: Tween<double>(begin: 0.5, end: 1).animate(animacion),
                child: FadeTransition(opacity: animacion, child: hijo),
              ),
              child: Icon(
                oscuro ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey(oscuro),
                size: 19,
                color: colorIcono,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.iniciales, this.tamano = 36});

  final String iniciales;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.acento, shape: BoxShape.circle),
      child: Text(
        iniciales,
        style: TextStyle(
          fontSize: tamano * 0.34,
          fontWeight: FontWeight.w700,
          color: p.acentoTinta,
        ),
      ),
    );
  }
}

class _PieUsuario extends ConsumerWidget {
  const _PieUsuario({required this.usuario, required this.compacta});

  final Usuario? usuario;
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final avatar = _Avatar(iniciales: usuario?.iniciales ?? '?');

    if (compacta) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Esp.lg, top: Esp.sm),
        child: Column(
          children: [
            _BotonTema(colorIcono: p.sobreNegro2),
            const SizedBox(height: Esp.sm),
            Tooltip(message: usuario?.nombre ?? '', child: avatar),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(Esp.md),
      padding: const EdgeInsets.fromLTRB(Esp.sm, Esp.sm, Esp.xs, Esp.sm),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.lg),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: Esp.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario?.nombre ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.sobreNegro,
                  ),
                ),
                Text(
                  usuario?.esDesarrollador == true
                      ? 'Desarrollador'
                      : (usuario?.rol ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.sobreNegro2),
                ),
              ],
            ),
          ),
          _BotonTema(colorIcono: p.sobreNegro2),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(sesionProvider.notifier).salir(),
            icon: Icon(Icons.logout_rounded, size: 18, color: p.sobreNegro2),
          ),
        ],
      ),
    );
  }
}

class _EncabezadoPantalla extends StatelessWidget {
  const _EncabezadoPantalla({required this.seccion, required this.usuario});

  final Seccion seccion;
  final Usuario? usuario;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(Esp.xxl, Esp.md, Esp.xl, 0),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: Duracion.media,
              transitionBuilder: _transicionTitulo,
              layoutBuilder: _apilarIzquierda,
              child: Column(
                key: ValueKey(seccion.id),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tituloDe(seccion, usuario),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    seccion.subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.tinta3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Esp.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Esp.lg,
              vertical: Esp.sm + 2,
            ),
            decoration: ShapeDecoration(
              color: p.superficie,
              shape: StadiumBorder(side: BorderSide(color: p.borde)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 15, color: p.tinta2),
                const SizedBox(width: Esp.sm),
                Text(
                  Fmt.fecha(DateTime.now()),
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.tinta,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MOVIL
// ---------------------------------------------------------------------------

class _ShellMovil extends ConsumerWidget {
  const _ShellMovil({
    required this.seccion,
    required this.usuario,
    required this.child,
  });

  final Seccion seccion;
  final Usuario? usuario;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final principales = Secciones.barraInferior;
    final indice = principales.indexWhere((s) => s.id == seccion.id);
    // Cuando la seccion actual no esta en la barra (Gastos, Precios, Ventas,
    // Campanas...), se resalta "Mas". Sin esto quedaba iluminado Panel
    // estando en otra pantalla, que es peor que no resaltar nada.
    final indiceVisible = indice < 0 ? principales.length : indice;
    final esPanel = seccion.id == Secciones.panel.id;

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(
        toolbarHeight: 78,
        titleSpacing: Esp.lg + 4,
        backgroundColor: p.fondo,
        title: Row(
          children: [
            _Avatar(iniciales: usuario?.iniciales ?? '?', tamano: 44),
            const SizedBox(width: Esp.md),
            Expanded(
              child: AnimatedSwitcher(
                duration: Duracion.media,
                transitionBuilder: _transicionTitulo,
                layoutBuilder: _apilarIzquierda,
                child: Column(
                  key: ValueKey(seccion.id),
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      esPanel ? _tituloDe(seccion, usuario) : seccion.grupo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: p.tinta3),
                    ),
                    Text(
                      seccion.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: p.tinta,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          BotonCircular(
            icono: Icons.grid_view_rounded,
            tooltip: 'Más',
            onTap: () => _abrirMenu(context, ref),
          ),
          const SizedBox(width: Esp.lg),
        ],
        bottom: Config.modoDemo
            ? const PreferredSize(
                preferredSize: Size.fromHeight(28),
                child: CintaDemo(),
              )
            : null,
      ),
      body: child,
      // La barra es la del diseño y la que ya estaba: pastilla oscura
      // flotante, con el "+" de cargar en el medio y "Más" al final, que abre
      // el resto de las secciones y el cambio de tema.
      bottomNavigationBar: _BarraInferior(
        indiceActivo: indiceVisible < principales.length
            ? (indiceVisible >= _lugarDelMas
                  ? indiceVisible + 1
                  : indiceVisible)
            : principales.length + 1,
        items: [
          for (var i = 0; i < principales.length; i++) ...[
            if (i == _lugarDelMas) (Icons.add_circle_outline_rounded, 'Cargar'),
            (principales[i].icono, principales[i].etiqueta),
          ],
          (Icons.more_horiz_rounded, 'Más'),
        ],
        // El "+" no marca sección activa: es una acción, no un destino.
        indiceAccion: _lugarDelMas,
        onTap: (i) {
          if (i == _lugarDelMas) return _abrirCargar(context);
          final real = i > _lugarDelMas ? i - 1 : i;
          if (real >= principales.length) return _abrirMenu(context, ref);
          context.go(principales[real].ruta);
        },
      ),
    );
  }

  /// El "+" va en el medio de la barra, entre la segunda y la tercera
  /// sección: es donde cae el pulgar.
  static const _lugarDelMas = 2;

  /// La hoja del "+": todo lo que se carga a mano, en un solo lugar.
  ///
  /// Antes había que acordarse de en qué sección se daba de alta cada cosa.
  /// "¿Qué querés cargar?", como la pantalla del diseño, en la hoja que
  /// sube desde el "+" de la barra.
  void _abrirCargar(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 820),
      builder: (_) => _HojaCargar(shell: context),
    );
  }

  /// Lo que no entra en la barra inferior vive aca. Se usa una hoja y no un
  /// drawer lateral porque en un telefono grande la esquina superior izquierda
  /// no se alcanza con una mano.
  /// "Más opciones", como en el diseño.
  ///
  /// El cliente pidió que siga siendo la hoja que sube desde la barra —no una
  /// pantalla aparte—, así que la hoja tiene el mismo contenido que la
  /// pantalla del diseño: el perfil, los accesos de "Mi negocio", las
  /// preferencias de visualización, las herramientas y el cierre de sesión.
  void _abrirMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      // La paleta se lee del contexto de la hoja, no del shell: si se cambia
      // el tema con la hoja abierta, tiene que repintarse con el nuevo.
      builder: (ctx) => _HojaMasOpciones(shell: context),
    );
  }
}

class _BarraInferior extends StatelessWidget {
  const _BarraInferior({
    required this.indiceActivo,
    required this.items,
    required this.onTap,
    this.indiceAccion,
  });

  final int indiceActivo;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;

  /// El "+": va siempre en ámbar, se marque o no la sección.
  final int? indiceAccion;

  static const _anchoInactivo = 46.0;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(Esp.lg, 0, Esp.lg, Esp.md),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: p.negro,
          borderRadius: BorderRadius.circular(Curva.completo),
          border: Border.all(color: p.negroBorde),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, restricciones) {
            // Lo que sobra despues de los iconos inactivos y del relleno del
            // activo es el lugar para la etiqueta. En telefonos muy angostos
            // no entra y queda solo el icono.
            final libre =
                restricciones.maxWidth -
                (items.length - 1) * _anchoInactivo -
                (Esp.md * 2 + 22 + 6) -
                4;
            final anchoEtiqueta = libre.clamp(0.0, 110.0);

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < items.length; i++)
                  _ItemBarra(
                    icono: items[i].$1,
                    etiqueta: items[i].$2,
                    activo: i == indiceActivo,
                    accion: i == indiceAccion,
                    anchoEtiqueta: anchoEtiqueta,
                    onTap: () => onTap(i),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ItemBarra extends StatelessWidget {
  const _ItemBarra({
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.anchoEtiqueta,
    required this.onTap,
    this.accion = false,
  });

  final IconData icono;
  final String etiqueta;
  final bool activo;
  final double anchoEtiqueta;
  final VoidCallback onTap;

  /// El "+" de cargar: siempre visible, nunca "seleccionado".
  final bool accion;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final conEtiqueta = activo && !accion && anchoEtiqueta >= 36;

    return Semantics(
      label: etiqueta,
      selected: activo && !accion,
      button: true,
      child: AnimatedContainer(
        duration: Duracion.media,
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: accion
              ? p.acento
              : activo
              ? p.acento
              : p.negro.withValues(alpha: 0),
          shape: const StadiumBorder(),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            splashColor: p.acento.withValues(alpha: 0.2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _BarraInferior._anchoInactivo,
                minHeight: 50,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: conEtiqueta ? Esp.md : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icono,
                      size: accion ? 26 : 22,
                      color: activo || accion ? p.acentoTinta : p.sobreNegro2,
                    ),
                    AnimatedSize(
                      duration: Duracion.media,
                      curve: Curves.easeOutCubic,
                      child: conEtiqueta
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: anchoEtiqueta,
                                ),
                                child: Text(
                                  etiqueta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: p.acentoTinta,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A / A+ / A++: el selector de tamaño de letra del diseño.
class _BotonTamano extends StatelessWidget {
  const _BotonTamano({
    required this.tamano,
    required this.activo,
    required this.onTap,
  });

  final TamanoLetra tamano;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Curva.md),
      side: BorderSide(color: activo ? p.acento : p.borde, width: 1.5),
    );
    return Material(
      color: activo ? p.acento : p.superficie,
      shape: forma,
      child: InkWell(
        onTap: onTap,
        customBorder: forma,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Esp.md),
          child: Column(
            children: [
              Text(
                tamano.simbolo,
                style: TextStyle(
                  fontFamily: TemaApp.titulo,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: activo ? p.acentoTinta : p.tinta,
                ),
              ),
              Text(
                tamano.etiqueta,
                style: TextStyle(
                  fontSize: 14,
                  color: activo ? p.acentoTinta : p.tinta3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El contenido de "Más opciones": lo mismo que la pantalla del diseño, en
/// una hoja que sube desde la barra inferior.
class _HojaMasOpciones extends ConsumerWidget {
  const _HojaMasOpciones({required this.shell});

  /// El contexto del shell: la hoja se cierra antes de navegar, así que la
  /// navegación tiene que salir del contexto de abajo y no del de la hoja.
  final BuildContext shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final usuario = ref.watch(usuarioProvider);
    final agencia = ref.watch(miAgenciaProvider).value;
    final esDesarrollador = usuario?.esDesarrollador ?? false;

    void irA(String ruta) {
      Navigator.pop(context);
      shell.go(ruta);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Más opciones',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Configuración general de tu agencia y preferencias del '
                      'sistema',
                      style: TextStyle(fontSize: 15, color: p.tinta2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.sm),
              Pastilla(
                texto: Config.modoDemo ? 'Modo demo' : 'Conectado',
                color: Config.modoDemo ? p.observar : p.bien,
                lavado: Config.modoDemo ? p.observarLavado : p.bienLavado,
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),

          // --- Perfil ---------------------------------------------------
          Tarjeta(
            padding: const EdgeInsets.all(Esp.lg),
            child: Row(
              children: [
                _Avatar(iniciales: usuario?.iniciales ?? '?', tamano: 56),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Esp.sm,
                        runSpacing: Esp.xs,
                        children: [
                          Text(
                            usuario?.nombre ?? 'Usuario',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Pastilla(
                            texto: _rol(usuario?.rol, esDesarrollador),
                            color: p.tinta2,
                            lavado: p.superficieHundida,
                            conPunto: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _rol(usuario?.rol, esDesarrollador),
                          if (agencia?.nombre != null) agencia!.nombre,
                        ].join(' · '),
                        style: TextStyle(fontSize: 15, color: p.tinta2),
                      ),
                      if ((usuario?.email ?? '').isNotEmpty) ...[
                        const SizedBox(height: Esp.xs),
                        Row(
                          children: [
                            Icon(
                              Icons.mail_outline_rounded,
                              size: 18,
                              color: p.tinta3,
                            ),
                            const SizedBox(width: Esp.sm - 2),
                            Flexible(
                              child: Text(
                                usuario!.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: p.tinta3),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Esp.sm),
                OutlinedButton.icon(
                  onPressed: () => irA(Secciones.configuracion.ruta),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('Editar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          // --- Mi negocio -----------------------------------------------
          _TituloGrupo(titulo: 'MI NEGOCIO', nota: 'Gestión administrativa'),
          const SizedBox(height: Esp.sm),
          Tarjeta(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _FilaOpcion(
                  icono: Icons.insights_outlined,
                  titulo: 'Estadísticas',
                  descripcion:
                      'Cómo vienen las ventas, los tiempos y las ganancias',
                  onTap: () => irA(Secciones.estadisticas.ruta),
                ),
                _FilaOpcion(
                  icono: Icons.calculate_outlined,
                  titulo: 'Simulador de financiamiento',
                  descripcion: 'Calculá las cuotas para mostrarle al cliente',
                  onTap: () => irA(Secciones.simulador.ruta),
                ),
                _FilaOpcion(
                  icono: Icons.storefront_outlined,
                  titulo: 'Datos de la agencia',
                  descripcion:
                      'Umbrales, márgenes, redondeo y tipo de cambio de la '
                      'agencia',
                  onTap: () => irA(Secciones.configuracion.ruta),
                ),
                _FilaOpcion(
                  icono: Icons.manage_accounts_outlined,
                  titulo: 'Usuarios y permisos',
                  descripcion:
                      'Quién usa el sistema y qué puede ver de cada unidad',
                  pastilla: esDesarrollador ? null : 'Próximamente',
                  onTap: esDesarrollador
                      ? () => irA(Secciones.agencias.ruta)
                      : null,
                  ultima: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          // --- Carga de datos -------------------------------------------
          _TituloGrupo(titulo: 'CARGA DE DATOS', nota: 'Altas a mano'),
          const SizedBox(height: Esp.sm),
          Tarjeta(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final s in [
                  Secciones.vehiculos,
                  Secciones.gastos,
                  Secciones.precios,
                  Secciones.ventas,
                ])
                  _FilaOpcion(
                    icono: s.icono,
                    titulo: s.titulo,
                    descripcion: s.subtitulo,
                    onTap: () => irA(s.ruta),
                    ultima: s.id == Secciones.ventas.id,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          // --- Preferencias de visualización ----------------------------
          _TituloGrupo(
            titulo: 'PREFERENCIAS DE VISUALIZACIÓN',
            nota: 'Comodidad visual',
          ),
          const SizedBox(height: Esp.sm),
          Tarjeta(
            padding: const EdgeInsets.all(Esp.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    IconoEnCirculo(
                      icono: Icons.format_size_rounded,
                      tamano: 42,
                      color: p.tinta,
                      fondo: p.superficieHundida,
                    ),
                    const SizedBox(width: Esp.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tamaño de la letra',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Ajustá qué tan grande se lee todo',
                            style: TextStyle(fontSize: 14, color: p.tinta2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Esp.md),
                Row(
                  children: [
                    for (final t in TamanoLetra.values) ...[
                      Expanded(
                        child: _BotonTamano(
                          tamano: t,
                          activo: ref.watch(tamanoLetraProvider) == t,
                          onTap: () =>
                              ref.read(tamanoLetraProvider.notifier).poner(t),
                        ),
                      ),
                      if (t != TamanoLetra.values.last)
                        const SizedBox(width: Esp.sm),
                    ],
                  ],
                ),
                Divider(color: p.borde, height: Esp.xl),
                _FilaInterruptor(
                  icono: Icons.dark_mode_outlined,
                  titulo: 'Modo oscuro',
                  descripcion:
                      'Fondo oscuro para descansar la vista de noche o en '
                      'oficinas cerradas',
                  valor: ref.watch(temaProvider) == ThemeMode.dark,
                  onCambio: (_) => ref.read(temaProvider.notifier).alternar(),
                ),
                Divider(color: p.borde, height: Esp.xl),
                _FilaInterruptor(
                  icono: Icons.visibility_off_outlined,
                  titulo: 'Ocultar montos',
                  descripcion:
                      'Muestra la plata con asteriscos, para cuando el cliente '
                      've la pantalla',
                  valor: ref.watch(ocultarMontosProvider),
                  onCambio: (_) =>
                      ref.read(ocultarMontosProvider.notifier).alternar(),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          // --- Otros y asistencia ---------------------------------------
          _TituloGrupo(titulo: 'OTROS Y ASISTENCIA', nota: 'Herramientas'),
          const SizedBox(height: Esp.sm),
          Tarjeta(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _FilaOpcion(
                  icono: Icons.campaign_outlined,
                  titulo: 'Campañas comerciales',
                  descripcion:
                      'Mensajes a los clientes con promociones y nuevos '
                      'ingresos',
                  onTap: () => irA(Secciones.campanas.ruta),
                ),
                _FilaOpcion(
                  icono: Icons.support_agent_outlined,
                  titulo: 'Ayuda y soporte técnico',
                  descripcion:
                      'Escribinos por WhatsApp ante cualquier duda con el '
                      'sistema',
                  pastilla: 'Atención rápida',
                  onTap: () => launchUrl(
                    Uri.parse('https://wa.me/5492613000000'),
                    mode: LaunchMode.externalApplication,
                  ),
                  ultima: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: p.critico,
              side: BorderSide(color: p.critico, width: 1.6),
            ),
            onPressed: () {
              Navigator.pop(context);
              ref.read(sesionProvider.notifier).salir();
            },
            icon: const Icon(Icons.logout_rounded, size: 22),
            label: const Text('Cerrar sesión en este equipo'),
          ),
          const SizedBox(height: Esp.md),
          Center(
            child: Column(
              children: [
                Text(
                  '${agencia?.nombre ?? 'Mi Agencia'} · Sistema de gestión'
                  '${Config.version.isEmpty ? '' : ' v${Config.version}'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 16, color: p.tinta3),
                    const SizedBox(width: Esp.sm - 2),
                    Flexible(
                      child: Text(
                        Config.modoDemo
                            ? 'Datos de ejemplo, sin conexión a la base'
                            : 'Conexión cifrada de extremo a extremo',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: p.tinta3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _rol(String? rol, bool esDesarrollador) {
    if (esDesarrollador) return 'Desarrollador';
    return switch (rol) {
      'owner' => 'Titular',
      'admin' => 'Administrador',
      'vendedor' => 'Vendedor',
      _ => 'Equipo',
    };
  }
}

/// El encabezado de cada grupo: el rótulo a la izquierda y la aclaración
/// a la derecha, como en el diseño.
class _TituloGrupo extends StatelessWidget {
  const _TituloGrupo({required this.titulo, required this.nota});

  final String titulo, nota;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    // En un telefono el rotulo y la aclaracion no entran en la misma linea.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Esp.md,
      runSpacing: 2,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.labelSmall),
        Text(nota, style: TextStyle(fontSize: 14, color: p.tinta3)),
      ],
    );
  }
}

/// Una fila de "Más opciones": icono, título, descripción y la flecha.
class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    this.onTap,
    this.pastilla,
    this.ultima = false,
  });

  final IconData icono;
  final String titulo, descripcion;
  final VoidCallback? onTap;
  final String? pastilla;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Esp.lg),
            child: Row(
              children: [
                IconoEnCirculo(
                  icono: icono,
                  tamano: 42,
                  color: onTap == null ? p.tinta3 : p.acentoTexto,
                  fondo: onTap == null ? p.superficieHundida : p.acentoLavado,
                ),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        descripcion,
                        style: TextStyle(fontSize: 14, color: p.tinta2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Esp.sm),
                if (pastilla != null)
                  Flexible(
                    child: Pastilla(
                      texto: pastilla!,
                      color: p.tinta2,
                      lavado: p.superficieHundida,
                      conPunto: false,
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, size: 24, color: p.tinta3),
              ],
            ),
          ),
        ),
        if (!ultima)
          Divider(
            color: p.borde,
            height: 1,
            indent: Esp.lg + 42 + Esp.md,
            endIndent: Esp.lg,
          ),
      ],
    );
  }
}

/// Una preferencia con interruptor.
class _FilaInterruptor extends StatelessWidget {
  const _FilaInterruptor({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onCambio,
  });

  final IconData icono;
  final String titulo, descripcion;
  final bool valor;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      children: [
        IconoEnCirculo(
          icono: icono,
          tamano: 42,
          color: p.tinta,
          fondo: p.superficieHundida,
        ),
        const SizedBox(width: Esp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              Text(
                descripcion,
                style: TextStyle(fontSize: 14, color: p.tinta2),
              ),
            ],
          ),
        ),
        const SizedBox(width: Esp.sm),
        Switch(value: valor, onChanged: onCambio),
      ],
    );
  }
}

/// Lo que se puede dar de alta, y lo último que se cargó.
class _HojaCargar extends ConsumerWidget {
  const _HojaCargar({required this.shell});

  /// El contexto del shell: la hoja se cierra antes de navegar.
  final BuildContext shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;

    void irA(String ruta) {
      Navigator.pop(context);
      shell.go(ruta);
    }

    final grandes = [
      _OpcionCarga(
        icono: Icons.add_rounded,
        titulo: 'Un auto solo',
        descripcion: 'Completás los datos de a uno, paso a paso.',
        accion: 'Comenzar ahora',
        destacada: true,
        onTap: () => irA(Secciones.vehiculos.ruta),
      ),
      _OpcionCarga(
        icono: Icons.description_outlined,
        titulo: 'Varios autos de una vez',
        descripcion:
            'Subí una planilla, un PDF o la foto del cuaderno de inventario.',
        accion: 'Subir lista',
        destacada: true,
        onTap: () => irA('${Secciones.vehiculos.ruta}?importar=1'),
      ),
    ];

    final chicas = [
      _OpcionCarga(
        icono: Secciones.gastos.icono,
        titulo: 'Un gasto',
        descripcion: 'Reparación, lavadero, batería o trámites de gestoría.',
        accion: 'Anotar gasto',
        onTap: () => irA(Secciones.gastos.ruta),
      ),
      _OpcionCarga(
        icono: Secciones.ventas.icono,
        titulo: 'Una venta',
        descripcion: 'Registrar la entrega y cerrar la operación.',
        accion: 'Cerrar venta',
        onTap: () => irA(Secciones.ventas.ruta),
      ),
      _OpcionCarga(
        icono: Secciones.precios.icono,
        titulo: 'Cambiar precios',
        descripcion: 'Actualizar los valores de venta de las unidades.',
        accion: 'Actualizar',
        onTap: () => irA(Secciones.precios.ruta),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '¿Qué querés cargar?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Elegí una opción para continuar',
            style: TextStyle(fontSize: 15, color: p.tinta2),
          ),
          const SizedBox(height: Esp.lg),

          LayoutBuilder(
            builder: (context, r) {
              final enFila = r.maxWidth >= 640;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (enFila)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < grandes.length; i++) ...[
                          if (i > 0) const SizedBox(width: Esp.md),
                          Expanded(child: grandes[i]),
                        ],
                      ],
                    )
                  else
                    for (var i = 0; i < grandes.length; i++) ...[
                      if (i > 0) const SizedBox(height: Esp.md),
                      grandes[i],
                    ],
                  const SizedBox(height: Esp.md),
                  if (enFila)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < chicas.length; i++) ...[
                          if (i > 0) const SizedBox(width: Esp.md),
                          Expanded(child: chicas[i]),
                        ],
                      ],
                    )
                  else
                    for (var i = 0; i < chicas.length; i++) ...[
                      if (i > 0) const SizedBox(height: Esp.md),
                      chicas[i],
                    ],
                ],
              );
            },
          ),

          const SizedBox(height: Esp.lg),
          _UltimoQueCargaste(onIr: irA),
        ],
      ),
    );
  }
}

/// Una de las opciones de "¿Qué querés cargar?".
class _OpcionCarga extends StatelessWidget {
  const _OpcionCarga({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.accion,
    required this.onTap,
    this.destacada = false,
  });

  final IconData icono;
  final String titulo, descripcion, accion;
  final VoidCallback onTap;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconoEnCirculo(
            icono: icono,
            tamano: destacada ? 52 : 44,
            color: destacada ? p.acentoTinta : p.acentoTexto,
            fondo: destacada ? p.acento : p.acentoLavado,
          ),
          const SizedBox(height: Esp.md),
          Text(titulo, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            descripcion,
            style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.35),
          ),
          const SizedBox(height: Esp.md),
          Align(
            alignment: Alignment.centerLeft,
            child: destacada
                ? FilledButton.icon(
                    onPressed: onTap,
                    icon: Text(accion),
                    label: const Icon(Icons.arrow_forward_rounded, size: 20),
                  )
                : TextButton.icon(
                    onPressed: onTap,
                    icon: Text(accion),
                    label: const Icon(Icons.arrow_forward_rounded, size: 20),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Lo último que cargaste": la actividad reciente, con el atajo para
/// corregir lo que haya salido mal.
class _UltimoQueCargaste extends ConsumerWidget {
  const _UltimoQueCargaste({required this.onIr});

  final void Function(String ruta) onIr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final inventario = ref.watch(inventarioProvider).value ?? const [];
    final gastos = ref.watch(gastosProvider).value ?? const [];
    final ventas = ref.watch(ventasProvider).value ?? const [];

    // Una sola lista con lo último de cada cosa, ordenada por fecha.
    final movimientos =
        <({DateTime cuando, IconData icono, String texto, String ruta})>[
          for (final v in inventario.take(20))
            (
              cuando: v.fechaIngreso,
              icono: Icons.directions_car_filled_rounded,
              texto: '${v.titulo}${v.patente == null ? '' : ' · ${v.patente}'}',
              ruta: '/inventario/${v.id}',
            ),
          for (final g in gastos.take(20))
            (
              cuando: g.fecha,
              icono: Icons.receipt_long_outlined,
              texto:
                  'Gasto: ${g.descripcion?.isNotEmpty == true ? g.descripcion! : g.categoria.etiqueta}'
                  ' · ${Fmt.pesos(g.importe)}',
              ruta: Secciones.gastos.ruta,
            ),
          for (final v in ventas.take(20))
            (
              cuando: v.fechaVenta,
              icono: Icons.sell_outlined,
              texto:
                  'Venta: ${v.vehiculoTitulo ?? v.vehiculoCodigo ?? 'una unidad'}',
              ruta: Secciones.ventas.ruta,
            ),
        ]..sort((a, b) => b.cuando.compareTo(a.cuando));

    if (movimientos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 20, color: p.tinta2),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Text(
                'Lo último que cargaste',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Pastilla(
              texto: 'Actividad reciente',
              color: p.tinta2,
              lavado: p.superficieHundida,
              conPunto: false,
            ),
          ],
        ),
        const SizedBox(height: Esp.sm),
        Tarjeta(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final m in movimientos.take(4))
                Padding(
                  padding: const EdgeInsets.all(Esp.md),
                  child: Row(
                    children: [
                      IconoEnCirculo(
                        icono: m.icono,
                        tamano: 40,
                        color: p.tinta2,
                        fondo: p.superficieHundida,
                      ),
                      const SizedBox(width: Esp.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.texto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              Fmt.fecha(m.cuando),
                              style: TextStyle(fontSize: 14, color: p.tinta3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Esp.sm),
                      OutlinedButton(
                        onPressed: () => onIr(m.ruta),
                        child: const Text('Corregir'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
