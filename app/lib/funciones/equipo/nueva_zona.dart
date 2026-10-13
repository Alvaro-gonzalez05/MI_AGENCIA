import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/equipo.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Crear o renombrar un área de la agencia.
///
/// Son dos datos: cómo se llama y con qué icono se la reconoce de lejos en
/// la pizarra. Nada más, porque una zona no decide permisos: eso lo hace el
/// rol de cada persona.
class HojaNuevaZona extends ConsumerStatefulWidget {
  const HojaNuevaZona({super.key, this.zona});

  /// Si viene, se edita en vez de crear.
  final Zona? zona;

  static Future<void> abrir(
    BuildContext context,
    WidgetRef ref, {
    Zona? zona,
  }) async {
    final hecho = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => HojaNuevaZona(zona: zona),
    );
    if (hecho == true) ref.invalidate(zonasProvider);
  }

  @override
  ConsumerState<HojaNuevaZona> createState() => _HojaNuevaZonaState();
}

class _HojaNuevaZonaState extends ConsumerState<HojaNuevaZona> {
  late String _nombre = widget.zona?.nombre ?? '';
  late String _icono = widget.zona?.icono ?? 'folder';
  String? _error;
  bool _guardando = false;

  Future<void> _guardar() async {
    if (_nombre.trim().length < 2) {
      setState(() => _error = 'Poné un nombre para la zona.');
      return;
    }
    setState(() {
      _error = null;
      _guardando = true;
    });
    try {
      final repo = ref.read(repositorioProvider);
      if (widget.zona == null) {
        // Entra abajo a la izquierda, donde casi siempre hay lugar: después
        // se arrastra adonde corresponda.
        await repo.crearZona(
          nombre: _nombre.trim(),
          icono: _icono,
          x: 40,
          y: 380,
        );
      } else {
        await repo.guardarZona(
          widget.zona!.copiar(nombre: _nombre.trim(), icono: _icono),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final editando = widget.zona != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: IconosZona.de(_icono),
                tamano: 44,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  editando ? 'Editar la zona' : 'Nueva zona',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          CampoTexto(
            etiqueta: 'Cómo se llama',
            obligatorio: true,
            ayuda: 'Ej: Taller, Playa, Posventa',
            valor: _nombre,
            capitalizar: true,
            onCambio: (x) => setState(() => _nombre = x),
          ),
          const SizedBox(height: Esp.lg),
          Text(
            'Con qué icono',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: p.tinta,
            ),
          ),
          const SizedBox(height: Esp.sm),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final e in IconosZona.opciones.entries)
                Pulsable(
                  onTap: () => setState(() => _icono = e.key),
                  child: AnimatedContainer(
                    duration: Duracion.rapida,
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _icono == e.key ? p.acento : p.superficie,
                      borderRadius: BorderRadius.circular(Curva.md),
                      border: Border.all(
                        color: _icono == e.key ? p.acentoTinta : p.borde,
                        width: _icono == e.key ? 1.5 : 1,
                      ),
                    ),
                    child: Icon(
                      e.value,
                      size: 22,
                      color: _icono == e.key ? p.acentoTinta : p.tinta2,
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: Esp.md),
            AvisoError(mensaje: _error!),
          ],
          const SizedBox(height: Esp.lg),
          BotoneraFormulario(
            guardando: _guardando,
            etiquetaGuardar: editando ? 'Guardar' : 'Crear la zona',
            onCancelar: () => Navigator.pop(context, false),
            onGuardar: _guardar,
          ),
        ],
      ),
    );
  }
}
