import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../dominio/equipo.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';
import 'alta_empleado.dart';
import 'ficha_miembro.dart';
import 'nueva_zona.dart';

/// La pizarra de usuarios: quién trabaja en la agencia, en qué área y qué
/// puede ver cada uno.
///
/// Es un tablero y no una tabla porque la pregunta que se hace el dueño no
/// es "¿cuántos usuarios tengo?" sino "¿quién está en ventas y quién ve la
/// plata?". Eso se contesta mirando, no leyendo.
///
/// En escritorio las zonas se arrastran por el tablero y las líneas las
/// siguen; en un celular eso no se puede usar, así que las mismas zonas se
/// apilan una debajo de la otra.
class PantallaEquipo extends ConsumerWidget {
  const PantallaEquipo({super.key});

  /// El tablero tiene medidas fijas para que las líneas se puedan calcular
  /// sin medir widgets: con las posiciones y la cantidad de gente alcanza.
  static const anchoLienzo = 900.0;
  static const altoLienzo = 600.0;
  static const anchoZona = 196.0;
  static const altoCabecera = 42.0;
  static const altoFila = 46.0;
  static const altoPie = 36.0;
  static const anchoDueno = 196.0;
  static const altoDueno = 58.0;

  static double altoDe(int cuantos) =>
      altoCabecera + cuantos * altoFila + altoPie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipo = ref.watch(equipoProvider);
    final zonas = ref.watch(zonasProvider);
    final puedeAdministrar = ref.watch(permisosProvider).puedeAdministrar;

    if (equipo.isLoading || zonas.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = equipo.error ?? zonas.error;
    if (error != null) {
      return EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar el equipo',
        descripcion: '$error',
      );
    }

    final gente = equipo.value ?? const <Miembro>[];
    final areas = zonas.value ?? const <Zona>[];
    final enPizarra = MediaQuery.sizeOf(context).width >= Corte.escritorio;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Barra(
            gente: gente,
            areas: areas,
            puedeAdministrar: puedeAdministrar,
          ),
          Expanded(
            child: enPizarra
                ? _Pizarra(
                    gente: gente,
                    areas: areas,
                    puedeAdministrar: puedeAdministrar,
                  )
                : _Apilada(
                    gente: gente,
                    areas: areas,
                    puedeAdministrar: puedeAdministrar,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Barra extends ConsumerWidget {
  const _Barra({
    required this.gente,
    required this.areas,
    required this.puedeAdministrar,
  });

  final List<Miembro> gente;
  final List<Zona> areas;
  final bool puedeAdministrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final activos = gente.where((m) => m.activa).length;
    final conPlata = gente.where((m) => m.activa && m.vePlata).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.sm, Esp.xl, Esp.md),
      child: Wrap(
        spacing: Esp.md,
        runSpacing: Esp.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$activos ${activos == 1 ? 'persona' : 'personas'} · '
            '$conPlata ${conPlata == 1 ? 've' : 'ven'} la plata · '
            '${areas.length} ${areas.length == 1 ? 'zona' : 'zonas'}',
            style: TextStyle(fontSize: 14, color: p.tinta2),
          ),
          if (puedeAdministrar) ...[
            OutlinedButton.icon(
              onPressed: () => HojaNuevaZona.abrir(context, ref),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Nueva zona'),
            ),
            FilledButton.icon(
              onPressed: () => HojaAltaEmpleado.abrir(context, ref),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Nuevo empleado'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// El tablero
// ---------------------------------------------------------------------------

class _Pizarra extends ConsumerStatefulWidget {
  const _Pizarra({
    required this.gente,
    required this.areas,
    required this.puedeAdministrar,
  });

  final List<Miembro> gente;
  final List<Zona> areas;
  final bool puedeAdministrar;

  @override
  ConsumerState<_Pizarra> createState() => _PizarraState();
}

class _PizarraState extends ConsumerState<_Pizarra> {
  /// Mientras se arrastra, la posición vive acá: guardarla en la base en
  /// cada cuadro sería una escritura por pixel.
  final Map<String, Offset> _movidas = {};
  Offset? _dueno;

  Offset _posDe(Zona z) => _movidas[z.id] ?? Offset(z.x, z.y);

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final dueno = widget.gente
        .where((m) => m.rol == RolMembresia.owner)
        .firstOrNull;
    final sinZona = widget.gente
        .where((m) => m.zonaId == null && m.rol != RolMembresia.owner)
        .toList();

    final posDueno =
        _dueno ??
        Offset(
          ref.watch(posicionDuenoProvider).value?.$1 ?? 352,
          ref.watch(posicionDuenoProvider).value?.$2 ?? 250,
        );

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
          child: SizedBox(
            width: PantallaEquipo.anchoLienzo,
            height:
                PantallaEquipo.altoLienzo + (sinZona.isEmpty ? 0 : Esp.xxxl),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Las líneas van primero: quedan debajo de las tarjetas, que
                // tienen fondo sólido, así que no las cruzan.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Lineas(
                      desde:
                          posDueno +
                          const Offset(
                            PantallaEquipo.anchoDueno / 2,
                            PantallaEquipo.altoDueno / 2,
                          ),
                      hasta: [
                        for (final z in widget.areas)
                          _posDe(z) +
                              Offset(
                                PantallaEquipo.anchoZona / 2,
                                PantallaEquipo.altoDe(
                                      widget.gente
                                          .where((m) => m.zonaId == z.id)
                                          .length,
                                    ) /
                                    2,
                              ),
                      ],
                      color: p.borde,
                    ),
                  ),
                ),

                for (final z in widget.areas)
                  Positioned(
                    left: _posDe(z).dx,
                    top: _posDe(z).dy,
                    child: _TarjetaZona(
                      zona: z,
                      gente: widget.gente
                          .where((m) => m.zonaId == z.id)
                          .toList(),
                      puedeAdministrar: widget.puedeAdministrar,
                      onMover: widget.puedeAdministrar
                          ? (delta) => setState(() {
                              final actual = _posDe(z);
                              _movidas[z.id] = Offset(
                                (actual.dx + delta.dx).clamp(
                                  0,
                                  PantallaEquipo.anchoLienzo -
                                      PantallaEquipo.anchoZona,
                                ),
                                (actual.dy + delta.dy).clamp(
                                  0,
                                  PantallaEquipo.altoLienzo - 80,
                                ),
                              );
                            })
                          : null,
                      onSoltar: () => _guardarZona(z),
                    ),
                  ),

                if (dueno != null)
                  Positioned(
                    left: posDueno.dx,
                    top: posDueno.dy,
                    child: _TarjetaDueno(
                      dueno: dueno,
                      puedeMover: widget.puedeAdministrar,
                      onMover: (delta) => setState(() {
                        _dueno = Offset(
                          (posDueno.dx + delta.dx).clamp(
                            0,
                            PantallaEquipo.anchoLienzo -
                                PantallaEquipo.anchoDueno,
                          ),
                          (posDueno.dy + delta.dy).clamp(
                            0,
                            PantallaEquipo.altoLienzo -
                                PantallaEquipo.altoDueno,
                          ),
                        );
                      }),
                      onSoltar: () => ref
                          .read(repositorioProvider)
                          .guardarPosicionDueno(posDueno.dx, posDueno.dy),
                    ),
                  ),

                if (sinZona.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: PantallaEquipo.altoLienzo,
                    child: _SinZona(
                      gente: sinZona,
                      puedeAdministrar: widget.puedeAdministrar,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardarZona(Zona z) async {
    final pos = _movidas[z.id];
    if (pos == null) return;
    await ref
        .read(repositorioProvider)
        .guardarZona(z.copiar(x: pos.dx, y: pos.dy));
    ref.invalidate(zonasProvider);
  }
}

/// Las líneas del dueño a cada zona. Se dibujan y no se arman con widgets
/// porque son una por zona y cambian en cada cuadro del arrastre.
class _Lineas extends CustomPainter {
  _Lineas({required this.desde, required this.hasta, required this.color});

  final Offset desde;
  final List<Offset> hasta;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lapiz = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final h in hasta) {
      canvas.drawLine(desde, h, lapiz);
    }
  }

  @override
  bool shouldRepaint(_Lineas viejo) =>
      viejo.desde != desde || viejo.hasta.length != hasta.length;
}

class _TarjetaDueno extends StatelessWidget {
  const _TarjetaDueno({
    required this.dueno,
    required this.puedeMover,
    required this.onMover,
    required this.onSoltar,
  });

  final Miembro dueno;
  final bool puedeMover;
  final void Function(Offset) onMover;
  final VoidCallback onSoltar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return GestureDetector(
      onPanUpdate: puedeMover ? (d) => onMover(d.delta) : null,
      onPanEnd: puedeMover ? (_) => onSoltar() : null,
      onTap: () => HojaMiembro.abrir(context, dueno),
      child: MouseRegion(
        cursor: puedeMover ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: Container(
          width: PantallaEquipo.anchoDueno,
          height: PantallaEquipo.altoDueno,
          padding: const EdgeInsets.symmetric(horizontal: Esp.md),
          decoration: BoxDecoration(
            color: p.negro,
            borderRadius: BorderRadius.circular(Curva.md),
            border: Border.all(color: p.negroBorde),
          ),
          child: Row(
            children: [
              IconoEnCirculo(
                icono: Icons.workspace_premium_outlined,
                tamano: 30,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dueno.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.sobreNegro,
                      ),
                    ),
                    Text(
                      'Dueño · ve todo',
                      style: TextStyle(fontSize: 12, color: p.acento),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaZona extends ConsumerWidget {
  const _TarjetaZona({
    required this.zona,
    required this.gente,
    required this.puedeAdministrar,
    required this.onMover,
    required this.onSoltar,
  });

  final Zona zona;
  final List<Miembro> gente;
  final bool puedeAdministrar;
  final void Function(Offset)? onMover;
  final VoidCallback onSoltar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;

    return DragTarget<Miembro>(
      onWillAcceptWithDetails: (d) =>
          puedeAdministrar && d.data.zonaId != zona.id,
      onAcceptWithDetails: (d) async {
        await ref
            .read(repositorioProvider)
            .moverAZona(d.data.membresiaId, zona.id);
        ref.invalidate(equipoProvider);
      },
      builder: (context, encima, _) => AnimatedContainer(
        duration: Duracion.rapida,
        width: PantallaEquipo.anchoZona,
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: BorderRadius.circular(Curva.lg),
          border: Border.all(
            color: encima.isNotEmpty ? p.acentoTinta : p.borde,
            width: encima.isNotEmpty ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onPanUpdate: onMover == null ? null : (d) => onMover!(d.delta),
              onPanEnd: onMover == null ? null : (_) => onSoltar(),
              child: MouseRegion(
                cursor: onMover == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.move,
                child: Container(
                  height: PantallaEquipo.altoCabecera,
                  padding: const EdgeInsets.symmetric(horizontal: Esp.md),
                  child: Row(
                    children: [
                      Icon(zona.dibujo, size: 17, color: p.tinta3),
                      const SizedBox(width: Esp.sm - 2),
                      Expanded(
                        child: Text(
                          zona.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.tinta),
                        ),
                      ),
                      Text(
                        '${gente.length}',
                        style: TextStyle(fontSize: 13, color: p.tinta3),
                      ),
                      if (puedeAdministrar)
                        _BotonChico(
                          icono: Icons.delete_outline_rounded,
                          tooltip: 'Eliminar la zona',
                          onTap: () => _borrar(context, ref),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            for (final m in gente)
              _TarjetaPersona(miembro: m, arrastrable: puedeAdministrar),
            Padding(
              padding: const EdgeInsets.fromLTRB(Esp.sm, 2, Esp.sm, Esp.sm),
              child: Pulsable(
                onTap: puedeAdministrar
                    ? () => HojaAltaEmpleado.abrir(context, ref, zona: zona)
                    : null,
                child: BordePunteado(
                  radio: Curva.md,
                  color: p.borde,
                  child: SizedBox(
                    height: 26,
                    child: Center(
                      child: Text(
                        'sumar',
                        style: TextStyle(fontSize: 12, color: p.tinta3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final ok = await confirmarAccion(
      context,
      titulo: 'Eliminar ${zona.nombre}',
      descripcion: gente.isEmpty
          ? 'La zona desaparece de la pizarra.'
          : '${gente.length} ${gente.length == 1 ? 'persona queda' : 'personas quedan'} '
                'sin zona. Siguen entrando igual: lo único que se borra es '
                'el área.',
      confirmar: 'Eliminar',
      icono: Icons.delete_outline_rounded,
      peligrosa: true,
    );
    if (!ok) return;
    await ref.read(repositorioProvider).borrarZona(zona.id);
    ref.invalidate(zonasProvider);
    ref.invalidate(equipoProvider);
  }
}

/// Una persona en la pizarra. Se puede arrastrar a otra zona y se abre al
/// tocarla.
class _TarjetaPersona extends StatelessWidget {
  const _TarjetaPersona({required this.miembro, required this.arrastrable});

  final Miembro miembro;
  final bool arrastrable;

  @override
  Widget build(BuildContext context) {
    final cuerpo = _CuerpoPersona(miembro: miembro);
    if (!arrastrable) {
      return Pulsable(
        onTap: () => HojaMiembro.abrir(context, miembro),
        child: cuerpo,
      );
    }
    return Draggable<Miembro>(
      data: miembro,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.rotate(
        angle: -0.03,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: PantallaEquipo.anchoZona - Esp.md,
            child: _CuerpoPersona(miembro: miembro, levantada: true),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cuerpo),
      child: Pulsable(
        onTap: () => HojaMiembro.abrir(context, miembro),
        child: cuerpo,
      ),
    );
  }
}

class _CuerpoPersona extends StatelessWidget {
  const _CuerpoPersona({required this.miembro, this.levantada = false});

  final Miembro miembro;
  final bool levantada;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final m = miembro;
    return Container(
      height: PantallaEquipo.altoFila - 6,
      margin: const EdgeInsets.fromLTRB(Esp.sm, 0, Esp.sm, 6),
      padding: const EdgeInsets.symmetric(horizontal: Esp.sm),
      decoration: BoxDecoration(
        color: m.activa ? p.superficieHundida : p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(
          color: levantada ? p.acentoTinta : p.borde,
          width: levantada ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(m.icono, size: 17, color: m.vePlata ? p.acentoTexto : p.tinta3),
          const SizedBox(width: Esp.sm - 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: m.activa ? p.tinta : p.tinta3,
                    decoration: m.activa ? null : TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  m.activa ? m.rol.etiqueta : 'Sin acceso',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.tinta3),
                ),
              ],
            ),
          ),
          if (m.vePlata && m.activa)
            Tooltip(
              message: 'Ve el precio de compra y la ganancia',
              child: Icon(
                Icons.monetization_on_outlined,
                size: 15,
                color: p.acentoTexto,
              ),
            ),
        ],
      ),
    );
  }
}

/// La bandeja de los que no están en ninguna zona: los recién dados de alta
/// y los que quedaron sueltos al borrar un área.
class _SinZona extends ConsumerWidget {
  const _SinZona({required this.gente, required this.puedeAdministrar});

  final List<Miembro> gente;
  final bool puedeAdministrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    return DragTarget<Miembro>(
      onWillAcceptWithDetails: (d) => puedeAdministrar && d.data.zonaId != null,
      onAcceptWithDetails: (d) async {
        await ref
            .read(repositorioProvider)
            .moverAZona(d.data.membresiaId, null);
        ref.invalidate(equipoProvider);
      },
      builder: (context, encima, _) => AnimatedContainer(
        duration: Duracion.rapida,
        padding: const EdgeInsets.all(Esp.sm),
        decoration: BoxDecoration(
          color: p.superficieHundida,
          borderRadius: BorderRadius.circular(Curva.lg),
          border: Border.all(
            color: encima.isNotEmpty ? p.acentoTinta : p.borde,
            style: encima.isNotEmpty ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Esp.sm, 2, 0, Esp.sm - 2),
              child: Row(
                children: [
                  Icon(Icons.person_off_outlined, size: 15, color: p.tinta3),
                  const SizedBox(width: Esp.sm - 2),
                  Text(
                    'Sin zona',
                    style: TextStyle(fontSize: 12, color: p.tinta2),
                  ),
                ],
              ),
            ),
            Wrap(
              children: [
                for (final m in gente)
                  SizedBox(
                    width: PantallaEquipo.anchoZona,
                    child: _TarjetaPersona(
                      miembro: m,
                      arrastrable: puedeAdministrar,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// La misma pizarra, apilada (celular)
// ---------------------------------------------------------------------------

class _Apilada extends ConsumerWidget {
  const _Apilada({
    required this.gente,
    required this.areas,
    required this.puedeAdministrar,
  });

  final List<Miembro> gente;
  final List<Zona> areas;
  final bool puedeAdministrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final dueno = gente.where((m) => m.rol == RolMembresia.owner).firstOrNull;
    final sinZona = gente
        .where((m) => m.zonaId == null && m.rol != RolMembresia.owner)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Esp.lg + 4, 0, Esp.lg + 4, Esp.xxl),
      children: [
        if (dueno != null) ...[
          Pulsable(
            onTap: () => HojaMiembro.abrir(context, dueno),
            child: Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.negro,
                borderRadius: BorderRadius.circular(Curva.lg),
              ),
              child: Row(
                children: [
                  IconoEnCirculo(
                    icono: Icons.workspace_premium_outlined,
                    tamano: 34,
                    color: p.acentoTinta,
                    fondo: p.acento,
                  ),
                  const SizedBox(width: Esp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dueno.nombre,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: p.sobreNegro,
                          ),
                        ),
                        Text(
                          'Dueño · ve todo',
                          style: TextStyle(fontSize: 13, color: p.acento),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Esp.md),
        ],
        for (var i = 0; i < areas.length; i++) ...[
          Aparecer(
            indice: i,
            child: _ZonaApilada(
              zona: areas[i],
              gente: gente.where((m) => m.zonaId == areas[i].id).toList(),
              puedeAdministrar: puedeAdministrar,
            ),
          ),
          const SizedBox(height: Esp.sm),
        ],
        if (sinZona.isNotEmpty) ...[
          const SizedBox(height: Esp.sm),
          EtiquetaSeccion('Sin zona'),
          const SizedBox(height: Esp.sm),
          Tarjeta(
            padding: const EdgeInsets.symmetric(vertical: Esp.sm),
            child: Column(
              children: [
                for (final m in sinZona)
                  _TarjetaPersona(miembro: m, arrastrable: false),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ZonaApilada extends ConsumerWidget {
  const _ZonaApilada({
    required this.zona,
    required this.gente,
    required this.puedeAdministrar,
  });

  final Zona zona;
  final List<Miembro> gente;
  final bool puedeAdministrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(0, Esp.md, 0, Esp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Esp.md, 0, Esp.sm, Esp.sm),
            child: Row(
              children: [
                Icon(zona.dibujo, size: 18, color: p.tinta3),
                const SizedBox(width: Esp.sm),
                Expanded(
                  child: Text(
                    zona.nombre,
                    style: TextStyle(fontSize: 14, color: p.tinta),
                  ),
                ),
                Text(
                  '${gente.length}',
                  style: TextStyle(fontSize: 13, color: p.tinta3),
                ),
                if (puedeAdministrar)
                  _BotonChico(
                    icono: Icons.person_add_alt_1_outlined,
                    tooltip: 'Sumar a alguien',
                    onTap: () =>
                        HojaAltaEmpleado.abrir(context, ref, zona: zona),
                  ),
              ],
            ),
          ),
          if (gente.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Esp.md, 0, Esp.md, Esp.sm),
              child: Text(
                'Todavía no hay nadie en esta zona.',
                style: TextStyle(fontSize: 13, color: p.tinta3),
              ),
            )
          else
            for (final m in gente)
              _TarjetaPersona(miembro: m, arrastrable: false),
        ],
      ),
    );
  }
}

class _BotonChico extends StatelessWidget {
  const _BotonChico({
    required this.icono,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icono, size: 17, color: context.paleta.tinta3),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onTap,
    );
  }
}

/// Dónde quedó la tarjeta del dueño, guardada por agencia.
final posicionDuenoProvider = FutureProvider<(double, double)>(
  (ref) => ref.watch(repositorioProvider).posicionDueno(),
);
