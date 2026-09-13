import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/actualizaciones.dart';
import '../core/config.dart';
import '../core/tema/colores.dart';
import '../core/tema/tema.dart';
import 'componentes.dart';

/// Capa por encima de toda la app que avisa cuando hay una version nueva.
///
/// Vive en el `builder` de MaterialApp y no en el shell: asi el aviso aparece
/// tambien en el login, que es justo donde hace falta si la actualizacion es
/// obligatoria.
class CapaActualizacion extends ConsumerStatefulWidget {
  const CapaActualizacion({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CapaActualizacion> createState() => _CapaActualizacionState();
}

class _CapaActualizacionState extends ConsumerState<CapaActualizacion> {
  /// Version que el usuario pospuso con "Después". Si sale otra mas nueva, se
  /// vuelve a avisar.
  String? _pospuesta;
  bool _instalando = false;
  double? _progreso;
  String? _error;

  Future<void> _instalar(VersionDisponible v) async {
    setState(() {
      _instalando = true;
      _progreso = null;
      _error = null;
    });
    try {
      await instalarActualizacion(
        v,
        alProgresar: (x) {
          if (mounted) setState(() => _progreso = x);
        },
      );
      // En Android se vuelve de abrir la descarga: el aviso queda por si el
      // usuario no termino de instalar.
      if (mounted) setState(() => _instalando = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _instalando = false;
        _error = 'No se pudo descargar. Revisá la conexión y probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(actualizacionProvider).value;
    final aviso = v != null && !v.obligatoria && _pospuesta != v.version;
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Stack(
      children: [
        widget.child,

        // Aviso comun: tarjeta negra flotante que entra deslizandose. En
        // escritorio va abajo a la derecha para no tapar la navegacion; en
        // el celular, arriba, porque abajo esta la barra.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !aviso,
            child: SafeArea(
              child: Align(
                alignment: esMovil
                    ? Alignment.topCenter
                    : Alignment.bottomRight,
                child: AnimatedSlide(
                  duration: Duracion.lenta,
                  curve: Curves.easeOutCubic,
                  offset: aviso ? Offset.zero : Offset(0, esMovil ? -1.4 : 1.4),
                  child: AnimatedOpacity(
                    duration: Duracion.media,
                    opacity: aviso ? 1 : 0,
                    child: v == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.all(Esp.lg),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: _TarjetaAviso(
                                version: v,
                                instalando: _instalando,
                                progreso: _progreso,
                                error: _error,
                                onActualizar: () => _instalar(v),
                                onPosponer: () =>
                                    setState(() => _pospuesta = v.version),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),

        if (v != null && v.obligatoria)
          Positioned.fill(
            child: _Bloqueo(
              version: v,
              instalando: _instalando,
              progreso: _progreso,
              error: _error,
              onActualizar: () => _instalar(v),
            ),
          ),
      ],
    );
  }
}

class _TarjetaAviso extends StatelessWidget {
  const _TarjetaAviso({
    required this.version,
    required this.instalando,
    required this.progreso,
    required this.error,
    required this.onActualizar,
    required this.onPosponer,
  });

  final VersionDisponible version;
  final bool instalando;
  final double? progreso;
  final String? error;
  final VoidCallback onActualizar;
  final VoidCallback onPosponer;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final detalle = version.notas.isNotEmpty
        ? version.notas
        : 'Tenés instalada la ${Config.version}.';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Curva.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: p.negro,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Curva.lg),
          side: BorderSide(color: p.negroBorde),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Esp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconoEnCirculo(
                    icono: Icons.system_update_alt_rounded,
                    tamano: 42,
                    color: p.acentoTinta,
                    fondo: p.acento,
                  ),
                  const SizedBox(width: Esp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nueva versión ${version.version}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.sobreNegro,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detalle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: p.sobreNegro2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Esp.md),
              _EstadoDescarga(
                instalando: instalando,
                progreso: progreso,
                error: error,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!instalando)
                    TextButton(
                      onPressed: onPosponer,
                      style: TextButton.styleFrom(
                        foregroundColor: p.sobreNegro2,
                      ),
                      child: const Text('Después'),
                    ),
                  const SizedBox(width: Esp.sm),
                  FilledButton.icon(
                    onPressed: instalando ? null : onActualizar,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Esp.lg + 2,
                        vertical: Esp.md,
                      ),
                      disabledBackgroundColor: p.negroElevado,
                      disabledForegroundColor: p.sobreNegro2,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(instalando ? 'Descargando…' : 'Actualizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de progreso o mensaje de error, segun corresponda.
class _EstadoDescarga extends StatelessWidget {
  const _EstadoDescarga({
    required this.instalando,
    required this.progreso,
    required this.error,
  });

  final bool instalando;
  final double? progreso;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    if (instalando) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Esp.md),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Curva.completo),
          child: LinearProgressIndicator(
            // Null = sin tamaño conocido: barra indeterminada.
            value: progreso,
            minHeight: 8,
            backgroundColor: p.negroElevado,
            valueColor: AlwaysStoppedAnimation(p.acento),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Esp.md),
        child: Text(error!, style: TextStyle(fontSize: 12.5, color: p.critico)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Pantalla que bloquea la app hasta actualizar. Solo para versiones marcadas
/// como obligatorias al publicar.
class _Bloqueo extends StatelessWidget {
  const _Bloqueo({
    required this.version,
    required this.instalando,
    required this.progreso,
    required this.error,
    required this.onActualizar,
  });

  final VersionDisponible version;
  final bool instalando;
  final double? progreso;
  final String? error;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: 0.7),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Esp.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Aparecer(
                child: Material(
                  color: p.superficieElevada,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Curva.xl),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Esp.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: IconoEnCirculo(
                            icono: Icons.system_update_alt_rounded,
                            tamano: 72,
                            color: p.acentoTinta,
                            fondo: p.acento,
                          ),
                        ),
                        const SizedBox(height: Esp.lg + 2),
                        Text(
                          'Hay que actualizar',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: Esp.sm),
                        Text(
                          'La versión ${version.version} trae cambios '
                          'necesarios para seguir usando la app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: p.tinta2,
                          ),
                        ),
                        if (version.notas.isNotEmpty) ...[
                          const SizedBox(height: Esp.md),
                          Container(
                            padding: const EdgeInsets.all(Esp.md + 2),
                            decoration: BoxDecoration(
                              color: p.superficieHundida,
                              borderRadius: BorderRadius.circular(Curva.md),
                            ),
                            child: Text(
                              version.notas,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: p.tinta2,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: Esp.xl),
                        if (instalando || error != null)
                          _EstadoDescargaClaro(
                            instalando: instalando,
                            progreso: progreso,
                            error: error,
                          ),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: instalando ? null : onActualizar,
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: Text(
                              instalando ? 'Descargando…' : 'Actualizar ahora',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Igual que [_EstadoDescarga], pero para una superficie clara.
class _EstadoDescargaClaro extends StatelessWidget {
  const _EstadoDescargaClaro({
    required this.instalando,
    required this.progreso,
    required this.error,
  });

  final bool instalando;
  final double? progreso;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.lg),
      child: instalando
          ? ClipRRect(
              borderRadius: BorderRadius.circular(Curva.completo),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 8,
                backgroundColor: p.superficieHundida,
                valueColor: AlwaysStoppedAnimation(p.acento),
              ),
            )
          : Text(
              error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.critico),
            ),
    );
  }
}
