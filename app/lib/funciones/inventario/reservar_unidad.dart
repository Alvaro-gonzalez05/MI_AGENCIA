import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/papeles.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Reservar una unidad: a nombre de quién, cuánto dejó de seña y hasta
/// cuándo se le guarda.
///
/// El plazo es obligatorio a propósito. Una reserva sin fecha es un auto
/// parado por tiempo indefinido con una seña chica adelante, que es la forma
/// más común de perder una venta sin darse cuenta.
class HojaReserva extends ConsumerStatefulWidget {
  const HojaReserva({super.key, required this.vehiculo, this.reserva});

  final VehiculoInventario vehiculo;

  /// Si ya está reservada, se muestra para cancelarla o darla por cerrada.
  final Reserva? reserva;

  /// Abre la hoja y devuelve true si algo cambió.
  static Future<bool> abrir(
    BuildContext context, {
    required VehiculoInventario vehiculo,
    Reserva? reserva,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (_) => HojaReserva(vehiculo: vehiculo, reserva: reserva),
      ) ??
      false;

  @override
  ConsumerState<HojaReserva> createState() => _HojaReservaState();
}

class _HojaReservaState extends ConsumerState<HojaReserva> {
  String _nombre = '';
  String _telefono = '';
  String? _oportunidadId;
  double _senia = 0;
  late DateTime _vence = DateTime.now().add(const Duration(days: 7));
  String _notas = '';

  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _error;

  Future<void> _reservar() async {
    final alta = AltaReserva(
      vehiculoId: widget.vehiculo.id,
      clienteNombre: _nombre,
      clienteTelefono: _telefono.isEmpty ? null : _telefono,
      oportunidadId: _oportunidadId,
      senia: _senia,
      venceEl: _vence,
      notas: _notas,
    );
    final errores = alta.validar();
    setState(() {
      _errores = errores;
      _error = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearReserva(alta);
      _refrescar();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = _mensaje(e);
      });
    }
  }

  Future<void> _cerrar(EstadoReserva estado) async {
    setState(() => _guardando = true);
    try {
      await ref
          .read(repositorioProvider)
          .cerrarReserva(widget.reserva!.id, estado);
      _refrescar();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = _mensaje(e);
      });
    }
  }

  /// La reserva cambia el estado de la unidad: hay que recargar el
  /// inventario, no solo la ficha.
  void _refrescar() {
    ref
      ..invalidate(inventarioProvider)
      ..invalidate(reservasProvider)
      ..invalidate(reservaDeProvider(widget.vehiculo.id));
  }

  static String _mensaje(Object e) {
    final t = e.toString();
    if (t.contains('reservas_una_activa')) {
      return 'Esta unidad ya tiene una reserva activa.';
    }
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'No tenés permiso para reservar unidades.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá internet y probá de nuevo.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = widget.vehiculo;
    final r = widget.reserva;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r == null ? 'Reservar unidad' : 'Reserva activa',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '${v.titulo}${v.patente == null ? '' : ' · ${v.patente}'}',
            style: TextStyle(fontSize: 15, color: p.tinta2),
          ),
          const SizedBox(height: Esp.lg),

          if (_error != null) ...[
            AvisoError(mensaje: _error!),
            const SizedBox(height: Esp.lg),
          ],

          if (r != null) ...[
            Tarjeta(
              padding: const EdgeInsets.all(Esp.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.clienteNombre,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Pastilla(
                        texto: r.cuandoVence,
                        color: r.vencida ? p.critico : p.observar,
                        lavado: r.vencida ? p.criticoLavado : p.observarLavado,
                      ),
                    ],
                  ),
                  const SizedBox(height: Esp.sm),
                  FilaDato(
                    etiqueta: 'Seña depositada',
                    valor: Fmt.pesos(r.senia),
                    destacado: true,
                  ),
                  FilaDato(
                    etiqueta: 'Reservada el',
                    valor: Fmt.fecha(r.fechaReserva),
                  ),
                  FilaDato(etiqueta: 'Vence el', valor: Fmt.fecha(r.venceEl)),
                  if ((r.clienteTelefono ?? '').isNotEmpty)
                    FilaDato(etiqueta: 'Teléfono', valor: r.clienteTelefono!),
                  if (r.notas.isNotEmpty) ...[
                    const SizedBox(height: Esp.sm),
                    Text(
                      r.notas,
                      style: TextStyle(
                        fontSize: 15,
                        color: p.tinta2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Esp.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: p.bien,
                foregroundColor: Colors.white,
              ),
              onPressed: _guardando
                  ? null
                  : () => _cerrar(EstadoReserva.concretada),
              icon: const Icon(Icons.check_rounded, size: 22),
              label: const Text('Se concretó la venta'),
            ),
            const SizedBox(height: Esp.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: p.critico,
                side: BorderSide(color: p.critico, width: 1.6),
              ),
              onPressed: _guardando
                  ? null
                  : () => _cerrar(EstadoReserva.cancelada),
              icon: const Icon(Icons.close_rounded, size: 22),
              label: const Text('Cancelar la reserva'),
            ),
            const SizedBox(height: Esp.sm),
            Text(
              'Al cerrarla, la unidad vuelve sola a disponible.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.tinta3),
            ),
          ] else ...[
            _ElegirCliente(
              nombre: _nombre,
              error: _errores['cliente'],
              onElegir: (nombre, telefono, id) => setState(() {
                _nombre = nombre;
                _telefono = telefono ?? '';
                _oportunidadId = id;
              }),
            ),
            const SizedBox(height: Esp.md),
            FilaCampos(
              children: [
                CampoMonto(
                  etiqueta: 'Seña',
                  ayuda: 'Lo que dejó depositado',
                  valor: _senia == 0 ? null : _senia,
                  error: _errores['senia'],
                  onCambio: (x) => setState(() => _senia = x ?? 0),
                ),
                CampoFecha(
                  etiqueta: 'Se le guarda hasta',
                  obligatorio: true,
                  valor: _vence,
                  error: _errores['vence'],
                  onCambio: (x) => setState(() => _vence = x),
                ),
              ],
            ),
            const SizedBox(height: Esp.md),
            CampoTexto(
              etiqueta: 'Notas',
              ayuda: 'Lo que se acordó: forma de pago, qué falta, lo que sea',
              valor: _notas,
              lineas: 2,
              onCambio: (x) => _notas = x,
            ),
            const SizedBox(height: Esp.lg),
            FilledButton.icon(
              onPressed: _guardando ? null : _reservar,
              icon: _guardando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.bookmark_added_outlined, size: 22),
              label: const Text('Reservar la unidad'),
            ),
            const SizedBox(height: Esp.sm),
            Text(
              'Mientras esté reservada, la unidad sale del listado de '
              'disponibles.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.tinta3),
            ),
          ],
        ],
      ),
    );
  }
}

/// A nombre de quién. Se puede elegir de los clientes cargados o escribir el
/// nombre a mano: muchas veces la seña la deja alguien que todavía no está
/// en el sistema.
class _ElegirCliente extends ConsumerWidget {
  const _ElegirCliente({
    required this.nombre,
    required this.onElegir,
    this.error,
  });

  final String nombre;
  final String? error;
  final void Function(String nombre, String? telefono, String? id) onElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final clientes = ref.watch(interesadosProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoTexto(
          etiqueta: 'A nombre de',
          obligatorio: true,
          valor: nombre,
          error: error,
          capitalizar: true,
          onCambio: (x) => onElegir(x, null, null),
        ),
        if (clientes.isNotEmpty) ...[
          const SizedBox(height: Esp.sm),
          Text(
            'O elegí uno de tus clientes:',
            style: TextStyle(fontSize: 14, color: p.tinta3),
          ),
          const SizedBox(height: Esp.sm - 2),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final c in clientes.take(8))
                ChipSeleccion(
                  etiqueta: c.nombre,
                  activo: nombre == c.nombre,
                  onTap: () => onElegir(c.nombre, c.telefono, c.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
