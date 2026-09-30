import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/gastos.dart';
import '../../dominio/modelos.dart';
import '../../dominio/ventas.dart';
import '../../ui/componentes.dart';

/// Inicio, calcado de la pantalla "Inicio · búsqueda rápida de revista" del
/// diseño: arriba el saludo con el buscador de revista y el resumen del mes;
/// abajo, lo que hay para atender hoy al lado de cómo vienen las ventas; y
/// al final, los autos publicados.
class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventario = ref.watch(inventarioProvider);

    return inventario.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar el panel',
        descripcion: '$e',
      ),
      data: (inv) => _Contenido(inventario: inv),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.inventario});

  final List<VehiculoInventario> inventario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esMovil = ancho < Corte.tablet;
    final dosColumnas = ancho >= Corte.escritorio;
    final margen = esMovil ? Esp.lg + 4 : Esp.xxl;

    final ventas = ref.watch(ventasProvider).value ?? const <Venta>[];
    final gastos = ref.watch(gastosProvider).value ?? const <Gasto>[];
    final interesados =
        ref.watch(interesadosProvider).value ?? const <Interesado>[];

    final pendientes = _pendientes(context, inventario, interesados);
    final atender = _ParaAtenderHoy(pendientes: pendientes);
    final ventasMes = _ComoVienenLasVentas(ventas: ventas);

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, Esp.xxl),
      children: [
        Aparecer(
          child: _Saludo(
            usuario: ref.watch(usuarioProvider),
            agencia: ref.watch(miAgenciaProvider).value?.nombre,
            ventas: ventas,
            gastos: gastos,
            pendientes: pendientes.length,
          ),
        ),
        const SizedBox(height: Esp.lg + 2),

        if (dosColumnas)
          // Sin IntrinsicHeight: adentro de "Para atender hoy" hay un
          // LayoutBuilder (cada pendiente se acomoda segun el ancho), y un
          // LayoutBuilder no sabe decir cuanto mide de alto antes de medirse.
          Aparecer(
            indice: 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: atender),
                const SizedBox(width: Esp.lg + 2),
                Expanded(child: ventasMes),
              ],
            ),
          )
        else ...[
          Aparecer(indice: 1, child: atender),
          const SizedBox(height: Esp.lg + 2),
          Aparecer(indice: 2, child: ventasMes),
        ],

        const SizedBox(height: Esp.lg + 2),
        Aparecer(indice: 3, child: _AutosEnVenta(inventario: inventario)),
      ],
    );
  }

  /// Lo que hay para atender hoy, sacado de lo que ya está cargado.
  ///
  /// El diseño muestra cuotas atrasadas y reservas por vencer; eso llega con
  /// las tandas de cobranzas y reservas. Hasta entonces la lista se arma con
  /// lo que el sistema sí sabe: acciones anotadas que vencieron, unidades
  /// pasadas de plazo y consultas al BCRA vencidas.
  static List<_Pendiente> _pendientes(
    BuildContext context,
    List<VehiculoInventario> inventario,
    List<Interesado> interesados,
  ) {
    final p = context.paleta;
    final hoy = DateTime.now();
    final dia = DateTime(hoy.year, hoy.month, hoy.day);
    final lista = <_Pendiente>[];

    for (final i in interesados) {
      final cuando = i.proximaAccionFecha;
      if (cuando == null || i.proximaAccion == null) continue;
      if (cuando.isAfter(dia)) continue;
      final atraso = dia
          .difference(DateTime(cuando.year, cuando.month, cuando.day))
          .inDays;
      final conTelefono = (i.telefono ?? '').isNotEmpty;
      lista.add(
        _Pendiente(
          icono: Icons.alarm_rounded,
          color: atraso > 0 ? p.critico : p.observar,
          titulo: i.nombre,
          plazo: atraso == 0 ? 'Para hoy' : '${Fmt.dias(atraso)} de atraso',
          detalle: i.proximaAccion!,
          accion: conTelefono ? 'Enviar WhatsApp' : 'Ver ficha',
          iconoAccion: conTelefono
              ? Icons.chat_rounded
              : Icons.drive_file_rename_outline,
          verde: conTelefono,
          onAccion: () => conTelefono
              ? _abrirWhatsApp(i.telefono!)
              : context.go('/interesados'),
          urgencia: 200 + atraso,
        ),
      );
    }

    final paradas =
        inventario
            .where((v) => !v.vendido && v.alerta == AlertaRotacion.critico)
            .toList()
          ..sort((a, b) => b.diasEnStock.compareTo(a.diasEnStock));
    for (final v in paradas.take(3)) {
      lista.add(
        _Pendiente(
          icono: Icons.hourglass_top_rounded,
          color: p.critico,
          titulo: '${v.titulo}${v.patente == null ? '' : ' (${v.patente})'}',
          plazo: '${v.diasEnStock} días en salón',
          detalle:
              'Lleva ${Fmt.dias(v.diasEnStock)} sin venderse. Sugerimos '
              'revisar precio o publicarla destacada.',
          accion: 'Ver ficha',
          iconoAccion: Icons.drive_file_rename_outline,
          onAccion: () => context.go('/inventario/${v.id}'),
          urgencia: 100 + v.diasEnStock,
        ),
      );
    }

    for (final i
        in interesados.where((x) => x.consulta?.vencida == true).take(2)) {
      lista.add(
        _Pendiente(
          icono: Icons.update_rounded,
          color: p.observar,
          titulo: i.nombre,
          plazo: 'Consulta vencida',
          detalle:
              'La consulta al BCRA quedó vieja. Conviene repetirla antes de '
              'ofrecerle financiación.',
          accion: 'Ver ficha',
          iconoAccion: Icons.drive_file_rename_outline,
          onAccion: () => context.go('/interesados'),
          urgencia: 50,
        ),
      );
    }

    lista.sort((a, b) => b.urgencia.compareTo(a.urgencia));
    return lista.take(4).toList();
  }

  static Future<void> _abrirWhatsApp(String telefono) async {
    final numero = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$numero'),
      mode: LaunchMode.externalApplication,
    );
  }
}

// ---------------------------------------------------------------------------
// El saludo: la tarjeta oscura de arriba, con el buscador y el mes
// ---------------------------------------------------------------------------

class _Saludo extends StatefulWidget {
  const _Saludo({
    required this.usuario,
    required this.agencia,
    required this.ventas,
    required this.gastos,
    required this.pendientes,
  });

  final Usuario? usuario;
  final String? agencia;
  final List<Venta> ventas;
  final List<Gasto> gastos;
  final int pendientes;

  @override
  State<_Saludo> createState() => _SaludoState();
}

class _SaludoState extends State<_Saludo> {
  final _busqueda = TextEditingController();
  int? _anio;

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _verPrecio() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La guía de precios todavía no está conectada. Mientras tanto, el '
          'valor de referencia se carga a mano en la ficha de cada unidad.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final hoy = DateTime.now();
    final desde = DateTime(hoy.year, hoy.month, 1);
    final mesPasado = DateTime(hoy.year, hoy.month - 1, 1);

    final delMes = widget.ventas
        .where((v) => !v.fechaVenta.isBefore(desde))
        .toList();
    final delMesPasado = widget.ventas
        .where(
          (v) =>
              v.fechaVenta.isBefore(desde) && !v.fechaVenta.isBefore(mesPasado),
        )
        .toList();

    final ganancia = delMes.fold<double>(
      0,
      (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
    );
    final gananciaPasada = delMesPasado.fold<double>(
      0,
      (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
    );
    final delMesGastos = widget.gastos
        .where((g) => !g.fecha.isBefore(desde))
        .toList();
    final gastoMes = delMesGastos.fold<double>(0, (s, g) => s + g.importe);

    final saludo = hoy.hour < 13
        ? 'Buen día'
        : hoy.hour < 20
        ? 'Buenas tardes'
        : 'Buenas noches';
    final nombre = (widget.usuario?.nombre ?? '').split(' ').first;
    final nombreMesPasado = Fmt.mes(mesPasado);

    return Tarjeta(
      destacada: true,
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _encabezado(context, saludo, nombre),
          const SizedBox(height: Esp.lg),
          Divider(color: p.negroBorde, height: 1),
          const SizedBox(height: Esp.lg),
          _buscadorRevista(context),
          const SizedBox(height: Esp.lg),
          LayoutBuilder(
            builder: (context, r) {
              final tarjetas = [
                _TarjetaMes(
                  titulo: 'Vendidos este mes',
                  valor:
                      '${delMes.length} ${delMes.length == 1 ? 'auto' : 'autos'}',
                  icono: Icons.task_alt_rounded,
                  colorIcono: p.bien,
                  nota: _comparar(
                    delMes.length,
                    delMesPasado.length,
                    nombreMesPasado,
                  ),
                  iconoNota: delMes.length >= delMesPasado.length
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  colorNota: delMes.length >= delMesPasado.length
                      ? p.bien
                      : p.critico,
                ),
                _TarjetaMes(
                  titulo: 'Ganancia del mes',
                  valor: Fmt.pesos(ganancia),
                  icono: Icons.payments_outlined,
                  colorIcono: p.acentoTexto,
                  nota: gananciaPasada == 0
                      ? 'Ganancia real, ajustada por dólar'
                      : ganancia >= gananciaPasada
                      ? 'Mejor que $nombreMesPasado'
                      : 'Por debajo de $nombreMesPasado',
                  iconoNota: ganancia >= gananciaPasada
                      ? Icons.trending_up_rounded
                      : Icons.horizontal_rule_rounded,
                  colorNota: ganancia >= gananciaPasada ? p.bien : p.observar,
                ),
                _TarjetaMes(
                  titulo: 'Gastos del mes',
                  valor: Fmt.pesos(gastoMes),
                  valorRojo: true,
                  icono: Icons.error_outline_rounded,
                  colorIcono: p.critico,
                  nota: delMesGastos.isEmpty
                      ? 'Todavía no cargaste gastos este mes'
                      : '${delMesGastos.length} '
                            '${delMesGastos.length == 1 ? 'comprobante cargado' : 'comprobantes cargados'}',
                  iconoNota: Icons.circle,
                  colorNota: p.critico,
                ),
              ];
              return r.maxWidth >= 760
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tarjetas.length; i++) ...[
                            if (i > 0) const SizedBox(width: Esp.md),
                            Expanded(child: tarjetas[i]),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < tarjetas.length; i++) ...[
                          if (i > 0) const SizedBox(height: Esp.md),
                          tarjetas[i],
                        ],
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  static String _comparar(int ahora, int antes, String mesPasado) {
    if (antes == 0) return 'En $mesPasado no hubo entregas';
    if (ahora == antes) return 'Igual que en $mesPasado';
    final variacion = ((ahora - antes) / antes * 100).round();
    final diferencia = (ahora - antes).abs();
    return ahora > antes
        ? '$diferencia más que en $mesPasado (+$variacion%)'
        : '$diferencia menos que en $mesPasado ($variacion%)';
  }

  Widget _encabezado(BuildContext context, String saludo, String nombre) {
    final p = context.paleta;

    final marca = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.acento,
            borderRadius: BorderRadius.circular(Curva.md),
          ),
          child: Icon(
            Icons.directions_car_filled_rounded,
            size: 24,
            color: p.acentoTinta,
          ),
        ),
        const SizedBox(width: Esp.md),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.agencia ?? 'Mi Agencia',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: TemaApp.titulo,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.sobreNegro,
                ),
              ),
              Text(
                'Gestión de Agencia',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.sobreNegro2),
              ),
            ],
          ),
        ),
      ],
    );

    final saludoTexto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Fmt.fechaLarga(DateTime.now()).toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: p.acento,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          nombre.isEmpty ? '¡$saludo!' : '¡$saludo, $nombre!',
          style: TextStyle(
            fontFamily: TemaApp.titulo,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: p.sobreNegro,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.pendientes == 0
              ? 'Tenés el local al día: no hay nada pendiente.'
              : 'Tenés ${widget.pendientes} '
                    '${widget.pendientes == 1 ? 'cosa' : 'cosas'} para atender hoy.',
          style: TextStyle(fontSize: 15, color: p.sobreNegro2),
        ),
      ],
    );

    final usuario = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.md,
        vertical: Esp.sm + 2,
      ),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.negroBorde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: p.acento, shape: BoxShape.circle),
            child: Center(
              child: Text(
                widget.usuario?.iniciales ?? '?',
                style: TextStyle(
                  fontFamily: TemaApp.titulo,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.acentoTinta,
                ),
              ),
            ),
          ),
          const SizedBox(width: Esp.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.usuario?.nombre ?? 'Usuario',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.sobreNegro,
                  ),
                ),
                Text(
                  _rol(widget.usuario?.rol),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.acento,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, r) {
        if (r.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Esp.md,
                runSpacing: Esp.md,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [marca, usuario],
              ),
              const SizedBox(height: Esp.lg),
              saludoTexto,
            ],
          );
        }
        return Row(
          children: [
            marca,
            const SizedBox(width: Esp.xl),
            Expanded(child: Center(child: saludoTexto)),
            const SizedBox(width: Esp.xl),
            usuario,
          ],
        );
      },
    );
  }

  static String _rol(String? rol) => switch (rol) {
    'owner' => 'Titular',
    'admin' => 'Administrador',
    'vendedor' => 'Vendedor',
    _ => 'Equipo',
  };

  /// El buscador de precio de revista del diseño. La guía todavía no está
  /// conectada: el campo existe y lo avisa, en vez de inventar un precio.
  Widget _buscadorRevista(BuildContext context) {
    final p = context.paleta;

    final campo = TextField(
      controller: _busqueda,
      onSubmitted: (_) => _verPrecio(),
      style: TextStyle(fontSize: 16, color: p.tinta),
      decoration: InputDecoration(
        hintText:
            'Buscá el precio de revista de cualquier auto... (ej: Hilux SRV)',
        filled: true,
        fillColor: p.superficie,
        prefixIcon: Icon(Icons.search_rounded, size: 24, color: p.tinta3),
      ),
    );

    final anio = Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: Esp.md),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _anio,
          isExpanded: true,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: 20, color: p.tinta2),
              const SizedBox(width: Esp.sm),
              Flexible(
                child: Text(
                  'Año',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: p.tinta2),
                ),
              ),
            ],
          ),
          icon: Icon(Icons.expand_more_rounded, color: p.tinta2),
          borderRadius: BorderRadius.circular(Curva.md),
          dropdownColor: p.superficieElevada,
          style: TextStyle(fontSize: 16, color: p.tinta),
          items: [
            const DropdownMenuItem(value: null, child: Text('Cualquier año')),
            for (
              var a = DateTime.now().year;
              a >= DateTime.now().year - 15;
              a--
            )
              DropdownMenuItem(value: a, child: Text('$a')),
          ],
          onChanged: (v) => setState(() => _anio = v),
        ),
      ),
    );

    final boton = FilledButton.icon(
      onPressed: _verPrecio,
      icon: const Icon(Icons.search_rounded, size: 22),
      label: const Text('Ver precio'),
    );

    return LayoutBuilder(
      builder: (context, r) => r.maxWidth >= 760
          ? Row(
              children: [
                Expanded(child: campo),
                const SizedBox(width: Esp.md),
                // Ancho fijo: el desplegable se estira hasta donde le dejen,
                // y en una fila sin limite eso es infinito.
                SizedBox(width: 190, child: anio),
                const SizedBox(width: Esp.md),
                boton,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                campo,
                const SizedBox(height: Esp.md),
                anio,
                const SizedBox(height: Esp.md),
                boton,
              ],
            ),
    );
  }
}

/// Una de las tres tarjetas del mes, adentro de la tarjeta oscura.
class _TarjetaMes extends StatelessWidget {
  const _TarjetaMes({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.colorIcono,
    required this.nota,
    required this.iconoNota,
    required this.colorNota,
    this.valorRojo = false,
  });

  final String titulo, valor, nota;
  final IconData icono, iconoNota;
  final Color colorIcono, colorNota;
  final bool valorRojo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md + 2),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo.toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: p.tinta3,
                  ),
                ),
              ),
              IconoEnCirculo(
                icono: icono,
                tamano: 34,
                color: colorIcono,
                fondo: colorIcono.withValues(alpha: 0.14),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: TemaApp.titulo,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: valorRojo ? p.critico : p.tinta,
              ),
            ),
          ),
          const SizedBox(height: Esp.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: Esp.sm + 2,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colorNota.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Curva.sm),
            ),
            child: Row(
              children: [
                Icon(iconoNota, size: 16, color: colorNota),
                const SizedBox(width: Esp.sm - 2),
                Expanded(
                  child: Text(
                    nota,
                    style: TextStyle(fontSize: 14, color: colorNota),
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
// Para atender hoy
// ---------------------------------------------------------------------------

class _Pendiente {
  _Pendiente({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.plazo,
    required this.detalle,
    required this.accion,
    required this.iconoAccion,
    required this.onAccion,
    required this.urgencia,
    this.verde = false,
  });

  final IconData icono, iconoAccion;
  final Color color;
  final String titulo, plazo, detalle, accion;
  final VoidCallback onAccion;
  final bool verde;

  /// Cuánto urge: más alto, más arriba.
  final int urgencia;
}

class _ParaAtenderHoy extends StatelessWidget {
  const _ParaAtenderHoy({required this.pendientes});

  final List<_Pendiente> pendientes;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Esp.sm,
            runSpacing: Esp.xs,
            children: [
              Text(
                'Para atender hoy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (pendientes.isNotEmpty)
                Pastilla(
                  texto:
                      '${pendientes.length} '
                      '${pendientes.length == 1 ? 'pendiente' : 'pendientes'}',
                  color: p.observar,
                  lavado: p.observarLavado,
                ),
              Text(
                'Prioridad por vencimiento',
                style: TextStyle(fontSize: 14, color: p.tinta3),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          if (pendientes.isEmpty)
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.bienLavado,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 24, color: p.bien),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      'Ninguna unidad pasada de plazo y ninguna acción vencida '
                      'con los clientes.',
                      style: TextStyle(fontSize: 15, color: p.tinta2),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final x in pendientes) ...[
              _FilaPendiente(pendiente: x),
              const SizedBox(height: Esp.sm),
            ],
          const SizedBox(height: Esp.xs),
          const _AgendarTarea(),
        ],
      ),
    );
  }
}

class _FilaPendiente extends StatelessWidget {
  const _FilaPendiente({required this.pendiente});

  final _Pendiente pendiente;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final x = pendiente;

    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Esp.sm,
          runSpacing: Esp.xs,
          children: [
            Text(
              x.titulo,
              style: TextStyle(
                fontFamily: TemaApp.titulo,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: p.tinta,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Esp.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: x.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Curva.sm),
              ),
              child: Text(
                x.plazo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: x.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          x.detalle,
          style: TextStyle(fontSize: 15, color: p.tinta2, height: 1.35),
        ),
      ],
    );

    final boton = x.verde
        ? FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.bien,
              foregroundColor: Colors.white,
            ),
            onPressed: x.onAccion,
            icon: Icon(x.iconoAccion, size: 20),
            label: Text(x.accion),
          )
        : OutlinedButton.icon(
            onPressed: x.onAccion,
            icon: Icon(x.iconoAccion, size: 20),
            label: Text(x.accion),
          );

    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.borde, width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, r) {
          final icono = IconoEnCirculo(
            icono: x.icono,
            tamano: 42,
            color: x.color,
            fondo: x.color.withValues(alpha: 0.14),
          );
          return r.maxWidth >= 560
              ? Row(
                  children: [
                    icono,
                    const SizedBox(width: Esp.md),
                    Expanded(child: texto),
                    const SizedBox(width: Esp.md),
                    boton,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icono,
                        const SizedBox(width: Esp.md),
                        Expanded(child: texto),
                      ],
                    ),
                    const SizedBox(height: Esp.md),
                    boton,
                  ],
                );
        },
      ),
    );
  }
}

/// La caja punteada del diseño. La agenda llega en la tanda siguiente: el
/// lugar está, y al tocarlo dice con todas las letras que todavía no guarda.
class _AgendarTarea extends StatelessWidget {
  const _AgendarTarea();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return InkWell(
      borderRadius: BorderRadius.circular(Curva.md),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La agenda de tareas es lo próximo que entra. Por ahora acá '
            'aparece solo lo que el sistema puede deducir solo.',
          ),
        ),
      ),
      child: BordePunteado(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Esp.lg),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_calendar_outlined,
                    size: 22,
                    color: p.acentoTexto,
                  ),
                  const SizedBox(width: Esp.sm),
                  Text(
                    'Agendar una tarea',
                    style: TextStyle(
                      fontFamily: TemaApp.titulo,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.tinta,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Llamar, cobrar, entregar un auto o lo que necesites',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.tinta3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cómo vienen las ventas
// ---------------------------------------------------------------------------

class _ComoVienenLasVentas extends StatelessWidget {
  const _ComoVienenLasVentas({required this.ventas});

  final List<Venta> ventas;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final hoy = DateTime.now();

    final serie = [
      for (var i = 5; i >= 0; i--)
        () {
          final mes = DateTime(hoy.year, hoy.month - i, 1);
          final delMes = ventas.where(
            (v) =>
                v.fechaVenta.year == mes.year &&
                v.fechaVenta.month == mes.month,
          );
          return (
            mes: mes,
            unidades: delMes.length,
            ganancia: delMes.fold<double>(
              0,
              (s, v) => s + (v.gananciaReal ?? v.ganancia ?? 0),
            ),
          );
        }(),
    ];

    final maximo = serie.fold<int>(
      0,
      (m, x) => x.unidades > m ? x.unidades : m,
    );
    final total = serie.fold<int>(0, (s, x) => s + x.unidades);
    final promedio = total / serie.length;
    final actual = serie.last;
    final anterior = serie[serie.length - 2];
    final mejora = actual.unidades >= anterior.unidades;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cómo vienen las ventas',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Evolución de entregas en los últimos 6 meses',
                      style: TextStyle(fontSize: 15, color: p.tinta2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Esp.sm),
              if (total > 0)
                Flexible(
                  child: Pastilla(
                    texto: mejora
                        ? '${Fmt.mes(actual.mes)} viene mejor que ${Fmt.mes(anterior.mes)}'
                        : '${Fmt.mes(actual.mes)} viene por debajo de ${Fmt.mes(anterior.mes)}',
                    color: mejora ? p.bien : p.observar,
                    lavado: mejora ? p.bienLavado : p.observarLavado,
                    icono: mejora
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Esp.xl),
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final x in serie) ...[
                  Expanded(
                    child: _BarraMes(
                      unidades: x.unidades,
                      ganancia: x.ganancia,
                      maximo: maximo < 1 ? 1 : maximo,
                      etiqueta: Fmt.mes(x.mes),
                      actual: x == actual,
                    ),
                  ),
                  if (x != serie.last) const SizedBox(width: Esp.sm),
                ],
              ],
            ),
          ),
          Divider(color: p.borde, height: Esp.xl),
          Wrap(
            spacing: Esp.lg,
            runSpacing: Esp.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Referencia(color: p.bordeFuerte, texto: 'Meses anteriores'),
              _Referencia(
                color: p.acento,
                texto: 'Mes en curso (${Fmt.mes(actual.mes)})',
              ),
              Text(
                'Promedio semestral: ${promedio.toStringAsFixed(1)} unidades/mes',
                style: TextStyle(fontSize: 14, color: p.tinta3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarraMes extends StatelessWidget {
  const _BarraMes({
    required this.unidades,
    required this.ganancia,
    required this.maximo,
    required this.etiqueta,
    required this.actual,
  });

  final int unidades, maximo;
  final double ganancia;
  final String etiqueta;
  final bool actual;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // El globito sobre la barra del mes en curso, como en el diseño.
        if (actual && unidades > 0)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Esp.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: p.negro,
              borderRadius: BorderRadius.circular(Curva.sm),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${Fmt.pesosCompacto(ganancia)} · $unidades '
                '${unidades == 1 ? 'auto' : 'autos'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.sobreNegro,
                ),
              ),
            ),
          )
        else
          Text(
            '$unidades',
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: p.tinta2,
            ),
          ),
        const SizedBox(height: Esp.xs),
        Expanded(
          child: LayoutBuilder(
            builder: (context, r) {
              final alto = unidades == 0
                  ? 4.0
                  : r.maxHeight * unidades / maximo;
              return Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: Duracion.lenta,
                  curve: Curves.easeOutCubic,
                  height: alto,
                  decoration: BoxDecoration(
                    color: actual ? p.acento : p.bordeFuerte,
                    borderRadius: BorderRadius.circular(Curva.sm),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Esp.sm),
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 14,
            fontWeight: actual ? FontWeight.w700 : FontWeight.w400,
            color: actual ? p.tinta : p.tinta3,
          ),
        ),
      ],
    );
  }
}

class _Referencia extends StatelessWidget {
  const _Referencia({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: Esp.sm - 2),
        Text(texto, style: TextStyle(fontSize: 14, color: p.tinta3)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tus autos en venta
// ---------------------------------------------------------------------------

class _AutosEnVenta extends StatelessWidget {
  const _AutosEnVenta({required this.inventario});

  final List<VehiculoInventario> inventario;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final enStock = inventario.where((v) => !v.vendido).toList()
      ..sort((a, b) => a.diasEnStock.compareTo(b.diasEnStock));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tus autos en venta',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unidades publicadas y listas para mostrar',
                    style: TextStyle(fontSize: 15, color: p.tinta2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Esp.sm),
            TextButton.icon(
              onPressed: () => context.go('/inventario'),
              icon: Text('Ver todos (${enStock.length})'),
              label: const Icon(Icons.chevron_right_rounded, size: 22),
            ),
          ],
        ),
        const SizedBox(height: Esp.md),
        if (enStock.isEmpty)
          Tarjeta(
            padding: const EdgeInsets.all(Esp.xl),
            child: Text(
              'Todavía no hay unidades en stock. Cargá la primera con el '
              'botón "+" de la barra de abajo.',
              style: TextStyle(fontSize: 15, color: p.tinta2),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, r) {
              final columnas = r.maxWidth >= 1080
                  ? 4
                  : r.maxWidth >= 760
                  ? 3
                  : r.maxWidth >= 460
                  ? 2
                  : 1;
              final ancho = (r.maxWidth - Esp.md * (columnas - 1)) / columnas;
              return Wrap(
                spacing: Esp.md,
                runSpacing: Esp.md,
                children: [
                  for (final v in enStock.take(columnas))
                    SizedBox(
                      width: ancho,
                      child: _TarjetaAuto(vehiculo: v),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _TarjetaAuto extends StatelessWidget {
  const _TarjetaAuto({required this.vehiculo});

  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final reservado = v.estado == EstadoVehiculo.reservado;

    return Tarjeta(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/inventario/${v.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La foto, con el estado arriba a la izquierda y la patente abajo a
          // la derecha, como en el diseño.
          Stack(
            children: [
              SizedBox(
                height: 132,
                width: double.infinity,
                child: FotoPortada(
                  vehiculoId: v.id,
                  alto: 132,
                  radio: Curva.lg,
                  colorVacio: v.alerta.color(p),
                  fondoVacio: v.alerta.lavado(p),
                ),
              ),
              Positioned(
                top: Esp.sm,
                left: Esp.sm,
                child: Pastilla(
                  texto: reservado ? 'Reservado' : 'Disponible',
                  color: reservado ? p.observar : p.bien,
                  lavado: p.superficie,
                ),
              ),
              if (v.patente != null && v.patente!.isNotEmpty)
                Positioned(
                  bottom: Esp.sm,
                  right: Esp.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Esp.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: p.negro,
                      borderRadius: BorderRadius.circular(Curva.sm),
                    ),
                    child: Text(
                      v.patente!.toUpperCase(),
                      style: TextStyle(
                        fontFamily: TemaApp.titulo,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: p.sobreNegro,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(Esp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${v.anio}${v.km == null ? '' : ' · ${Fmt.km(v.km)}'}',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                const SizedBox(height: 2),
                Text(
                  v.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: TemaApp.titulo,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.tinta,
                  ),
                ),
                Text(
                  v.version ?? v.codigo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.tinta2),
                ),
                Divider(color: p.borde, height: Esp.lg),
                Text(
                  reservado ? 'Valor acordado' : 'Precio contado',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.pesos(v.precioActual),
                    style: TextStyle(
                      fontFamily: TemaApp.titulo,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: p.tinta,
                    ),
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
