import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
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
///   < 900 px  -> barra inferior (al alcance del pulgar) + hoja "Más"
///   900-1280  -> barra lateral de iconos
///   > 1280 px -> barra lateral completa con etiquetas y grupos
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
                _BarraLateral(
                  seccionActual: seccion,
                  usuario: usuario,
                  compacta: compacta,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _EncabezadoPantalla(seccion: seccion),
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
              compacta ? 0 : Esp.md,
              Esp.lg,
              Esp.md,
              Esp.sm,
            ),
            child: compacta
                ? Divider(color: p.borde, height: 1)
                : EtiquetaSeccion(s.grupo),
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

    return Container(
      width: compacta ? 68 : 244,
      decoration: BoxDecoration(
        color: p.superficie,
        border: Border(right: BorderSide(color: p.borde)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Marca(compacta: compacta, agencia: usuario?.agenciaNombre),
          Divider(color: p.borde, height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: compacta ? Esp.md : Esp.sm,
                vertical: Esp.sm,
              ),
              children: items,
            ),
          ),
          Divider(color: p.borde, height: 1),
          _PieUsuario(usuario: usuario, compacta: compacta),
        ],
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
    final logo = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p.acento, p.acento.withValues(alpha: 0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.directions_car_filled, size: 18, color: p.acentoTinta),
    );

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: compacta ? Esp.lg : Esp.lg),
      alignment: compacta ? Alignment.center : Alignment.centerLeft,
      child: compacta
          ? logo
          : Row(
              children: [
                logo,
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mi Agencia',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: p.tinta,
                          height: 1.2,
                        ),
                      ),
                      if (agencia != null)
                        Text(
                          agencia!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: p.tinta3),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _EnlaceNav extends StatelessWidget {
  const _EnlaceNav({
    required this.seccion,
    required this.activo,
    required this.compacta,
  });

  final Seccion seccion;
  final bool activo;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final color = activo ? p.acento : p.tinta2;

    final contenido = compacta
        ? Center(child: Icon(seccion.icono, size: 20, color: color))
        : Row(
            children: [
              Icon(seccion.icono, size: 19, color: color),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  seccion.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                    color: activo ? p.tinta : p.tinta2,
                  ),
                ),
              ),
            ],
          );

    final boton = Material(
      color: activo ? p.acentoLavado : Colors.transparent,
      borderRadius: BorderRadius.circular(Curva.md),
      child: InkWell(
        onTap: () => context.go(seccion.ruta),
        borderRadius: BorderRadius.circular(Curva.md),
        hoverColor: p.superficieHover,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compacta ? Esp.sm : Esp.md,
            vertical: Esp.md - 1,
          ),
          child: contenido,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: compacta
          ? Tooltip(message: seccion.etiqueta, child: boton)
          : boton,
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
    final modo = ref.watch(temaProvider);

    final avatar = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: p.acentoLavado,
        borderRadius: BorderRadius.circular(Curva.sm),
        border: Border.all(color: p.acento.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: Text(
        usuario?.iniciales ?? '?',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: p.acento,
        ),
      ),
    );

    if (compacta) {
      return Padding(
        padding: const EdgeInsets.all(Esp.md),
        child: Column(
          children: [
            IconButton(
              tooltip: modo == ThemeMode.dark ? 'Tema claro' : 'Tema oscuro',
              onPressed: () => ref.read(temaProvider.notifier).alternar(),
              icon: Icon(
                modo == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 18,
              ),
            ),
            const SizedBox(height: Esp.sm),
            Tooltip(message: usuario?.nombre ?? '', child: avatar),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(Esp.md),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: Esp.md),
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
                    color: p.tinta,
                  ),
                ),
                Text(
                  usuario?.esDesarrollador == true
                      ? 'Desarrollador'
                      : (usuario?.rol ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.tinta3),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: modo == ThemeMode.dark ? 'Tema claro' : 'Tema oscuro',
            onPressed: () => ref.read(temaProvider.notifier).alternar(),
            icon: Icon(
              modo == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(sesionProvider.notifier).salir(),
            icon: const Icon(Icons.logout, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EncabezadoPantalla extends StatelessWidget {
  const _EncabezadoPantalla({required this.seccion});

  final Seccion seccion;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: Esp.xl),
      decoration: BoxDecoration(
        color: p.fondo,
        border: Border(bottom: BorderSide(color: p.borde)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seccion.titulo,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  seccion.subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.tinta3),
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Esp.lg,
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              seccion.titulo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              seccion.subtitulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: p.tinta3),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _abrirMenu(context, ref),
            icon: const Icon(Icons.more_horiz),
            tooltip: 'Más',
          ),
          const SizedBox(width: Esp.sm),
        ],
        bottom: Config.modoDemo
            ? const PreferredSize(
                preferredSize: Size.fromHeight(28),
                child: CintaDemo(),
              )
            : null,
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.superficie,
          border: Border(top: BorderSide(color: p.borde)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: p.acentoLavado,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (estados) => TextStyle(
                fontSize: 11,
                fontWeight: estados.contains(WidgetState.selected)
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: estados.contains(WidgetState.selected)
                    ? p.tinta
                    : p.tinta3,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (estados) => IconThemeData(
                size: 21,
                color: estados.contains(WidgetState.selected)
                    ? p.acento
                    : p.tinta3,
              ),
            ),
          ),
          child: NavigationBar(
            height: 62,
            elevation: 0,
            selectedIndex: indiceVisible,
            onDestinationSelected: (i) => i < principales.length
                ? context.go(principales[i].ruta)
                : _abrirMenu(context, ref),
            destinations: [
              for (final s in principales)
                NavigationDestination(icon: Icon(s.icono), label: s.etiqueta),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: 'Más',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que no entra en la barra inferior vive aca. Se usa una hoja y no un
  /// drawer lateral porque en un telefono grande la esquina superior izquierda
  /// no se alcanza con una mano.
  void _abrirMenu(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final resto = Secciones.visibles(
      esDesarrollador: ref.read(usuarioProvider)?.esDesarrollador ?? false,
    ).where((s) => !s.enBarraInferior).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.superficieElevada,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Curva.lg)),
      ),
      // isScrollControlled + el envoltorio scrolleable: con la cuenta de
      // desarrollador el menu tiene mas entradas de las que entran en media
      // pantalla, y sin esto la hoja desborda en vez de dejar scrollear.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in resto)
                ListTile(
                  leading: Icon(s.icono, size: 20, color: p.tinta2),
                  title: Text(
                    s.etiqueta,
                    style: const TextStyle(fontSize: 14.5),
                  ),
                  subtitle: Text(
                    s.subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: p.tinta3),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(s.ruta);
                  },
                ),
              Divider(color: p.borde, height: Esp.lg),
              Consumer(
                builder: (_, r, _) {
                  final modo = r.watch(temaProvider);
                  return ListTile(
                    leading: Icon(
                      modo == ThemeMode.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 20,
                      color: p.tinta2,
                    ),
                    title: Text(
                      modo == ThemeMode.dark ? 'Tema claro' : 'Tema oscuro',
                      style: const TextStyle(fontSize: 14.5),
                    ),
                    onTap: () => r.read(temaProvider.notifier).alternar(),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, size: 20, color: p.critico),
                title: Text(
                  'Cerrar sesión',
                  style: TextStyle(fontSize: 14.5, color: p.critico),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(sesionProvider.notifier).salir();
                },
              ),
              const SizedBox(height: Esp.sm),
            ],
          ),
        ),
      ),
    );
  }
}
