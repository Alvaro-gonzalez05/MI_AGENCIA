import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/revista.dart';
import '../../ui/componentes.dart';

/// El precio de revista de un auto, como el modal del diseño.
///
/// Lee nuestra copia de la guía, no la guía: es instantáneo, no gasta el
/// cupo diario y funciona sin internet. Si lo buscado todavía no está, se
/// lo encola al cosechador y se avisa que va a aparecer en un rato: es
/// preferible a mostrar un precio inventado.
class ModalPrecioRevista extends ConsumerStatefulWidget {
  const ModalPrecioRevista({super.key, required this.texto, this.anio});

  final String texto;
  final int? anio;

  static Future<void> abrir(
    BuildContext context, {
    required String texto,
    int? anio,
  }) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(Esp.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: ModalPrecioRevista(texto: texto, anio: anio),
      ),
    ),
  );

  @override
  ConsumerState<ModalPrecioRevista> createState() => _ModalPrecioRevistaState();
}

class _ModalPrecioRevistaState extends ConsumerState<ModalPrecioRevista> {
  late int? _anio = widget.anio;
  List<AnioRevista> _anios = const [];
  List<PrecioRevista> _precios = const [];
  bool _cargando = true;
  bool _pedido = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositorioProvider);
      final anios = await repo.aniosRevista(widget.texto);
      final anio = _anio ?? (anios.isEmpty ? null : anios.first.anio);
      final precios = await repo.buscarRevista(widget.texto, anio: anio);

      if (!mounted) return;
      setState(() {
        _anios = anios;
        _anio = anio;
        _precios = precios;
        _cargando = false;
      });

      // Todavía no lo tenemos: que el cosechador lo pida.
      if (precios.isEmpty && !_pedido) {
        _pedido = true;
        await repo.pedirRevista(widget.texto, anio: widget.anio);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cambiarAnio(int anio) async {
    setState(() {
      _anio = anio;
      _cargando = true;
    });
    final precios = await ref
        .read(repositorioProvider)
        .buscarRevista(widget.texto, anio: anio);
    if (!mounted) return;
    setState(() {
      _precios = precios;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final titulo = _precios.isEmpty
        ? widget.texto
        : _precios.first.titulo.isEmpty
        ? widget.texto
        : _precios.first.titulo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Esp.xl, Esp.xl, Esp.md, Esp.md),
          child: Row(
            children: [
              IconoEnCirculo(
                icono: Icons.sell_rounded,
                tamano: 44,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _capitalizar(titulo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      _precios.isEmpty
                          ? 'Precio de revista'
                          : 'Precio de revista · '
                                '${Fmt.mesAnio(_precios.first.actualizado)}',
                      style: TextStyle(fontSize: 15, color: p.tinta2),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Divider(color: p.borde, height: 1),

        Flexible(
          child: _cargando
              ? const Padding(
                  padding: EdgeInsets.all(Esp.xxl),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(Esp.xl),
                  child: Text(
                    'No se pudo buscar: $_error',
                    style: TextStyle(fontSize: 15, color: p.critico),
                  ),
                )
              : _precios.isEmpty
              ? _SinDatos(texto: widget.texto)
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Esp.xl),
                  children: [
                    if (_anios.length > 1) ...[
                      _SelectorAnio(
                        anios: _anios,
                        actual: _anio,
                        onElegir: _cambiarAnio,
                      ),
                      const SizedBox(height: Esp.sm),
                      Center(
                        child: Text(
                          '${_precios.length} '
                          '${_precios.length == 1 ? 'versión encontrada' : 'versiones encontradas'}',
                          style: TextStyle(fontSize: 14, color: p.tinta3),
                        ),
                      ),
                      const SizedBox(height: Esp.md),
                    ],
                    for (final x in _precios) _FilaPrecio(precio: x),
                    const SizedBox(height: Esp.md),
                    _TenesUno(precios: _precios),
                  ],
                ),
        ),

        Divider(color: p.borde, height: 1),
        Padding(
          padding: const EdgeInsets.all(Esp.lg),
          child: Center(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalizar(String s) => s
      .split(' ')
      .map(
        (p) => p.isEmpty
            ? p
            : '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}',
      )
      .join(' ');
}

/// El selector de año del diseño: ‹ 2018 [2019] 2020 ›
class _SelectorAnio extends StatelessWidget {
  const _SelectorAnio({
    required this.anios,
    required this.actual,
    required this.onElegir,
  });

  final List<AnioRevista> anios;
  final int? actual;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context) {
    final i = anios.indexWhere((a) => a.anio == actual);
    final desde = (i - 1).clamp(0, anios.length - 1);
    final visibles = anios.skip(desde).take(3).toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Año anterior',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: i < anios.length - 1
              ? () => onElegir(anios[i + 1].anio)
              : null,
        ),
        for (final a in visibles) ...[
          ChipSeleccion(
            etiqueta: '${a.anio}',
            activo: a.anio == actual,
            onTap: () => onElegir(a.anio),
          ),
          const SizedBox(width: Esp.sm),
        ],
        IconButton(
          tooltip: 'Año siguiente',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: i > 0 ? () => onElegir(anios[i - 1].anio) : null,
        ),
      ],
    );
  }
}

class _FilaPrecio extends StatelessWidget {
  const _FilaPrecio({required this.precio});

  final PrecioRevista precio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.sm),
      child: Container(
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: p.superficie,
          borderRadius: BorderRadius.circular(Curva.md),
          border: Border.all(color: p.borde, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    precio.version.isEmpty
                        ? precio.versionCompleta
                        : precio.version,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Año ${precio.anio}',
                    style: TextStyle(fontSize: 14, color: p.tinta2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Esp.sm),
            Text(
              Fmt.pesos(precio.precioArs),
              style: TextStyle(
                fontFamily: TemaApp.titulo,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: p.tinta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tenés 1 Toyota Hilux en venta: SRV 2019 · $34.500.000 · Ver ficha"
class _TenesUno extends ConsumerWidget {
  const _TenesUno({required this.precios});

  final List<PrecioRevista> precios;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    if (precios.isEmpty) return const SizedBox.shrink();

    final ids = precios.map((x) => x.versionId).toSet();
    final mias =
        (ref.watch(inventarioProvider).value ?? const <VehiculoInventario>[])
            .where((v) => !v.vendido && ids.contains(v.refVersionId))
            .toList();
    if (mias.isEmpty) return const SizedBox.shrink();

    final v = mias.first;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car_filled_rounded, size: 22, color: p.tinta2),
          const SizedBox(width: Esp.sm),
          Expanded(
            child: Text(
              mias.length == 1
                  ? 'Tenés uno en venta: ${v.titulo} ${v.anio} · '
                        '${Fmt.pesos(v.precioActual)}'
                  : 'Tenés ${mias.length} en venta de este modelo',
              style: TextStyle(fontSize: 15, color: p.tinta),
            ),
          ),
          const SizedBox(width: Esp.sm),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.go('/inventario/${v.id}');
            },
            icon: const Text('Ver ficha'),
            label: const Icon(Icons.arrow_forward_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Todavía no lo tenemos: se encoló y llega en un rato.
class _SinDatos extends StatelessWidget {
  const _SinDatos({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        children: [
          IconoEnCirculo(
            icono: Icons.hourglass_top_rounded,
            tamano: 56,
            color: p.observar,
            fondo: p.observarLavado,
          ),
          const SizedBox(height: Esp.md),
          Text(
            'Todavía no tenemos ese precio',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Esp.xs),
          Text(
            'Lo pedimos a la guía: en unos minutos va a estar acá y en la '
            'ficha de las unidades que coincidan. La guía nos deja hacer unas '
            'pocas consultas por día, así que primero se resuelven los autos '
            'que tenés cargados.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.45),
          ),
        ],
      ),
    );
  }
}
