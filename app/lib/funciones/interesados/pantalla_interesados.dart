import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import 'ficha_interesado.dart';
import 'alta_interesado.dart';
import 'eliminar_interesado.dart';

/// Pantalla de Clientes.
///
/// Sigue el diseño que entregó el cliente (Stitch, 09/2026): título con el
/// conteo, buscador ancho, pestañas con contador y una tarjeta por persona
/// con tres zonas (quién es · qué auto · cómo está en el BCRA).
///
/// La ruta sigue siendo /interesados y los datos son los mismos: lo que
/// cambió es cómo se ven y que ahora se puede buscar y ordenar.

/// Con quién estamos tratando. Es el eje del diseño: las pestañas de arriba.
enum _Pestana {
  todos('Todos'),
  compraron('Compraron'),
  interesados('Interesados');

  const _Pestana(this.etiqueta);
  final String etiqueta;
}

enum _Orden {
  recientes('Más recientes'),
  nombre('Nombre (A-Z)'),
  riesgo('Situación crediticia');

  const _Orden(this.etiqueta);
  final String etiqueta;
}

/// Filtro por color del semáforo. `null` significa "todos".
final _filtroProvider = NotifierProvider<_Filtro, SemaforoCrediticio?>(
  _Filtro.new,
);

class _Filtro extends Notifier<SemaforoCrediticio?> {
  @override
  SemaforoCrediticio? build() => null;

  void poner(SemaforoCrediticio? s) => state = s;
}

final _pestanaProvider = NotifierProvider<_PestanaActual, _Pestana>(
  _PestanaActual.new,
);

class _PestanaActual extends Notifier<_Pestana> {
  @override
  _Pestana build() => _Pestana.todos;

  void poner(_Pestana v) => state = v;
}

final _busquedaProvider = NotifierProvider<_Busqueda, String>(_Busqueda.new);

class _Busqueda extends Notifier<String> {
  @override
  String build() => '';

  void poner(String v) => state = v;
}

final _ordenProvider = NotifierProvider<_OrdenActual, _Orden>(_OrdenActual.new);

class _OrdenActual extends Notifier<_Orden> {
  @override
  _Orden build() => _Orden.recientes;

  void poner(_Orden v) => state = v;
}

/// Un cliente que ya compró tiene la oportunidad en "ganado". No hace falta
/// mirar las ventas: es el mismo dato, y así la pantalla no depende de otra
/// consulta que puede venir a destiempo.
bool _compro(Interesado i) => i.estadoOportunidad == 'ganado';

class PantallaInteresados extends ConsumerWidget {
  const PantallaInteresados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(interesadosProvider);
    final p = context.paleta;
    final margen = MediaQuery.sizeOf(context).width < Corte.tablet
        ? Esp.lg + 4
        : Esp.xxl;

    void nuevo() => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FormularioInteresado(),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar los clientes',
          descripcion: '$e',
        ),
        data: (todos) {
          if (todos.isEmpty) {
            return EstadoVacio(
              icono: Icons.people_outline,
              titulo: 'Sin clientes cargados',
              descripcion:
                  'Cuando cargues a alguien vas a poder consultarle la '
                  'situación en el BCRA y guardar su informe.',
              accion: FilledButton.icon(
                onPressed: nuevo,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Nuevo cliente'),
              ),
            );
          }

          final pestana = ref.watch(_pestanaProvider);
          final filtro = ref.watch(_filtroProvider);
          final busqueda = ref.watch(_busquedaProvider);
          final orden = ref.watch(_ordenProvider);

          final deLaPestana = todos
              .where(
                (i) => switch (pestana) {
                  _Pestana.todos => true,
                  _Pestana.compraron => _compro(i),
                  _Pestana.interesados => !_compro(i),
                },
              )
              .toList();

          var lista = deLaPestana
              .where((i) => filtro == null || i.semaforo == filtro)
              .where((i) => _coincide(i, busqueda))
              .toList();

          lista.sort(switch (orden) {
            _Orden.nombre => (a, b) => a.nombre.toLowerCase().compareTo(
              b.nombre.toLowerCase(),
            ),
            // Lo peor primero: es a quién hay que mirar antes de financiar.
            _Orden.riesgo => (a, b) => b.semaforo.index.compareTo(
              a.semaforo.index,
            ),
            _Orden.recientes => (a, b) => (b.fecha ?? DateTime(2000)).compareTo(
              a.fecha ?? DateTime(2000),
            ),
          });

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(interesadosProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, 120),
              children: [
                Aparecer(
                  child: CabeceraPantalla(
                    titulo: 'Clientes',
                    subtitulo:
                        '${todos.length} '
                        '${todos.length == 1 ? 'cliente en total' : 'clientes en total'}',
                    accion: FilledButton.icon(
                      onPressed: nuevo,
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 24,
                      ),
                      label: const Text('Nuevo cliente'),
                    ),
                  ),
                ),
                const SizedBox(height: Esp.lg),

                Aparecer(
                  indice: 1,
                  child: _BuscadorYOrden(
                    total: deLaPestana.length,
                    interesados: deLaPestana,
                  ),
                ),
                const SizedBox(height: Esp.md),

                Aparecer(
                  indice: 2,
                  child: Row(
                    children: [
                      Expanded(child: _Pestanas(interesados: todos)),
                      const SizedBox(width: Esp.sm),
                      // El criterio del semaforo decide si se financia o no:
                      // no puede quedar solo en la cabeza del que programo.
                      TextButton(
                        onPressed: () => _ExplicacionSemaforo.mostrar(context),
                        child: const Text('¿Qué significa cada color?'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Esp.md),

                const SizedBox(height: Esp.xs),

                if (lista.isEmpty)
                  Tarjeta(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Esp.xl,
                      vertical: Esp.xxl,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: p.superficieHundida,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_search_outlined,
                            size: 32,
                            color: p.tinta2,
                          ),
                        ),
                        const SizedBox(height: Esp.lg),
                        Text(
                          busqueda.isEmpty
                              ? 'Nadie está en "${filtro?.etiqueta ?? pestana.etiqueta}"'
                              : 'No encontramos clientes con ese criterio',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: Esp.sm),
                        Text(
                          busqueda.isEmpty
                              ? 'Probá con otra pestaña o sacando el filtro.'
                              : 'Probá escribiendo el nombre, el teléfono, el '
                                    'CUIT o la localidad.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: p.tinta2),
                        ),
                        const SizedBox(height: Esp.lg),
                        FilledButton(
                          onPressed: () {
                            ref.read(_busquedaProvider.notifier).poner('');
                            ref.read(_filtroProvider.notifier).poner(null);
                            ref
                                .read(_pestanaProvider.notifier)
                                .poner(_Pestana.todos);
                          },
                          child: const Text('Ver todos los clientes'),
                        ),
                      ],
                    ),
                  ),

                for (var i = 0; i < lista.length; i++) ...[
                  Aparecer(
                    indice: i + 4,
                    child: _TarjetaInteresado(interesado: lista[i]),
                  ),
                  const SizedBox(height: Esp.md),
                ],

                if (lista.isNotEmpty) ...[
                  const SizedBox(height: Esp.sm),
                  Center(
                    child: Text(
                      lista.length == deLaPestana.length
                          ? '${lista.length} ${lista.length == 1 ? 'persona' : 'personas'}'
                          : '${lista.length} de ${deLaPestana.length}',
                      style: TextStyle(fontSize: 14, color: p.tinta3),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Busca en todo lo que alguien puede recordar de un cliente: cómo se llama,
/// el teléfono que le anotó, el CUIT, de dónde es o qué auto vino a ver.
bool _coincide(Interesado i, String busqueda) {
  final q = busqueda.trim().toLowerCase();
  if (q.isEmpty) return true;
  final campos = [
    i.nombre,
    i.telefono ?? '',
    i.whatsapp ?? '',
    i.email ?? '',
    i.cuit ?? '',
    i.dni ?? '',
    i.localidad ?? '',
    i.provincia ?? '',
    i.vehiculoCodigo ?? '',
    i.vehiculoTitulo ?? '',
  ].join(' ').toLowerCase();
  // Sin separadores: se busca "20-12345678-9" escribiendo 20123456789.
  final plano = campos.replaceAll(RegExp(r'[\s.\-]'), '');
  final qPlano = q.replaceAll(RegExp(r'[\s.\-]'), '');
  return campos.contains(q) || plano.contains(qPlano);
}

class _BuscadorYOrden extends ConsumerStatefulWidget {
  const _BuscadorYOrden({required this.total, required this.interesados});

  final int total;

  /// La lista de la pestaña actual: el selector de situación muestra
  /// cuántos hay de cada color.
  final List<Interesado> interesados;

  @override
  ConsumerState<_BuscadorYOrden> createState() => _BuscadorYOrdenState();
}

class _BuscadorYOrdenState extends ConsumerState<_BuscadorYOrden> {
  final _controlador = TextEditingController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final busqueda = ref.watch(_busquedaProvider);
    // El provider puede limpiarse desde el estado vacío: el campo tiene que
    // enterarse, o queda mostrando lo que ya no filtra nada.
    if (busqueda.isEmpty && _controlador.text.isNotEmpty) _controlador.clear();

    final orden = ref.watch(_ordenProvider);
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final buscador = Buscador(
      texto: busqueda,
      controlador: _controlador,
      pista: 'Buscar por nombre, apellido, teléfono o patente...',
      onCambio: (v) => ref.read(_busquedaProvider.notifier).poner(v),
    );

    final selector = Container(
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.lg),
        border: Border.all(color: p.borde, width: 1.5),
      ),
      child: PopupMenuButton<_Orden>(
        tooltip: 'Ordenar la lista',
        initialValue: orden,
        onSelected: (v) => ref.read(_ordenProvider.notifier).poner(v),
        itemBuilder: (_) => [
          for (final o in _Orden.values)
            PopupMenuItem(value: o, child: Text(o.etiqueta)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.lg,
            vertical: Esp.lg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort_rounded, size: 22, color: p.tinta2),
              const SizedBox(width: Esp.sm),
              Text(
                'Ordenar: ${orden.etiqueta}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 22, color: p.tinta2),
            ],
          ),
        ),
      ),
    );

    final situacion = _SelectorSituacion(interesados: widget.interesados);

    return angosto
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buscador,
              const SizedBox(height: Esp.sm),
              Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [selector, situacion],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: buscador),
              const SizedBox(width: Esp.md),
              selector,
              const SizedBox(width: Esp.sm),
              situacion,
            ],
          );
  }
}

/// Las pestañas del diseño: con quién estoy tratando, y cuántos hay de cada.
class _Pestanas extends ConsumerWidget {
  const _Pestanas({required this.interesados});

  final List<Interesado> interesados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actual = ref.watch(_pestanaProvider);

    int contar(_Pestana p) => switch (p) {
      _Pestana.todos => interesados.length,
      _Pestana.compraron => interesados.where(_compro).length,
      _Pestana.interesados => interesados.where((i) => !_compro(i)).length,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in _Pestana.values) ...[
            ChipSeleccion(
              etiqueta: p.etiqueta,
              contador: contar(p),
              activo: actual == p,
              onTap: () => ref.read(_pestanaProvider.notifier).poner(p),
            ),
            if (p != _Pestana.values.last) const SizedBox(width: Esp.sm),
          ],
        ],
      ),
    );
  }
}

/// El filtro por situación crediticia, como desplegable.
///
/// En el diseño, la fila de filtros de esta pantalla son el buscador, el
/// orden y las pestañas. La situación del BCRA es el dato que decide si se
/// financia o no, así que sigue estando, pero como un desplegable más y no
/// como una fila aparte de pastillas.
class _SelectorSituacion extends ConsumerWidget {
  const _SelectorSituacion({required this.interesados});

  final List<Interesado> interesados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final actual = ref.watch(_filtroProvider);

    int contar(SemaforoCrediticio s) =>
        interesados.where((i) => i.semaforo == s).length;

    return Container(
      decoration: BoxDecoration(
        color: actual == null ? p.superficie : p.acentoLavado,
        borderRadius: BorderRadius.circular(Curva.lg),
        border: Border.all(
          color: actual == null ? p.borde : p.acento,
          width: 1.5,
        ),
      ),
      child: PopupMenuButton<SemaforoCrediticio?>(
        tooltip: 'Filtrar por situación en el BCRA',
        initialValue: actual,
        onSelected: (v) => ref.read(_filtroProvider.notifier).poner(v),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: null,
            child: Text('Todas las situaciones'),
          ),
          for (final s in SemaforoCrediticio.values)
            PopupMenuItem(
              value: s,
              child: Text('${s.etiqueta}  (${contar(s)})'),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.lg,
            vertical: Esp.lg,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: actual == null ? p.tinta3 : actual.color(p),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Esp.sm),
              Text(
                actual == null ? 'Situación: todas' : actual.etiqueta,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 22, color: p.tinta2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explica qué significa cada color. No es decorativo: el semáforo decide si
/// se le financia una compra a alguien, así que el criterio tiene que estar
/// a la vista y no escondido en la cabeza del que lo programó.
class _ExplicacionSemaforo extends StatelessWidget {
  const _ExplicacionSemaforo();

  /// Lo abre el enlace "¿Qué significa cada color?".
  static void mostrar(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(Esp.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: const SingleChildScrollView(child: _ExplicacionSemaforo()),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      destacada: true,
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.account_balance_rounded,
                tamano: 44,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Semáforo crediticio',
                  descripcion: 'Central de Deudores del BCRA',
                  sobreNegro: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),
          LayoutBuilder(
            builder: (context, restricciones) {
              final porFila = restricciones.maxWidth >= 700 ? 3 : 1;
              final ancho =
                  (restricciones.maxWidth - Esp.sm * (porFila - 1)) / porFila;
              return Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [
                  for (final (color, titulo, detalle) in [
                    (
                      p.bien,
                      'Situación normal',
                      'Situación 1, sin alertas informadas',
                    ),
                    (
                      p.observar,
                      'Con reparos',
                      'Situación 2 o 3, cheques pagados o mora',
                    ),
                    (
                      p.critico,
                      'Riesgo alto',
                      'Situación 4 a 6, cheques impagos o juicio',
                    ),
                  ])
                    SizedBox(
                      width: ancho,
                      child: _Criterio(
                        color: color,
                        titulo: titulo,
                        detalle: detalle,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Criterio extends StatelessWidget {
  const _Criterio({
    required this.color,
    required this.titulo,
    required this.detalle,
  });

  final Color color;
  final String titulo, detalle;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.negroBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: Esp.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.sobreNegro,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 14, color: p.sobreNegro2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La tarjeta del diseño, con sus tres zonas: quién es, qué auto y cómo está
/// en el BCRA. En celular las zonas se apilan; en escritorio van en fila.
class _TarjetaInteresado extends ConsumerWidget {
  const _TarjetaInteresado({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final i = interesado;
    final ancho = MediaQuery.sizeOf(context).width;
    final enFila = ancho >= Corte.escritorio;

    void abrir() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FichaInteresado(interesado: i)));

    final quien = _Quien(interesado: i);
    final auto = _AutoYEstado(interesado: i);
    final estado = _ZonaSemaforo(interesado: i, onVer: abrir);

    return Tarjeta(
      onTap: abrir,
      padding: const EdgeInsets.all(Esp.xl - 2),
      child: enFila
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 300, child: quien),
                Container(
                  width: 1.5,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: Esp.lg),
                  color: p.borde,
                ),
                Expanded(child: auto),
                const SizedBox(width: Esp.lg),
                estado,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                quien,
                const SizedBox(height: Esp.md),
                Divider(color: p.borde, height: 1.5, thickness: 1.5),
                const SizedBox(height: Esp.md),
                auto,
                const SizedBox(height: Esp.md),
                estado,
              ],
            ),
    );
  }
}

class _Quien extends ConsumerWidget {
  const _Quien({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final i = interesado;
    final iniciales = i.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .take(2)
        .map((x) => x[0].toUpperCase())
        .join();

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: i.semaforo.lavado(p),
            shape: BoxShape.circle,
            border: Border.all(
              color: i.semaforo.color(p).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Text(
            iniciales.isEmpty ? '?' : iniciales,
            style: TextStyle(
              fontFamily: TemaApp.titulo,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: i.semaforo.color(p),
            ),
          ),
        ),
        const SizedBox(width: Esp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (i.telefono != null && i.telefono!.isNotEmpty) i.telefono!,
                  if (i.localidad != null && i.localidad!.isNotEmpty)
                    i.localidad!,
                  if ((i.telefono ?? '').isEmpty && (i.localidad ?? '').isEmpty)
                    'Sin datos de contacto',
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: p.tinta2),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Acciones de ${i.nombre}',
          icon: const Icon(Icons.more_vert_rounded, size: 24),
          onSelected: (accion) async {
            if (accion == 'ver') {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FichaInteresado(interesado: i),
                ),
              );
            } else if (accion == 'eliminar') {
              await eliminarInteresadoConConfirmacion(context, ref, i);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'ver',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.badge_outlined),
                title: Text('Ver ficha'),
              ),
            ),
            PopupMenuItem(
              value: 'eliminar',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('Eliminar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// La zona del medio: qué auto compró o vino a ver, y desde cuándo.
class _AutoYEstado extends StatelessWidget {
  const _AutoYEstado({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;
    final compro = _compro(i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          compro ? 'COMPRÓ' : 'INTERESADO EN',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: Esp.xs),
        Row(
          children: [
            Icon(
              compro
                  ? Icons.check_circle_outline_rounded
                  : Icons.directions_car_filled_outlined,
              size: 22,
              color: compro ? p.bien : p.tinta2,
            ),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Text(
                i.vehiculoTitulo == null
                    ? 'Todavía sin unidad definida'
                    : '${i.vehiculoCodigo} · ${i.vehiculoTitulo}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: i.vehiculoTitulo == null ? p.tinta3 : p.tinta,
                ),
              ),
            ),
          ],
        ),
        if (i.fecha != null) ...[
          const SizedBox(height: Esp.xs),
          Text(
            '${compro ? 'Cerrado' : 'Anotado'} el ${Fmt.fecha(i.fecha)}',
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 14,
              color: p.tinta3,
            ),
          ),
        ],
      ],
    );
  }
}

/// La zona de la derecha: la pastilla del semáforo y en qué punto está la
/// evaluación crediticia.
class _ZonaSemaforo extends StatelessWidget {
  const _ZonaSemaforo({required this.interesado, required this.onVer});

  final Interesado interesado;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;
    final c = i.consulta;

    final (IconData icono, String texto, Color color) = switch (c) {
      null when !i.tieneCuit => (
        Icons.badge_outlined,
        'Falta el CUIT para consultar',
        p.tinta3,
      ),
      null => (Icons.search_rounded, 'Sin consultar', p.observar),
      _ when c.vencida => (
        Icons.update_rounded,
        'Consulta del ${Fmt.fecha(c.consultadoEl)}',
        p.observar,
      ),
      _ when c.sinDeudasInformadas => (
        Icons.verified_outlined,
        'Sin deudas informadas',
        p.bien,
      ),
      _ => (
        Icons.account_balance_outlined,
        '${c.entidades.length} '
            '${c.entidades.length == 1 ? 'entidad' : 'entidades'} · '
            '${Fmt.pesosCompacto(c.totalDeuda)}',
        p.tinta2,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Pastilla(
          texto: i.semaforo.etiqueta,
          color: i.semaforo.color(p),
          lavado: i.semaforo.lavado(p),
        ),
        const SizedBox(height: Esp.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: Esp.sm - 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: color),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
