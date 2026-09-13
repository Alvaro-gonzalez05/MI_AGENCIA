import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/control_tema.dart';
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
                  padding: const EdgeInsets.fromLTRB(
                    Esp.md,
                    Esp.md,
                    0,
                    Esp.md,
                  ),
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

Widget _apilarIzquierda(Widget? actual, List<Widget> previos) => Stack(
  alignment: Alignment.centerLeft,
  children: [...previos, ?actual],
);

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
      child: Icon(
        Icons.directions_car_filled_rounded,
        size: tamano * 0.52,
        color: p.acentoTinta,
      ),
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
                              text: 'Mi',
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
                          style: TextStyle(
                            fontSize: 11.5,
                            color: p.sobreNegro2,
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
                    fontSize: 13.5,
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
                    fontSize: 13,
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
                  style: TextStyle(fontSize: 11.5, color: p.sobreNegro2),
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
                    style: TextStyle(fontSize: 13, color: p.tinta3),
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
                    fontSize: 12.5,
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
                      style: TextStyle(fontSize: 12.5, color: p.tinta3),
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
      bottomNavigationBar: _BarraInferior(
        indiceActivo: indiceVisible,
        items: [
          for (final s in principales) (s.icono, s.etiqueta),
          (Icons.more_horiz_rounded, 'Más'),
        ],
        onTap: (i) => i < principales.length
            ? context.go(principales[i].ruta)
            : _abrirMenu(context, ref),
      ),
    );
  }

  /// Lo que no entra en la barra inferior vive aca. Se usa una hoja y no un
  /// drawer lateral porque en un telefono grande la esquina superior izquierda
  /// no se alcanza con una mano.
  void _abrirMenu(BuildContext context, WidgetRef ref) {
    final resto = Secciones.visibles(
      esDesarrollador: ref.read(usuarioProvider)?.esDesarrollador ?? false,
    ).where((s) => !s.enBarraInferior).toList();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // isScrollControlled + el envoltorio scrolleable: con la cuenta de
      // desarrollador el menu tiene mas entradas de las que entran en media
      // pantalla, y sin esto la hoja desborda en vez de dejar scrollear.
      isScrollControlled: true,
      // La paleta se lee del contexto de la hoja, no del shell: si se cambia
      // el tema con la hoja abierta, tiene que repintarse con el nuevo.
      builder: (ctx) {
        final p = ctx.paleta;
        return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Más secciones',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: Esp.lg),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Esp.md,
                crossAxisSpacing: Esp.md,
                childAspectRatio: 0.98,
                children: [
                  for (var i = 0; i < resto.length; i++)
                    Aparecer(
                      indice: i,
                      child: _MosaicoSeccion(
                        seccion: resto[i],
                        activa: resto[i].id == seccion.id,
                        onTap: () {
                          Navigator.pop(ctx);
                          context.go(resto[i].ruta);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Esp.xl),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: Esp.lg,
                        right: Esp.xs,
                      ),
                      decoration: ShapeDecoration(
                        color: p.superficieHundida,
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tema',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: p.tinta,
                              ),
                            ),
                          ),
                          _BotonTema(colorIcono: p.acentoTexto),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Esp.md),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.criticoLavado,
                      foregroundColor: p.critico,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Esp.lg + 2,
                        vertical: Esp.md,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(sesionProvider.notifier).salir();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Salir'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      },
    );
  }
}

class _MosaicoSeccion extends StatelessWidget {
  const _MosaicoSeccion({
    required this.seccion,
    required this.activa,
    required this.onTap,
  });

  final Seccion seccion;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Material(
      color: activa ? p.acento : p.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Curva.lg),
        child: Padding(
          padding: const EdgeInsets.all(Esp.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconoEnCirculo(
                icono: seccion.icono,
                tamano: 44,
                color: activa ? p.acento : p.tinta,
                fondo: activa ? p.acentoTinta : p.superficie,
              ),
              const SizedBox(height: Esp.sm),
              Text(
                seccion.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: activa ? p.acentoTinta : p.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra inferior flotante: una pildora negra donde el destino activo se
/// expande en amarillo y muestra su nombre.
class _BarraInferior extends StatelessWidget {
  const _BarraInferior({
    required this.indiceActivo,
    required this.items,
    required this.onTap,
  });

  final int indiceActivo;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;

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
  });

  final IconData icono;
  final String etiqueta;
  final bool activo;
  final double anchoEtiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final conEtiqueta = activo && anchoEtiqueta >= 36;

    return Semantics(
      label: etiqueta,
      selected: activo,
      button: true,
      child: AnimatedContainer(
        duration: Duracion.media,
        curve: Curves.easeOutCubic,
        decoration: ShapeDecoration(
          color: activo ? p.acento : p.negro.withValues(alpha: 0),
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
                      size: 22,
                      color: activo ? p.acentoTinta : p.sobreNegro2,
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
                                    fontSize: 12.5,
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
