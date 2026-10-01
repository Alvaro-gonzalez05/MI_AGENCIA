import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

/// Inventario, según el diseño "Clarity Drive" (pantalla
/// `inventario_filtros_y_menu_de_opciones`).
///
/// La idea del diseño: primero se elige en qué estado está la unidad
/// (pestañas), después se busca o se filtra, y recién ahí se mira la lista.
/// Cada unidad se muestra como una tarjeta con su foto, la patente bien
/// grande y una sola línea que dice qué le pasó por última vez.

/// En qué estado está la unidad. Es la pestaña de arriba.
enum EstadoLista {
  disponibles('Disponibles'),
  reservados('Reservados'),
  vendidos('Vendidos'),
  todos('Todos');

  const EstadoLista(this.etiqueta);
  final String etiqueta;

  bool incluye(VehiculoInventario v) => switch (this) {
    EstadoLista.disponibles =>
      !v.vendido && v.estado != EstadoVehiculo.reservado,
    EstadoLista.reservados => v.estado == EstadoVehiculo.reservado,
    EstadoLista.vendidos => v.vendido,
    EstadoLista.todos => true,
  };
}

/// Desde cuándo mirar los ingresos. "Elegir fechas" abre el calendario.
enum PeriodoIngreso {
  mes('Este mes'),
  tres('Últimos 3 meses'),
  anio('Este año'),
  todo('Cualquier fecha');

  const PeriodoIngreso(this.etiqueta);
  final String etiqueta;

  DateTime? get desde {
    final hoy = DateTime.now();
    return switch (this) {
      PeriodoIngreso.mes => DateTime(hoy.year, hoy.month, 1),
      PeriodoIngreso.tres => DateTime(hoy.year, hoy.month - 2, 1),
      PeriodoIngreso.anio => DateTime(hoy.year, 1, 1),
      PeriodoIngreso.todo => null,
    };
  }
}

enum OrdenInventario {
  recientes('Más recientes'),
  antiguos('Más días en stock'),
  precioMayor('Precio: mayor primero'),
  precioMenor('Precio: menor primero'),
  margenMenor('Margen: menor primero');

  const OrdenInventario(this.etiqueta);
  final String etiqueta;
}

/// Tramos de precio. Fijos y en millones: es como habla la agencia
/// ("tenés algo hasta veinte palos?").
enum TramoPrecio {
  todos('Cualquier precio', 0, double.infinity),
  hasta10('Hasta \$10 M', 0, 10000000),
  de10a20('\$10 M a \$20 M', 10000000, 20000000),
  de20a40('\$20 M a \$40 M', 20000000, 40000000),
  masDe40('Más de \$40 M', 40000000, double.infinity);

  const TramoPrecio(this.etiqueta, this.desde, this.hasta);
  final String etiqueta;
  final double desde, hasta;

  bool incluye(double precio) => precio >= desde && precio < hasta;
}

/// Cuánto hace que la unidad está parada. En el diseño es el filtro "Días
/// inmovilizado"; acá reutiliza el semáforo de rotación, que ya tiene los
/// umbrales configurados por la agencia.
enum DiasParado {
  todos('Cualquier antigüedad', null),
  observar('Más de lo esperado', AlertaRotacion.observar),
  atencion('Demoradas', AlertaRotacion.atencion),
  critico('Críticas', AlertaRotacion.critico);

  const DiasParado(this.etiqueta, this.alerta);
  final String etiqueta;
  final AlertaRotacion? alerta;
}

/// Filtros activos de la lista.
class FiltroInventario {
  const FiltroInventario({
    this.busqueda = '',
    this.estado = EstadoLista.disponibles,
    this.periodo = PeriodoIngreso.todo,
    this.rango,
    this.marca,
    this.anio,
    this.precio = TramoPrecio.todos,
    this.parado = DiasParado.todos,
    this.orden = OrdenInventario.recientes,
  });

  final String busqueda;
  final EstadoLista estado;
  final PeriodoIngreso periodo;

  /// Fechas elegidas a mano. Si está, manda sobre [periodo].
  final DateTimeRange? rango;

  final String? marca;
  final int? anio;
  final TramoPrecio precio;
  final DiasParado parado;
  final OrdenInventario orden;

  FiltroInventario copiar({
    String? busqueda,
    EstadoLista? estado,
    PeriodoIngreso? periodo,
    DateTimeRange? rango,
    String? marca,
    int? anio,
    TramoPrecio? precio,
    DiasParado? parado,
    OrdenInventario? orden,
    bool limpiarRango = false,
    bool limpiarMarca = false,
    bool limpiarAnio = false,
  }) => FiltroInventario(
    busqueda: busqueda ?? this.busqueda,
    estado: estado ?? this.estado,
    periodo: periodo ?? this.periodo,
    rango: limpiarRango ? null : (rango ?? this.rango),
    marca: limpiarMarca ? null : (marca ?? this.marca),
    anio: limpiarAnio ? null : (anio ?? this.anio),
    precio: precio ?? this.precio,
    parado: parado ?? this.parado,
    orden: orden ?? this.orden,
  );

  /// Lo que se puede limpiar de un toque. La pestaña y el orden no cuentan:
  /// no son filtros, son cómo se está mirando la lista.
  bool get hayFiltros =>
      busqueda.isNotEmpty ||
      periodo != PeriodoIngreso.todo ||
      rango != null ||
      marca != null ||
      anio != null ||
      precio != TramoPrecio.todos ||
      parado != DiasParado.todos;

  bool pasa(VehiculoInventario v) {
    if (!estado.incluye(v)) return false;

    final desde = rango?.start ?? periodo.desde;
    final hasta = rango?.end;
    if (desde != null && v.fechaIngreso.isBefore(desde)) return false;
    if (hasta != null && v.fechaIngreso.isAfter(hasta)) return false;

    if (marca != null && v.marca != marca) return false;
    if (anio != null && v.anio != anio) return false;
    if (!precio.incluye(v.precioActual)) return false;
    if (parado.alerta != null && v.alerta != parado.alerta) return false;

    final q = busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    final heno =
        '${v.codigo} ${v.marca} ${v.modelo} ${v.version ?? ''} '
                '${v.patente ?? ''}'
            .toLowerCase();
    // Sin espacios ni guiones: la patente se busca como venga escrita.
    final plano = heno.replaceAll(RegExp(r'[\s\-.]'), '');
    return heno.contains(q) ||
        plano.contains(q.replaceAll(RegExp(r'[\s\-.]'), ''));
  }
}

/// Riverpod 3 eliminó StateProvider: el estado mutable va en un Notifier.
class ControlFiltro extends Notifier<FiltroInventario> {
  @override
  FiltroInventario build() => const FiltroInventario();

  void poner(FiltroInventario f) => state = f;

  /// Limpia los filtros pero deja la pestaña y el orden donde estaban.
  void limpiar() =>
      state = FiltroInventario(estado: state.estado, orden: state.orden);
}

final filtroProvider = NotifierProvider<ControlFiltro, FiltroInventario>(
  ControlFiltro.new,
);

/// Inventario ya filtrado y ordenado. Se recalcula solo cuando cambia el
/// filtro o llegan datos nuevos.
final inventarioFiltradoProvider = Provider<List<VehiculoInventario>>((ref) {
  final todos = ref.watch(inventarioProvider).value ?? const [];
  final f = ref.watch(filtroProvider);
  final lista = todos.where(f.pasa).toList();

  lista.sort(switch (f.orden) {
    OrdenInventario.recientes => (a, b) => b.fechaIngreso.compareTo(
      a.fechaIngreso,
    ),
    OrdenInventario.antiguos => (a, b) => b.diasEnStock.compareTo(
      a.diasEnStock,
    ),
    OrdenInventario.precioMayor => (a, b) => b.precioActual.compareTo(
      a.precioActual,
    ),
    OrdenInventario.precioMenor => (a, b) => a.precioActual.compareTo(
      b.precioActual,
    ),
    OrdenInventario.margenMenor => (a, b) => a.margenActual.compareTo(
      b.margenActual,
    ),
  });
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
    final asincrono = ref.watch(inventarioProvider);
    final filtro = ref.watch(filtroProvider);
    final lista = ref.watch(inventarioFiltradoProvider);
    final ancho = MediaQuery.sizeOf(context).width;
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

    final todos = asincrono.value ?? const <VehiculoInventario>[];
    final mostrados = lista.take(_visibles).toList();
    final capital = lista.fold<double>(0, (s, v) => s + v.capitalInmovilizado);

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, Esp.xl),
            children: [
              Aparecer(
                child: CabeceraPantalla(
                  titulo: 'Inventario',
                  subtitulo: 'Listado de vehículos en la agencia',
                  accion: FilledButton.icon(
                    onPressed: () => context.go('/vehiculos'),
                    icon: const Icon(Icons.add_rounded, size: 24),
                    label: const Text('Cargar auto'),
                  ),
                ),
              ),
              const SizedBox(height: Esp.lg),
              Aparecer(indice: 1, child: _Pestanas(todos: todos)),
              const SizedBox(height: Esp.md),
              Aparecer(
                indice: 2,
                child: Buscador(
                  texto: filtro.busqueda,
                  controlador: _buscador,
                  pista: 'Buscar por patente, marca o modelo...',
                  onCambio: (v) => ref
                      .read(filtroProvider.notifier)
                      .poner(filtro.copiar(busqueda: v)),
                ),
              ),
              const SizedBox(height: Esp.md),
              Aparecer(indice: 3, child: _Filtros(todos: todos)),
              const SizedBox(height: Esp.md),
              Aparecer(
                indice: 4,
                child: _Resumen(
                  cuantos: lista.length,
                  capital: capital,
                  filtro: filtro,
                  onLimpiar: () {
                    _buscador.clear();
                    ref.read(filtroProvider.notifier).limpiar();
                  },
                ),
              ),
              const SizedBox(height: Esp.md),

              if (lista.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Esp.xl),
                  child: EstadoVacio(
                    icono: Icons.search_off_rounded,
                    titulo: filtro.hayFiltros
                        ? 'Ningún auto coincide con los filtros'
                        : 'Todavía no hay autos en ${filtro.estado.etiqueta.toLowerCase()}',
                    descripcion: filtro.hayFiltros
                        ? 'Probá sacando algún filtro o cambiando de pestaña.'
                        : 'Cargá la primera unidad y va a aparecer acá.',
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
                            icon: const Icon(Icons.add_rounded, size: 24),
                            label: const Text('Cargar un auto'),
                          ),
                  ),
                ),

              for (var i = 0; i < mostrados.length; i++) ...[
                if (i >= _tamanoPagina)
                  _TarjetaVehiculo(vehiculo: mostrados[i])
                else
                  Aparecer(
                    key: ValueKey('${mostrados[i].id}-${filtro.hashCode}'),
                    indice: i + 5,
                    child: _TarjetaVehiculo(vehiculo: mostrados[i]),
                  ),
                const SizedBox(height: Esp.md),
              ],

              if (mostrados.isNotEmpty)
                _PieLista(
                  cargando: _cargandoMas,
                  quedan: lista.length - mostrados.length,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Las pestañas por estado, con el conteo de cada una.
class _Pestanas extends ConsumerWidget {
  const _Pestanas({required this.todos});

  final List<VehiculoInventario> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in EstadoLista.values) ...[
            ChipSeleccion(
              etiqueta: e.etiqueta,
              contador: todos.where(e.incluye).length,
              activo: filtro.estado == e,
              onTap: () => ref
                  .read(filtroProvider.notifier)
                  .poner(filtro.copiar(estado: e)),
            ),
            if (e != EstadoLista.values.last) const SizedBox(width: Esp.sm),
          ],
        ],
      ),
    );
  }
}

/// La fila de filtros del diseño: desde cuándo, y después marca, año, precio,
/// antigüedad y orden.
class _Filtros extends ConsumerWidget {
  const _Filtros({required this.todos});

  final List<VehiculoInventario> todos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final filtro = ref.watch(filtroProvider);
    final notificador = ref.read(filtroProvider.notifier);

    final marcas = todos.map((v) => v.marca).toSet().toList()..sort();
    final anios = todos.map((v) => v.anio).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    Future<void> elegirFechas() async {
      final hoy = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(hoy.year - 10),
        lastDate: hoy,
        initialDateRange: filtro.rango,
        helpText: 'Ingresados entre',
        saveText: 'Aplicar',
      );
      if (r != null) {
        notificador.poner(
          filtro.copiar(rango: r, periodo: PeriodoIngreso.todo),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.lg),
        border: Border.all(color: p.borde, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: p.tinta2),
              const SizedBox(width: Esp.sm),
              Text(
                'Ingresados:',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in PeriodoIngreso.values) ...[
                  _Pildora(
                    etiqueta: e.etiqueta,
                    activo: filtro.rango == null && filtro.periodo == e,
                    onTap: () => notificador.poner(
                      filtro.copiar(periodo: e, limpiarRango: true),
                    ),
                  ),
                  const SizedBox(width: Esp.sm),
                ],
                _Pildora(
                  etiqueta: filtro.rango == null
                      ? 'Elegir fechas'
                      : '${Fmt.fecha(filtro.rango!.start)} a ${Fmt.fecha(filtro.rango!.end)}',
                  icono: Icons.calendar_month_rounded,
                  activo: filtro.rango != null,
                  onTap: elegirFechas,
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.md),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              _Selector<String?>(
                icono: Icons.directions_car_outlined,
                etiqueta: filtro.marca ?? 'Marca',
                activo: filtro.marca != null,
                valor: filtro.marca,
                opciones: [
                  (null, 'Todas las marcas'),
                  for (final m in marcas) (m, m),
                ],
                onElegir: (v) => notificador.poner(
                  v == null
                      ? filtro.copiar(limpiarMarca: true)
                      : filtro.copiar(marca: v),
                ),
              ),
              _Selector<int?>(
                icono: Icons.calendar_today_outlined,
                etiqueta: filtro.anio?.toString() ?? 'Año',
                activo: filtro.anio != null,
                valor: filtro.anio,
                opciones: [
                  (null, 'Todos los años'),
                  for (final a in anios) (a, '$a'),
                ],
                onElegir: (v) => notificador.poner(
                  v == null
                      ? filtro.copiar(limpiarAnio: true)
                      : filtro.copiar(anio: v),
                ),
              ),
              _Selector<TramoPrecio>(
                icono: Icons.attach_money_rounded,
                etiqueta: filtro.precio == TramoPrecio.todos
                    ? 'Precio'
                    : filtro.precio.etiqueta,
                activo: filtro.precio != TramoPrecio.todos,
                valor: filtro.precio,
                opciones: [for (final t in TramoPrecio.values) (t, t.etiqueta)],
                onElegir: (v) => notificador.poner(filtro.copiar(precio: v)),
              ),
              _Selector<DiasParado>(
                icono: Icons.hourglass_top_rounded,
                etiqueta: filtro.parado == DiasParado.todos
                    ? 'Días en stock'
                    : filtro.parado.etiqueta,
                activo: filtro.parado != DiasParado.todos,
                valor: filtro.parado,
                opciones: [for (final d in DiasParado.values) (d, d.etiqueta)],
                onElegir: (v) => notificador.poner(filtro.copiar(parado: v)),
              ),
              _Selector<OrdenInventario>(
                icono: Icons.swap_vert_rounded,
                etiqueta: 'Ordenar: ${filtro.orden.etiqueta}',
                activo: false,
                valor: filtro.orden,
                opciones: [
                  for (final o in OrdenInventario.values) (o, o.etiqueta),
                ],
                onElegir: (v) => notificador.poner(filtro.copiar(orden: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pastilla chica de un solo toque (los períodos de ingreso).
class _Pildora extends StatelessWidget {
  const _Pildora({
    required this.etiqueta,
    required this.activo,
    required this.onTap,
    this.icono,
  });

  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;
  final IconData? icono;

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
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.md,
            vertical: Esp.sm + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null || activo) ...[
                Icon(
                  activo ? Icons.check_rounded : icono,
                  size: 18,
                  color: activo ? p.acentoTinta : p.tinta2,
                ),
                const SizedBox(width: Esp.xs + 2),
              ],
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                  color: activo ? p.acentoTinta : p.tinta2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un desplegable con aspecto de pastilla, como los del diseño.
class _Selector<T> extends StatelessWidget {
  const _Selector({
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.valor,
    required this.opciones,
    required this.onElegir,
  });

  final IconData icono;
  final String etiqueta;
  final bool activo;
  final T valor;
  final List<(T, String)> opciones;
  final ValueChanged<T> onElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      decoration: BoxDecoration(
        color: activo ? p.acentoLavado : p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: activo ? p.acento : p.borde, width: 1.5),
      ),
      child: PopupMenuButton<T>(
        tooltip: etiqueta,
        initialValue: valor,
        onSelected: onElegir,
        itemBuilder: (_) => [
          for (final (v, texto) in opciones)
            PopupMenuItem(value: v, child: Text(texto)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.md,
            vertical: Esp.sm + 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 20, color: p.tinta2),
              const SizedBox(width: Esp.sm - 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 20, color: p.tinta2),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Mostrando 8 autos disponibles · ingresados este año", con el atajo para
/// sacar todos los filtros de una.
class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.cuantos,
    required this.capital,
    required this.filtro,
    required this.onLimpiar,
  });

  final int cuantos;
  final double capital;
  final FiltroInventario filtro;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final detalle = [
      if (filtro.rango != null)
        'ingresados entre el ${Fmt.fecha(filtro.rango!.start)} y el ${Fmt.fecha(filtro.rango!.end)}'
      else if (filtro.periodo != PeriodoIngreso.todo)
        'ingresados ${filtro.periodo.etiqueta.toLowerCase()}',
      if (filtro.marca != null) filtro.marca!,
      if (filtro.anio != null) 'del ${filtro.anio}',
      if (filtro.precio != TramoPrecio.todos)
        filtro.precio.etiqueta.toLowerCase(),
      if (filtro.parado != DiasParado.todos)
        filtro.parado.etiqueta.toLowerCase(),
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: p.bien, shape: BoxShape.circle),
        ),
        const SizedBox(width: Esp.sm),
        Expanded(
          child: Text(
            'Mostrando $cuantos '
            '${cuantos == 1 ? 'auto' : 'autos'} '
            '${filtro.estado == EstadoLista.todos ? 'en total' : filtro.estado.etiqueta.toLowerCase()}'
            '${detalle.isEmpty ? '' : ' · $detalle'}'
            '${capital <= 0 ? '' : ' · capital ${Fmt.pesosCompacto(capital)}'}',
            style: TextStyle(fontSize: 15, color: p.tinta2),
          ),
        ),
        if (filtro.hayFiltros)
          TextButton.icon(
            onPressed: onLimpiar,
            icon: const Icon(Icons.close_rounded, size: 20),
            label: const Text('Limpiar filtros'),
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
        padding: const EdgeInsets.symmetric(vertical: Esp.lg),
        child: Center(
          child: Text(
            'No hay más unidades',
            style: TextStyle(fontSize: 14, color: p.tinta3),
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

/// La tarjeta del diseño: foto, datos, patente y una línea que cuenta lo
/// último que le pasó a la unidad.
class _TarjetaVehiculo extends StatelessWidget {
  const _TarjetaVehiculo({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final datos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          v.titulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: Esp.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Esp.sm,
          runSpacing: Esp.xs,
          children: [
            Text(
              '${v.anio}${v.km == null ? '' : '  ·  ${Fmt.km(v.km)}'}',
              style: TextStyle(fontSize: 15, color: p.tinta2),
            ),
            if (v.patente != null && v.patente!.isNotEmpty)
              _Patente(v.patente!),
          ],
        ),
        const SizedBox(height: Esp.sm),
        _UltimoMovimiento(vehiculo: v),
      ],
    );

    final precioYEstado = Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Column(
        crossAxisAlignment: angosto
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuUnidad(vehiculo: v),
              const SizedBox(width: Esp.sm - 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    Fmt.pesos(v.precioActual),
                    style: TextStyle(
                      fontFamily: TemaApp.titulo,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: v.vendido ? p.tinta2 : p.tinta,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          Pastilla(
            texto: _estado(v),
            color: _colorEstado(v, p),
            lavado: _lavadoEstado(v, p),
          ),
          const SizedBox(height: Esp.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: p.superficie),
            onPressed: () => context.go('/inventario/${v.id}'),
            icon: const Text('Ver ficha'),
            label: const Icon(Icons.arrow_forward_rounded, size: 20),
          ),
        ],
      ),
    );

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.md),
      onTap: () => context.go('/inventario/${v.id}'),
      child: angosto
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FotoPortada(
                      vehiculoId: v.id,
                      ancho: 108,
                      alto: 92,
                      colorVacio: v.alerta.color(p),
                      fondoVacio: v.alerta.lavado(p),
                      textoVacio: 'Sin fotos',
                    ),
                    const SizedBox(width: Esp.md),
                    Expanded(child: datos),
                  ],
                ),
                const SizedBox(height: Esp.md),
                Divider(color: p.borde, height: 1.5, thickness: 1.5),
                const SizedBox(height: Esp.md),
                precioYEstado,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FotoPortada(
                  vehiculoId: v.id,
                  ancho: 168,
                  alto: 120,
                  colorVacio: v.alerta.color(p),
                  fondoVacio: v.alerta.lavado(p),
                  textoVacio: 'Sin fotos',
                ),
                const SizedBox(width: Esp.lg),
                Expanded(child: datos),
                const SizedBox(width: Esp.lg),
                precioYEstado,
              ],
            ),
    );
  }

  static String _estado(VehiculoInventario v) => switch (v.estado) {
    EstadoVehiculo.vendido => 'Vendido',
    EstadoVehiculo.reservado => 'Reservado',
    EstadoVehiculo.enPreparacion => 'En preparación',
    EstadoVehiculo.dadoDeBaja => 'Dado de baja',
    EstadoVehiculo.enStock => 'Disponible',
  };

  static Color _colorEstado(VehiculoInventario v, Paleta p) =>
      switch (v.estado) {
        EstadoVehiculo.vendido || EstadoVehiculo.dadoDeBaja => p.neutro,
        EstadoVehiculo.reservado => p.observar,
        EstadoVehiculo.enPreparacion => p.tinta2,
        EstadoVehiculo.enStock => p.bien,
      };

  static Color _lavadoEstado(VehiculoInventario v, Paleta p) =>
      switch (v.estado) {
        EstadoVehiculo.vendido || EstadoVehiculo.dadoDeBaja => p.neutroLavado,
        EstadoVehiculo.reservado => p.observarLavado,
        EstadoVehiculo.enPreparacion => p.superficieHundida,
        EstadoVehiculo.enStock => p.bienLavado,
      };
}

/// La patente, en su placa.
class _Patente extends StatelessWidget {
  const _Patente(this.patente);

  final String patente;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.sm, vertical: 3),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.sm),
        border: Border.all(color: p.bordeFuerte, width: 1.5),
      ),
      child: Text(
        patente.toUpperCase(),
        style: TextStyle(
          fontFamily: TemaApp.titulo,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: p.tinta,
        ),
      ),
    );
  }
}

/// Una sola línea con lo último que pasó: cuándo entró, hasta cuándo está
/// reservada o cuándo se vendió.
class _UltimoMovimiento extends ConsumerWidget {
  const _UltimoMovimiento({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final v = vehiculo;
    // Para una unidad reservada, lo que importa es hasta cuándo se guarda.
    final reserva = v.estado == EstadoVehiculo.reservado
        ? ref.watch(reservaDeProvider(v.id)).value
        : null;

    final (IconData icono, String texto, Color color) = switch (v.estado) {
      EstadoVehiculo.vendido => (
        Icons.verified_outlined,
        'Vendido el ${Fmt.fecha(v.fechaVenta)}',
        p.tinta3,
      ),
      EstadoVehiculo.reservado => (
        Icons.event_available_rounded,
        reserva == null
            ? 'Reservado · ingresó el ${Fmt.fecha(v.fechaIngreso)}'
            : 'Reservado hasta el ${Fmt.fecha(reserva.venceEl)}'
                  ' · ${reserva.clienteNombre}',
        reserva != null && reserva.vencida ? p.critico : p.observar,
      ),
      _ => (
        Icons.history_rounded,
        'Ingresó el ${Fmt.fecha(v.fechaIngreso)} (hace ${Fmt.dias(v.diasEnStock)})',
        v.alerta == AlertaRotacion.normal ? p.tinta3 : v.alerta.color(p),
      ),
    };

    return Row(
      children: [
        Icon(icono, size: 18, color: color),
        const SizedBox(width: Esp.sm - 2),
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: color),
          ),
        ),
      ],
    );
  }
}

/// El menú de tres puntos de cada unidad: lo que se puede hacer con ella sin
/// entrar a la ficha.
class _MenuUnidad extends StatelessWidget {
  const _MenuUnidad({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de ${vehiculo.codigo}',
      icon: Icon(Icons.more_vert_rounded, size: 22, color: p.tinta2),
      onSelected: (opcion) => switch (opcion) {
        'ficha' => context.go('/inventario/${vehiculo.id}'),
        'precio' => context.go('/precios'),
        'gasto' => context.go('/gastos'),
        'venta' => context.go('/ventas'),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'ficha', child: Text('Ver la ficha')),
        const PopupMenuItem(value: 'precio', child: Text('Cambiar el precio')),
        const PopupMenuItem(value: 'gasto', child: Text('Cargar un gasto')),
        if (!vehiculo.vendido)
          const PopupMenuItem(value: 'venta', child: Text('Marcar vendida')),
      ],
    );
  }
}
