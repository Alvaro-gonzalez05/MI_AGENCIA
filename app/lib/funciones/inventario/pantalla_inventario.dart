import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

/// Filtros activos de la lista.
class FiltroInventario {
  const FiltroInventario({
    this.busqueda = '',
    this.alerta,
    this.marca,
    this.soloEnStock = true,
  });

  final String busqueda;
  final AlertaRotacion? alerta;
  final String? marca;
  final bool soloEnStock;

  FiltroInventario copiar({
    String? busqueda,
    AlertaRotacion? alerta,
    String? marca,
    bool? soloEnStock,
    bool limpiarAlerta = false,
    bool limpiarMarca = false,
  }) => FiltroInventario(
    busqueda: busqueda ?? this.busqueda,
    alerta: limpiarAlerta ? null : (alerta ?? this.alerta),
    marca: limpiarMarca ? null : (marca ?? this.marca),
    soloEnStock: soloEnStock ?? this.soloEnStock,
  );

  bool get hayFiltros =>
      busqueda.isNotEmpty || alerta != null || marca != null || !soloEnStock;
}

/// Riverpod 3 eliminó StateProvider: el estado mutable va en un Notifier.
class ControlFiltro extends Notifier<FiltroInventario> {
  @override
  FiltroInventario build() => const FiltroInventario();

  void poner(FiltroInventario f) => state = f;
  void limpiar() => state = const FiltroInventario();
}

final filtroProvider = NotifierProvider<ControlFiltro, FiltroInventario>(
  ControlFiltro.new,
);

/// Inventario ya filtrado y ordenado. Se recalcula solo cuando cambia el
/// filtro o llegan datos nuevos.
final inventarioFiltradoProvider = Provider<List<VehiculoInventario>>((ref) {
  final todos = ref.watch(inventarioProvider).value ?? const [];
  final f = ref.watch(filtroProvider);
  final q = f.busqueda.trim().toLowerCase();

  final lista = todos.where((v) {
    if (f.soloEnStock && v.vendido) return false;
    if (f.alerta != null && v.alerta != f.alerta) return false;
    if (f.marca != null && v.marca != f.marca) return false;
    if (q.isNotEmpty) {
      final heno = '${v.codigo} ${v.marca} ${v.modelo} ${v.version ?? ''}'
          .toLowerCase();
      if (!heno.contains(q)) return false;
    }
    return true;
  }).toList();

  // Lo más viejo primero: es lo que hay que mirar.
  lista.sort((a, b) => b.diasEnStock.compareTo(a.diasEnStock));
  return lista;
});

class PantallaInventario extends ConsumerStatefulWidget {
  const PantallaInventario({super.key});

  @override
  ConsumerState<PantallaInventario> createState() => _PantallaInventarioState();
}

class _PantallaInventarioState extends ConsumerState<PantallaInventario> {
  static const _tamanoPagina = 20;

  final _scroll = ScrollController();
  final _buscador = TextEditingController();
  int _visibles = _tamanoPagina;
  bool _cargandoMas = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alScrollear);
  }

  @override
  void dispose() {
    _scroll.removeListener(_alScrollear);
    _scroll.dispose();
    _buscador.dispose();
    super.dispose();
  }

  /// Scroll infinito: se pide la pagina siguiente 400 px ANTES del final, para
  /// que los datos lleguen mientras el usuario todavia esta scrolleando y no
  /// vea nunca el spinner.
  void _alScrollear() {
    if (_cargandoMas) return;
    if (!_scroll.hasClients) return;
    final faltan = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (faltan > 400) return;

    final total = ref.read(inventarioFiltradoProvider).length;
    if (_visibles >= total) return;

    setState(() => _cargandoMas = true);
    // Cuando esto lea de Supabase, aca va el select con range(). La demora
    // simulada mantiene el mismo comportamiento visual.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _visibles = (_visibles + _tamanoPagina).clamp(0, total);
        _cargandoMas = false;
      });
    });
  }

  void _reiniciarPaginado() => _visibles = _tamanoPagina;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final asincrono = ref.watch(inventarioProvider);
    final filtro = ref.watch(filtroProvider);
    final lista = ref.watch(inventarioFiltradoProvider);
    final ancho = MediaQuery.sizeOf(context).width;
    final esAncho = ancho >= Corte.escritorio;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;

    // Al cambiar el filtro, volver a la primera pagina.
    ref.listen(filtroProvider, (_, _) => setState(_reiniciarPaginado));

    if (asincrono.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (asincrono.hasError) {
      return EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar el inventario',
        descripcion: '${asincrono.error}',
      );
    }

    final marcas =
        (asincrono.value ?? const <VehiculoInventario>[])
            .map((v) => v.marca)
            .toSet()
            .toList()
          ..sort();

    final mostrados = lista.take(_visibles).toList();
    final capital = lista.fold<double>(0, (s, v) => s + v.capitalInmovilizado);

    return Column(
      children: [
        _BarraFiltros(
          buscador: _buscador,
          filtro: filtro,
          marcas: marcas,
          margen: margen,
        ),
        Expanded(
          child: lista.isEmpty
              ? EstadoVacio(
                  icono: Icons.search_off_rounded,
                  titulo: 'Sin resultados',
                  descripcion: filtro.hayFiltros
                      ? 'Ninguna unidad coincide con los filtros aplicados.'
                      : 'Todavía no hay vehículos cargados.',
                  accion: filtro.hayFiltros
                      ? OutlinedButton(
                          onPressed: () {
                            _buscador.clear();
                            ref.read(filtroProvider.notifier).limpiar();
                          },
                          child: const Text('Limpiar filtros'),
                        )
                      : FilledButton.icon(
                          onPressed: () => context.go('/vehiculos'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Cargar un vehículo'),
                        ),
                )
              : ListView.separated(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, Esp.xl),
                  itemCount: mostrados.length + 1,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: Esp.sm + 2),
                  itemBuilder: (context, i) {
                    if (i == mostrados.length) {
                      return _PieLista(
                        cargando: _cargandoMas,
                        quedan: lista.length - mostrados.length,
                      );
                    }
                    final v = mostrados[i];
                    final fila = esAncho
                        ? _FilaVehiculo(vehiculo: v)
                        : _TarjetaVehiculo(vehiculo: v);
                    // Solo la primera tanda entra animada: las paginas que
                    // llegan scrolleando tienen que aparecer ya, sin demora.
                    if (i >= _tamanoPagina) return fila;
                    return Aparecer(
                      // La clave por filtro hace que al filtrar las filas
                      // entren animadas de nuevo en vez de reciclar las viejas.
                      key: ValueKey('${v.id}-${identityHashCode(filtro)}'),
                      indice: i,
                      child: fila,
                    );
                  },
                ),
        ),
        if (mostrados.isNotEmpty)
          SafeArea(
            top: false,
            bottom: false,
            child: Container(
              margin: EdgeInsets.fromLTRB(margen, 0, margen, Esp.md),
              padding: const EdgeInsets.fromLTRB(
                Esp.lg + 2,
                Esp.sm + 2,
                Esp.sm + 2,
                Esp.sm + 2,
              ),
              decoration: ShapeDecoration(
                color: p.negro,
                shape: const StadiumBorder(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mostrando ${mostrados.length} de ${lista.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.sobreNegro2),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Esp.md + 2,
                      vertical: 6,
                    ),
                    decoration: ShapeDecoration(
                      color: p.acento,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'Capital ${Fmt.pesosCompacto(capital)}',
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.acentoTinta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PieLista extends StatelessWidget {
  const _PieLista({required this.cargando, required this.quedan});

  final bool cargando;
  final int quedan;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    if (quedan <= 0 && !cargando) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Esp.xl),
        child: Center(
          child: Text(
            'No hay más unidades',
            style: TextStyle(fontSize: 12, color: p.tinta3),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Esp.xl),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _BarraFiltros extends ConsumerWidget {
  const _BarraFiltros({
    required this.buscador,
    required this.filtro,
    required this.marcas,
    required this.margen,
  });

  final TextEditingController buscador;
  final FiltroInventario filtro;
  final List<String> marcas;
  final double margen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final notificador = ref.read(filtroProvider.notifier);
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final buscadorCampo = SizedBox(
      height: 46,
      child: TextField(
        controller: buscador,
        onChanged: (v) => notificador.poner(filtro.copiar(busqueda: v)),
        decoration: InputDecoration(
          hintText: 'Buscar marca, modelo o código',
          filled: true,
          fillColor: p.superficie,
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: p.tinta2),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Esp.sm),
          border: _pildora(p.borde),
          enabledBorder: _pildora(p.borde),
          focusedBorder: _pildora(p.acentoTexto, ancho: 1.6),
          suffixIcon: filtro.busqueda.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    buscador.clear();
                    notificador.poner(filtro.copiar(busqueda: ''));
                  },
                ),
        ),
      ),
    );

    final chips = <Widget>[
      ChipSeleccion(
        etiqueta: 'Solo en stock',
        icono: Icons.inventory_2_outlined,
        activo: filtro.soloEnStock,
        onTap: () =>
            notificador.poner(filtro.copiar(soloEnStock: !filtro.soloEnStock)),
      ),
      for (final a in [
        AlertaRotacion.critico,
        AlertaRotacion.atencion,
        AlertaRotacion.observar,
        AlertaRotacion.normal,
      ])
        ChipSeleccion(
          etiqueta: a.etiqueta,
          activo: filtro.alerta == a,
          color: a.color(p),
          onTap: () => notificador.poner(
            filtro.alerta == a
                ? filtro.copiar(limpiarAlerta: true)
                : filtro.copiar(alerta: a),
          ),
        ),
      if (marcas.isNotEmpty)
        Container(
          height: 40,
          padding: const EdgeInsets.only(left: Esp.lg - 2, right: Esp.sm),
          decoration: ShapeDecoration(
            color: filtro.marca != null ? p.acento : p.superficie,
            shape: StadiumBorder(
              side: BorderSide(
                color: filtro.marca != null ? p.acento : p.borde,
              ),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: filtro.marca,
              hint: Text(
                'Marca',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: p.tinta2,
                ),
              ),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: filtro.marca != null ? p.acentoTinta : p.tinta3,
              ),
              isDense: true,
              borderRadius: BorderRadius.circular(Curva.md),
              dropdownColor: p.superficieElevada,
              selectedItemBuilder: (_) => [
                const SizedBox.shrink(),
                for (final m in marcas)
                  Center(
                    child: Text(
                      m,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.acentoTinta,
                      ),
                    ),
                  ),
              ],
              style: TextStyle(fontSize: 13, color: p.tinta),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    'Todas las marcas',
                    style: TextStyle(fontSize: 13, color: p.tinta2),
                  ),
                ),
                for (final m in marcas)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => notificador.poner(
                v == null
                    ? filtro.copiar(limpiarMarca: true)
                    : filtro.copiar(marca: v),
              ),
            ),
          ),
        ),
      if (filtro.hayFiltros)
        TextButton.icon(
          onPressed: () {
            buscador.clear();
            notificador.poner(const FiltroInventario());
          },
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('Limpiar'),
        ),
    ];

    // En movil los chips van en una sola fila deslizable: apilados en varias
    // lineas se comian media pantalla antes del primer vehiculo.
    if (angosto) {
      return Padding(
        padding: const EdgeInsets.only(top: Esp.xs, bottom: Esp.md),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: margen),
              child: buscadorCampo,
            ),
            const SizedBox(height: Esp.md),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: margen),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: Esp.sm),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, Esp.lg),
      child: Wrap(
        spacing: Esp.sm,
        runSpacing: Esp.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 300, child: buscadorCampo),
          ...chips,
        ],
      ),
    );
  }

  static OutlineInputBorder _pildora(Color color, {double ancho = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Curva.completo),
        borderSide: BorderSide(color: color, width: ancho),
      );
}

/// Mosaico con el icono del auto teñido por el semaforo de rotacion: el
/// estado se lee antes que cualquier texto.
class _IconoUnidad extends StatelessWidget {
  const _IconoUnidad({required this.vehiculo, this.tamano = 48});

  final VehiculoInventario vehiculo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final color = vehiculo.alerta.color(p);
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: vehiculo.alerta.lavado(p),
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Icon(
        Icons.directions_car_filled_rounded,
        size: tamano * 0.48,
        color: color,
      ),
    );
  }
}

/// Fila para escritorio: densa, pensada para escanear muchas unidades.
class _FilaVehiculo extends StatelessWidget {
  const _FilaVehiculo({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final margenColor = v.margenActual < 0
        ? p.critico
        : v.margenActual < 0.10
        ? p.observar
        : p.bien;

    return Tarjeta(
      padding: const EdgeInsets.fromLTRB(
        Esp.md,
        Esp.md,
        Esp.lg,
        Esp.md,
      ),
      onTap: () => context.go('/inventario/${v.id}'),
      child: Row(
        children: [
          _IconoUnidad(vehiculo: v),
          const SizedBox(width: Esp.md + 2),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${v.codigo} · ${v.subtitulo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.tinta3),
                ),
              ],
            ),
          ),
          _Columna(
            etiqueta: 'Días',
            valor: '${v.diasEnStock}',
            color: v.alerta.color(p),
          ),
          _Columna(etiqueta: 'Costo', valor: Fmt.pesosCompacto(v.costoTotal)),
          _Columna(
            etiqueta: 'Precio',
            valor: Fmt.pesosCompacto(v.precioActual),
          ),
          _Columna(
            etiqueta: 'Margen',
            valor: Fmt.porcentaje(v.margenActual),
            color: margenColor,
          ),
          _Columna(
            etiqueta: 'Ganancia real',
            valor: Fmt.pesosCompacto(v.gananciaRealIpc),
            color: v.gananciaRealIpc < 0 ? p.critico : p.tinta,
          ),
          const SizedBox(width: Esp.lg),
          SizedBox(
            width: 104,
            child: Align(
              alignment: Alignment.centerRight,
              child: Pastilla(
                texto: v.alerta.etiqueta,
                color: v.alerta.color(p),
                lavado: v.alerta.lavado(p),
              ),
            ),
          ),
          const SizedBox(width: Esp.md),
          IconoEnCirculo(
            icono: Icons.arrow_forward_rounded,
            tamano: 34,
            color: p.tinta,
            fondo: p.superficieHundida,
          ),
        ],
      ),
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({required this.etiqueta, required this.valor, this.color});

  final String etiqueta, valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Expanded(
      flex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(etiqueta, style: TextStyle(fontSize: 11, color: p.tinta3)),
          const SizedBox(height: 2),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color ?? p.tinta,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta para movil: la fila densa no entra en 375 px.
class _TarjetaVehiculo extends StatelessWidget {
  const _TarjetaVehiculo({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.md + 2),
      onTap: () => context.go('/inventario/${v.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconoUnidad(vehiculo: v, tamano: 46),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: p.tinta,
                      ),
                    ),
                    Text(
                      '${v.codigo} · ${v.subtitulo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.sm),
              Pastilla(
                texto: v.alerta.etiqueta,
                color: v.alerta.color(p),
                lavado: v.alerta.lavado(p),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Row(
            children: [
              Expanded(
                child: _MiniDato(
                  icono: Icons.schedule_rounded,
                  etiqueta: 'En stock',
                  valor: Fmt.dias(v.diasEnStock),
                  color: v.alerta.color(p),
                ),
              ),
              const SizedBox(width: Esp.sm),
              Expanded(
                child: _MiniDato(
                  icono: Icons.sell_outlined,
                  etiqueta: 'Precio',
                  valor: Fmt.pesosCompacto(v.precioActual),
                ),
              ),
              const SizedBox(width: Esp.sm),
              Expanded(
                child: _MiniDato(
                  icono: Icons.percent_rounded,
                  etiqueta: 'Margen',
                  valor: Fmt.porcentaje(v.margenActual),
                  color: v.margenActual < 0.10 ? p.observar : p.bien,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniDato extends StatelessWidget {
  const _MiniDato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.color,
  });

  final IconData icono;
  final String etiqueta, valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.sm + 2,
        vertical: Esp.sm,
      ),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.sm + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 12, color: p.tinta3),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: p.tinta3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: color ?? p.tinta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
