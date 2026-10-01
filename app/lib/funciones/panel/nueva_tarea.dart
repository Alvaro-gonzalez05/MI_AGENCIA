import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/tareas.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// "Nueva tarea", como el modal del diseño: qué hay que hacer, con quién,
/// sobre qué auto, cuándo y si se repite.
///
/// El orden de las preguntas no es casual: primero el tipo, porque con eso
/// solo ya se entiende la tarea; después el resto, que es opcional. Así
/// anotar "llamar a Juan" son dos toques.
class HojaNuevaTarea extends ConsumerStatefulWidget {
  const HojaNuevaTarea({super.key, this.tarea, this.vehiculoId});

  final Tarea? tarea;

  /// Si se abre desde una ficha, la unidad viene puesta.
  final String? vehiculoId;

  /// Devuelve true si se guardó algo.
  static Future<bool> abrir(
    BuildContext context, {
    Tarea? tarea,
    String? vehiculoId,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (_) => HojaNuevaTarea(tarea: tarea, vehiculoId: vehiculoId),
      ) ??
      false;

  @override
  ConsumerState<HojaNuevaTarea> createState() => _HojaNuevaTareaState();
}

class _HojaNuevaTareaState extends ConsumerState<HojaNuevaTarea> {
  late AltaTarea _t = AltaTarea(
    id: widget.tarea?.id,
    titulo: widget.tarea?.titulo ?? '',
    detalle: widget.tarea?.detalle ?? '',
    tipo: widget.tarea?.tipo ?? TipoTarea.llamar,
    venceEl: widget.tarea?.venceEl ?? _hoy(),
    hora: widget.tarea?.hora,
    repeticion: widget.tarea?.repeticion ?? RepeticionTarea.unaVez,
    oportunidadId: widget.tarea?.oportunidadId,
    vehiculoId: widget.tarea?.vehiculoId ?? widget.vehiculoId,
  );

  Map<String, String> _errores = {};
  bool _guardando = false;

  static DateTime _hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _guardar() async {
    final errores = _t.validar();
    setState(() => _errores = errores);
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).guardarTarea(_t);
      ref.invalidate(tareasProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la tarea: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final clientes = ref.watch(interesadosProvider).value ?? const [];
    final unidades =
        ref.watch(inventarioProvider).value ?? const <VehiculoInventario>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.event_note_outlined,
                tamano: 44,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  _t.esEdicion ? 'Editar la tarea' : 'Nueva tarea',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),

          _Numerada(
            numero: 1,
            titulo: '¿Qué tenés que hacer?',
            nota: 'Elegí una opción',
            hijo: LayoutBuilder(
              builder: (context, r) {
                final columnas = r.maxWidth >= 480 ? 3 : 2;
                final ancho = (r.maxWidth - Esp.sm * (columnas - 1)) / columnas;
                return Wrap(
                  spacing: Esp.sm,
                  runSpacing: Esp.sm,
                  children: [
                    for (final t in TipoTarea.values)
                      SizedBox(
                        width: ancho,
                        child: _BotonTipo(
                          tipo: t,
                          activo: _t.tipo == t,
                          onTap: () => setState(() => _t = _t.copiar(tipo: t)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: Esp.lg),
          CampoTexto(
            etiqueta: 'Qué hay que hacer',
            obligatorio: true,
            ayuda: 'Ej: llamar para confirmar la entrega',
            valor: _t.titulo,
            error: _errores['titulo'],
            onCambio: (x) => _t = _t.copiar(titulo: x),
          ),

          const SizedBox(height: Esp.lg),
          _Numerada(
            numero: 2,
            titulo: '¿Con quién?',
            nota: 'Opcional',
            hijo: _Elegible(
              vacio: 'Sin cliente',
              elegido: _t.oportunidadId == null
                  ? null
                  : clientes
                        .where((c) => c.id == _t.oportunidadId)
                        .map((c) => (c.nombre, c.telefono ?? ''))
                        .firstOrNull,
              opciones: [
                for (final c in clientes.take(12))
                  (c.id, c.nombre, c.telefono ?? ''),
              ],
              onElegir: (id) => setState(
                () => _t = id == null
                    ? _t.copiar(limpiarCliente: true)
                    : _t.copiar(oportunidadId: id),
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          _Numerada(
            numero: 3,
            titulo: '¿Sobre qué auto?',
            nota: 'Opcional',
            hijo: _Elegible(
              vacio: 'Sin unidad',
              elegido: _t.vehiculoId == null
                  ? null
                  : unidades
                        .where((v) => v.id == _t.vehiculoId)
                        .map((v) => (v.titulo, v.patente ?? v.codigo))
                        .firstOrNull,
              opciones: [
                for (final v in unidades.where((v) => !v.vendido).take(12))
                  (v.id, v.titulo, v.patente ?? v.codigo),
              ],
              onElegir: (id) => setState(
                () => _t = id == null
                    ? _t.copiar(limpiarVehiculo: true)
                    : _t.copiar(vehiculoId: id),
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          _Numerada(
            numero: 4,
            titulo: '¿Cuándo?',
            hijo: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Esp.sm,
                  runSpacing: Esp.sm,
                  children: [
                    ChipSeleccion(
                      etiqueta: 'Hoy',
                      activo: _t.venceEl == _hoy(),
                      onTap: () =>
                          setState(() => _t = _t.copiar(venceEl: _hoy())),
                    ),
                    ChipSeleccion(
                      etiqueta: 'Mañana',
                      activo: _t.venceEl == _hoy().add(const Duration(days: 1)),
                      onTap: () => setState(
                        () => _t = _t.copiar(
                          venceEl: _hoy().add(const Duration(days: 1)),
                        ),
                      ),
                    ),
                    ChipSeleccion(
                      etiqueta: 'Esta semana',
                      activo: _t.venceEl == _hoy().add(const Duration(days: 7)),
                      onTap: () => setState(
                        () => _t = _t.copiar(
                          venceEl: _hoy().add(const Duration(days: 7)),
                        ),
                      ),
                    ),
                    ChipSeleccion(
                      etiqueta: Fmt.fecha(_t.venceEl),
                      icono: Icons.calendar_today_outlined,
                      activo: false,
                      onTap: () async {
                        final f = await showDatePicker(
                          context: context,
                          initialDate: _t.venceEl,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 2),
                          ),
                          helpText: '¿Para cuándo?',
                        );
                        if (f != null) {
                          setState(() => _t = _t.copiar(venceEl: f));
                        }
                      },
                    ),
                    ChipSeleccion(
                      etiqueta: _t.hora == null
                          ? 'Poner hora'
                          : _t.hora!.format(context),
                      icono: Icons.schedule_rounded,
                      activo: _t.hora != null,
                      onTap: () async {
                        final h = await showTimePicker(
                          context: context,
                          initialTime:
                              _t.hora ?? const TimeOfDay(hour: 10, minute: 0),
                        );
                        if (h != null) setState(() => _t = _t.copiar(hora: h));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Esp.sm),
                Text(
                  _t.hora == null
                      ? Fmt.fechaLarga(_t.venceEl)
                      : '${Fmt.fechaLarga(_t.venceEl)} a las '
                            '${_t.hora!.format(context)}',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
              ],
            ),
          ),

          const SizedBox(height: Esp.lg),
          _Numerada(
            numero: 5,
            titulo: '¿Se repite?',
            hijo: Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                for (final r in RepeticionTarea.values)
                  ChipSeleccion(
                    etiqueta: r.etiqueta,
                    activo: _t.repeticion == r,
                    onTap: () => setState(() => _t = _t.copiar(repeticion: r)),
                  ),
              ],
            ),
          ),
          if (_t.repeticion != RepeticionTarea.unaVez) ...[
            const SizedBox(height: Esp.sm),
            Row(
              children: [
                Icon(Icons.repeat_rounded, size: 18, color: p.tinta3),
                const SizedBox(width: Esp.sm - 2),
                Expanded(
                  child: Text(
                    'Al marcarla hecha se crea sola la siguiente.',
                    style: TextStyle(fontSize: 14, color: p.tinta3),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: Esp.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _guardando
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Icon(Icons.check_rounded, size: 22),
                  label: const Text('Guardar tarea'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un paso numerado del modal, como en el diseño.
class _Numerada extends StatelessWidget {
  const _Numerada({
    required this.numero,
    required this.titulo,
    required this.hijo,
    this.nota,
  });

  final int numero;
  final String titulo;
  final String? nota;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$numero. $titulo',
                style: TextStyle(
                  fontFamily: TemaApp.titulo,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
            ),
            if (nota != null)
              Text(nota!, style: TextStyle(fontSize: 14, color: p.tinta3)),
          ],
        ),
        const SizedBox(height: Esp.sm),
        hijo,
      ],
    );
  }
}

class _BotonTipo extends StatelessWidget {
  const _BotonTipo({
    required this.tipo,
    required this.activo,
    required this.onTap,
  });

  final TipoTarea tipo;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Curva.md),
      side: BorderSide(color: activo ? p.acento : p.borde, width: 1.6),
    );
    return Material(
      color: activo ? p.acentoLavado : p.superficie,
      shape: forma,
      child: InkWell(
        onTap: onTap,
        customBorder: forma,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Esp.md),
          child: Column(
            children: [
              Icon(
                tipo.icono,
                size: 26,
                color: activo ? p.acentoTexto : p.tinta2,
              ),
              const SizedBox(height: Esp.xs),
              Text(
                tipo.etiqueta,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                  color: p.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Elegir un cliente o una unidad, con lo elegido a la vista y una cruz
/// para sacarlo.
class _Elegible extends StatelessWidget {
  const _Elegible({
    required this.vacio,
    required this.elegido,
    required this.opciones,
    required this.onElegir,
  });

  final String vacio;
  final (String, String)? elegido;
  final List<(String id, String titulo, String detalle)> opciones;
  final ValueChanged<String?> onElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    if (elegido != null) {
      return Container(
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: p.superficieHundida,
          borderRadius: BorderRadius.circular(Curva.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    elegido!.$1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (elegido!.$2.isNotEmpty)
                    Text(
                      elegido!.$2,
                      style: TextStyle(fontSize: 14, color: p.tinta2),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Sacar',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => onElegir(null),
            ),
          ],
        ),
      );
    }

    if (opciones.isEmpty) {
      return Text(
        'No hay nada cargado todavía.',
        style: TextStyle(fontSize: 15, color: p.tinta3),
      );
    }

    return Wrap(
      spacing: Esp.sm,
      runSpacing: Esp.sm,
      children: [
        for (final (id, titulo, _) in opciones)
          ChipSeleccion(
            etiqueta: titulo,
            activo: false,
            onTap: () => onElegir(id),
          ),
      ],
    );
  }
}
