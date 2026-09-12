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
  }) =>
      FiltroInventario(
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

final filtroProvider =
    NotifierProvider<ControlFiltro, FiltroInventario>(ControlFiltro.new);

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

    final marcas = (asincrono.value ?? const <VehiculoInventario>[])
        .map((v) => v.marca)
        .toSet()
        .toList()
      ..sort();

    final mostrados = lista.take(_visibles).toList();

    return Column(
      children: [
        _BarraFiltros(
          buscador: _buscador,
          filtro: filtro,
          marcas: marcas,
          cantidad: lista.length,
          total: (asincrono.value ?? const []).length,
        ),
        Expanded(
          child: lista.isEmpty
              ? EstadoVacio(
                  icono: Icons.search_off,
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
                  padding: const EdgeInsets.all(Esp.xl),
                  itemCount: mostrados.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: Esp.sm),
                  itemBuilder: (context, i) {
                    if (i == mostrados.length) {
                      return _PieLista(
                        cargando: _cargandoMas,
                        quedan: lista.length - mostrados.length,
                      );
                    }
                    final v = mostrados[i];
                    return esAncho
                        ? _FilaVehiculo(vehiculo: v)
                        : _TarjetaVehiculo(vehiculo: v);
                  },
                ),
        ),
        if (mostrados.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Esp.xl, vertical: Esp.sm),
            decoration: BoxDecoration(
              color: p.superficie,
              border: Border(top: BorderSide(color: p.borde)),
            ),
            child: Row(
              children: [
                Text(
                  'Mostrando ${mostrados.length} de ${lista.length}',
                  style: TextStyle(fontSize: 12, color: p.tinta3),
                ),
                const Spacer(),
                Text(
                  'Capital: ${Fmt.pesosCompacto(lista.fold<double>(0, (s, v) => s + v.capitalInmovilizado))}',
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.tinta2,
                  ),
                ),
              ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Esp.xl),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.tinta3),
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
    required this.cantidad,
    required this.total,
  });

  final TextEditingController buscador;
  final FiltroInventario filtro;
  final List<String> marcas;
  final int cantidad, total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final notificador = ref.read(filtroProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Esp.xl, vertical: Esp.md),
      decoration: BoxDecoration(
        color: p.superficie,
        border: Border(bottom: BorderSide(color: p.borde)),
      ),
      child: Wrap(
        spacing: Esp.sm,
        runSpacing: Esp.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            height: 38,
            child: TextField(
              controller: buscador,
              onChanged: (v) =>
                  notificador.poner(filtro.copiar(busqueda: v)),
              decoration: InputDecoration(
                hintText: 'Marca, modelo o código',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: Esp.sm),
                suffixIcon: filtro.busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          buscador.clear();
                          notificador.poner(filtro.copiar(busqueda: ''));
                        },
                      ),
              ),
            ),
          ),
          _Chip(
            etiqueta: 'Solo en stock',
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
            _Chip(
              etiqueta: a.etiqueta,
              activo: filtro.alerta == a,
              color: a.color(p),
              onTap: () => notificador.poner(filtro.alerta == a
                  ? filtro.copiar(limpiarAlerta: true)
                  : filtro.copiar(alerta: a)),
            ),
          if (marcas.isNotEmpty)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: Esp.md),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
                border: Border.all(color: p.borde),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: filtro.marca,
                  hint: Text('Marca',
                      style: TextStyle(fontSize: 13, color: p.tinta3)),
                  isDense: true,
                  borderRadius: BorderRadius.circular(Curva.md),
                  dropdownColor: p.superficieElevada,
                  style: TextStyle(fontSize: 13, color: p.tinta),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Todas las marcas',
                          style: TextStyle(fontSize: 13, color: p.tinta2)),
                    ),
                    for (final m in marcas)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => notificador.poner(v == null
                      ? filtro.copiar(limpiarMarca: true)
                      : filtro.copiar(marca: v)),
                ),
              ),
            ),
          if (filtro.hayFiltros)
            TextButton.icon(
              onPressed: () {
                buscador.clear();
                notificador.poner(const FiltroInventario());
              },
              icon: const Icon(Icons.close, size: 15),
              label: const Text('Limpiar'),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.etiqueta,
    required this.activo,
    required this.onTap,
    this.color,
  });

  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = color ?? p.acento;
    return Material(
      color: activo ? c.withValues(alpha: 0.14) : p.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Curva.md),
        // Sin `alignment`: se lo pusiera, el Container se estira hasta las
        // constraints maximas y en movil cada chip ocuparia todo el ancho.
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: Esp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Curva.md),
            border: Border.all(color: activo ? c : p.borde),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: Esp.sm - 2),
              ],
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: activo ? FontWeight.w600 : FontWeight.w500,
                  color: activo ? (color ?? p.acento) : p.tinta2,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(
          horizontal: Esp.lg, vertical: Esp.md),
      onTap: () => context.go('/inventario/${v.id}'),
      child: Row(
        children: [
          // Franja de color: el estado se lee antes que cualquier texto.
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: v.alerta.color(p),
              borderRadius: BorderRadius.circular(Curva.completo),
            ),
          ),
          const SizedBox(width: Esp.md),
          SizedBox(
            width: 48,
            child: Text(
              v.codigo,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 12,
                color: p.tinta3,
              ),
            ),
          ),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.tinta,
                  ),
                ),
                Text(
                  v.subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.tinta3),
                ),
              ],
            ),
          ),
          _Columna(etiqueta: 'Días', valor: '${v.diasEnStock}', color: v.alerta.color(p)),
          _Columna(etiqueta: 'Costo', valor: Fmt.pesosCompacto(v.costoTotal)),
          _Columna(etiqueta: 'Precio', valor: Fmt.pesosCompacto(v.precioActual)),
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
          const SizedBox(width: Esp.md),
          Pastilla(
            texto: v.alerta.etiqueta,
            color: v.alerta.color(p),
            lavado: v.alerta.lavado(p),
          ),
          const SizedBox(width: Esp.sm),
          Icon(Icons.chevron_right, size: 18, color: p.tinta3),
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
          Text(etiqueta, style: TextStyle(fontSize: 10.5, color: p.tinta3)),
          const SizedBox(height: 1),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 13,
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
      onTap: () => context.go('/inventario/${v.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                        fontWeight: FontWeight.w600,
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
          Divider(color: p.borde, height: 1),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              Expanded(
                child: _MiniDato(
                  etiqueta: 'En stock',
                  valor: Fmt.dias(v.diasEnStock),
                  color: v.alerta.color(p),
                ),
              ),
              Expanded(
                child: _MiniDato(
                  etiqueta: 'Precio',
                  valor: Fmt.pesosCompacto(v.precioActual),
                ),
              ),
              Expanded(
                child: _MiniDato(
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
  const _MiniDato({required this.etiqueta, required this.valor, this.color});

  final String etiqueta, valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 10.5, color: p.tinta3)),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: color ?? p.tinta,
          ),
        ),
      ],
    );
  }
}
