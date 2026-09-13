import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../ui/componentes.dart';
import 'formulario_agencia.dart';

/// Panel de la cuenta de desarrollador: las agencias cliente.
///
/// El RLS ya garantiza que un usuario común no vea nada acá, así que la
/// pantalla no chequea permisos: si la lista llega vacía es porque la base
/// no devolvió nada, no porque haya que esconderlo en el cliente.
class PantallaAgencias extends ConsumerWidget {
  const PantallaAgencias({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(agenciasProvider);
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(context),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Nueva agencia'),
      ),
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar las agencias',
          descripcion: '$e',
        ),
        data: (agencias) {
          if (agencias.isEmpty) {
            return EstadoVacio(
              icono: Icons.apartment_outlined,
              titulo: 'Todavía no diste de alta ninguna agencia',
              descripcion:
                  'Al crear una, se invita por email a su dueño. Cuando se '
                  'registre queda vinculado solo.',
              accion: FilledButton.icon(
                onPressed: () => abrirFormulario(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Crear una agencia'),
              ),
            );
          }

          final activas = agencias.where((a) => a.activa).length;
          final unidades = agencias.fold<int>(0, (s, a) => s + a.vehiculos);

          return ListView(
            padding: EdgeInsets.fromLTRB(
              esMovil ? Esp.lg + 4 : Esp.xxl,
              Esp.xl,
              esMovil ? Esp.lg + 4 : Esp.xxl,
              96,
            ),
            children: [
              _Resumen(
                total: agencias.length,
                activas: activas,
                unidades: unidades,
              ),
              const SizedBox(height: Esp.lg),
              for (var i = 0; i < agencias.length; i++) ...[
                Aparecer(
                  indice: i,
                  child: _Tarjeta(agencia: agencias[i]),
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
        builder: (_) => const FormularioAgencia(),
      ),
    );
    if (creada == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agencia creada — se invitó a su dueño por email'),
        ),
      );
    }
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({
    required this.total,
    required this.activas,
    required this.unidades,
  });

  final int total, activas, unidades;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Cuentas cliente',
            descripcion: 'Lo que factura el sistema',
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: _Dato(etiqueta: 'Agencias', valor: '$total'),
              ),
              Expanded(
                child: _Dato(
                  etiqueta: 'Activas',
                  valor: '$activas',
                  color: activas < total ? p.observar : p.bien,
                ),
              ),
              Expanded(
                child: _Dato(etiqueta: 'Unidades', valor: '$unidades'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, this.color});

  final String etiqueta, valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: color ?? p.tinta,
          ),
        ),
      ],
    );
  }
}

class _Tarjeta extends ConsumerWidget {
  const _Tarjeta({required this.agencia});

  final Agencia agencia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final a = agencia;

    final (Color color, String estado) = !a.activa
        ? (p.neutro, 'Suspendida')
        : a.vencida
        ? (p.critico, 'Vencida')
        : (p.bien, 'Activa');

    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoEnCirculo(icono: Icons.storefront_outlined, color: color),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: p.tinta,
                      ),
                    ),
                    Text(
                      [
                        if (a.ubicacion.isNotEmpty) a.ubicacion,
                        'Plan ${a.plan}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              Pastilla(
                texto: estado,
                color: color,
                lavado: color.withValues(alpha: 0.14),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          Divider(color: p.borde, height: 1),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              Expanded(
                child: _Mini(etiqueta: 'Usuarios', valor: '${a.miembros}'),
              ),
              Expanded(
                child: _Mini(etiqueta: 'Unidades', valor: '${a.vehiculos}'),
              ),
              Expanded(
                child: _Mini(
                  etiqueta: a.vigenteHasta == null ? 'Vigencia' : 'Paga hasta',
                  valor: a.vigenteHasta == null
                      ? 'Sin límite'
                      : Fmt.fecha(a.vigenteHasta),
                  color: a.vencida ? p.critico : null,
                ),
              ),
              IconButton(
                tooltip: a.activa ? 'Suspender' : 'Reactivar',
                icon: Icon(
                  a.activa
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  size: 20,
                  color: p.tinta3,
                ),
                onPressed: () => _confirmarCambio(context, ref, a),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Suspender le corta el acceso a un cliente: conviene preguntar.
  Future<void> _confirmarCambio(
    BuildContext context,
    WidgetRef ref,
    Agencia a,
  ) async {
    final suspender = a.activa;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.paleta.superficieElevada,
        title: Text(
          suspender ? 'Suspender ${a.nombre}' : 'Reactivar ${a.nombre}',
        ),
        content: Text(
          suspender
              ? 'Sus usuarios dejan de poder entrar. Los datos quedan '
                    'intactos y se recupera todo al reactivarla.'
              : 'Sus usuarios vuelven a tener acceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(suspender ? 'Suspender' : 'Reactivar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ref
        .read(repositorioProvider)
        .cambiarEstadoAgencia(a.id, activa: !a.activa);
    ref.invalidate(agenciasProvider);
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.etiqueta, required this.valor, this.color});

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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? p.tinta2,
          ),
        ),
      ],
    );
  }
}
