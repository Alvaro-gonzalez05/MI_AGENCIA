import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/campanas.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';
import 'formulario_campana.dart';

class PantallaCampanas extends ConsumerWidget {
  const PantallaCampanas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(campanasProvider);
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: asincrono.value?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: () => abrirFormulario(context),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Nueva campaña'),
            )
          : null,
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar las campañas',
          descripcion: '$e',
        ),
        data: (campanas) {
          if (campanas.isEmpty) {
            return EstadoVacio(
              icono: Icons.campaign_outlined,
              titulo: 'Todavía no hay campañas',
              descripcion:
                  'Escribile a los interesados que dejaron su email. A quien '
                  'pidió la baja no se le vuelve a escribir nunca.',
              accion: FilledButton.icon(
                onPressed: () => abrirFormulario(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Armar una campaña'),
              ),
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              esMovil ? Esp.lg + 4 : Esp.xxl,
              Esp.xl,
              esMovil ? Esp.lg + 4 : Esp.xxl,
              96,
            ),
            children: [
              const _Audiencia(),
              const SizedBox(height: Esp.lg),
              for (var i = 0; i < campanas.length; i++) ...[
                Aparecer(
                  indice: i,
                  child: _Tarjeta(campana: campanas[i]),
                ),
                const SizedBox(height: Esp.sm),
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<void> abrirFormulario(BuildContext context) async {
    final creada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FormularioCampana(),
      ),
    );
    if (creada == true && context.mounted) {
      confirmarGuardado(context, 'Campaña guardada como borrador');
    }
  }
}

/// A cuánta gente se le puede escribir hoy.
class _Audiencia extends ConsumerWidget {
  const _Audiencia();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final cantidad = ref.watch(destinatariosProvider);

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Tu audiencia',
            descripcion: 'Interesados con email, que no pidieron la baja',
          ),
          const SizedBox(height: Esp.lg),
          cantidad.when(
            loading: () => const SizedBox(
              height: 32,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => Text(
              'No se pudo contar la audiencia.',
              style: TextStyle(fontSize: 13, color: p.tinta3),
            ),
            data: (n) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: n == 0 ? p.tinta3 : p.tinta,
                  ),
                ),
                Text(
                  n == 0
                      ? 'Ningún interesado tiene email cargado todavía. Sin '
                            'email no hay a quién escribirle.'
                      : n == 1
                      ? 'persona recibiría esta campaña'
                      : 'personas recibirían esta campaña',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: p.tinta3,
                    height: 1.4,
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

class _Tarjeta extends ConsumerWidget {
  const _Tarjeta({required this.campana});

  final Campana campana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final c = campana;

    final (Color color, String etiqueta) = switch (c.estado) {
      EstadoCampana.enviada => (p.bien, 'Enviada'),
      EstadoCampana.enviando => (p.observar, 'Enviando'),
      EstadoCampana.cancelada => (p.neutro, 'Cancelada'),
      EstadoCampana.programada => (p.acentoTexto, 'Programada'),
      EstadoCampana.borrador => (p.neutro, 'Borrador'),
    };

    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoEnCirculo(icono: Icons.mail_outline, color: color),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: p.tinta,
                      ),
                    ),
                    Text(
                      c.asunto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              Pastilla(
                texto: etiqueta,
                color: color,
                lavado: color.withValues(alpha: 0.14),
              ),
            ],
          ),

          if (c.estado == EstadoCampana.enviada) ...[
            const SizedBox(height: Esp.md),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.sm),
            Row(
              children: [
                Expanded(
                  child: _Mini(etiqueta: 'Enviados', valor: '${c.enviados}'),
                ),
                Expanded(
                  child: _Mini(
                    etiqueta: 'Aperturas',
                    valor: c.tasaApertura == null
                        ? Fmt.sinDato
                        : Fmt.porcentaje(c.tasaApertura, decimales: 0),
                  ),
                ),
                Expanded(
                  child: _Mini(
                    etiqueta: 'Clics',
                    valor: c.tasaClick == null
                        ? Fmt.sinDato
                        : Fmt.porcentaje(c.tasaClick, decimales: 0),
                  ),
                ),
                Expanded(
                  child: _Mini(
                    etiqueta: 'Fecha',
                    valor: Fmt.fecha(c.enviadaEl),
                  ),
                ),
              ],
            ),
          ] else if (c.estado.editable) ...[
            const SizedBox(height: Esp.md),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Todavía no salió. Revisala antes de enviarla: un mail '
                    'mandado no se puede deshacer.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: p.tinta3,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: Esp.md),
                FilledButton.icon(
                  onPressed: () => _enviar(context, ref, c),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Enviar es irreversible, así que pide confirmación con el número de
  /// destinatarios a la vista.
  Future<void> _enviar(BuildContext context, WidgetRef ref, Campana c) async {
    final cantidad = ref.read(destinatariosProvider).value ?? 0;

    if (cantidad == 0) {
      mostrarError(context, 'No hay ningún destinatario con email cargado.');
      return;
    }

    final ok = await confirmarAccion(
      context,
      titulo: 'Enviar la campaña',
      descripcion:
          'Se le va a mandar "${c.asunto}" a $cantidad '
          '${cantidad == 1 ? 'persona' : 'personas'}. Un mail enviado no se '
          'puede deshacer.',
      confirmar: 'Enviar ahora',
      icono: Icons.send_rounded,
      permitirCancelarTocandoAfuera: false,
    );

    if (ok != true || !context.mounted) return;

    try {
      final enviados = await ref.read(repositorioProvider).enviarCampana(c.id);
      ref.invalidate(campanasProvider);
      if (context.mounted) {
        confirmarGuardado(context, 'Campaña enviada a $enviados destinatarios');
      }
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.etiqueta, required this.valor});

  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 10.5, color: p.tinta3)),
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.tinta2,
          ),
        ),
      ],
    );
  }
}
