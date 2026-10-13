import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../dominio/equipo.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';

/// La ficha de una persona del equipo: con qué usuario entra, qué puede
/// ver, y los tres botones que hacen falta de verdad —clave nueva, cambiar
/// el rol, sacarle el acceso—.
///
/// Lo que no está, y no es un olvido: ver la clave. No se guarda en ningún
/// lado. Lo único posible es generar otra, y eso es lo que hace falta
/// cuando alguien la pierde.
class HojaMiembro extends ConsumerStatefulWidget {
  const HojaMiembro({super.key, required this.miembro});

  final Miembro miembro;

  static Future<void> abrir(BuildContext context, Miembro m) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 580),
        builder: (_) => HojaMiembro(miembro: m),
      );

  @override
  ConsumerState<HojaMiembro> createState() => _HojaMiembroState();
}

class _HojaMiembroState extends ConsumerState<HojaMiembro> {
  String? _claveNueva;
  String? _error;
  bool _trabajando = false;

  Miembro get m => widget.miembro;

  Future<void> _hacer(Future<void> Function() accion) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await accion();
      ref.invalidate(equipoProvider);
      if (mounted) setState(() => _trabajando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _nuevaClave() async {
    final ok = await confirmarAccion(
      context,
      titulo: 'Generar una clave nueva',
      descripcion:
          '${m.nombre} va a dejar de entrar con la clave que tiene. La nueva '
          'se muestra una sola vez, para que se la dictes.',
      confirmar: 'Generar',
      icono: Icons.key_outlined,
    );
    if (!ok) return;
    await _hacer(() async {
      final cuenta = await ref
          .read(repositorioProvider)
          .nuevaClave(m.usuarioId);
      if (mounted) setState(() => _claveNueva = cuenta.clave);
    });
  }

  Future<void> _cambiarAcceso() async {
    final sacando = m.activa;
    final ok = await confirmarAccion(
      context,
      titulo: sacando
          ? 'Sacarle el acceso a ${m.nombre}'
          : 'Devolverle el acceso a ${m.nombre}',
      descripcion: sacando
          ? 'Deja de poder entrar ahora mismo. No se borra nada: las ventas '
                'que hizo, los gastos que cargó y los clientes que atendió '
                'siguen con su nombre, y si vuelve se reactiva en un toque.'
          : 'Vuelve a entrar con el mismo usuario. Si no se acuerda la '
                'clave, generale una nueva.',
      confirmar: sacando ? 'Sacarle el acceso' : 'Devolvérselo',
      icono: sacando ? Icons.lock_outline_rounded : Icons.lock_open_outlined,
      peligrosa: sacando,
    );
    if (!ok) return;
    await _hacer(
      () => ref
          .read(repositorioProvider)
          .cambiarAcceso(m.membresiaId, activa: !m.activa),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cambiarRol() async {
    final elegido = await showModalBottomSheet<RolMembresia>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _ElegirRol(actual: m.rol),
    );
    if (elegido == null || elegido == m.rol) return;
    await _hacer(
      () => ref.read(repositorioProvider).cambiarRol(m.membresiaId, elegido),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final yo = ref.watch(usuarioProvider)?.id == m.usuarioId;
    final puedo = ref.watch(permisosProvider).puedeAdministrar;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: m.icono,
                tamano: 48,
                color: m.vePlata ? p.acentoTexto : p.tinta2,
                fondo: m.vePlata ? p.acentoLavado : p.superficieHundida,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.nombre,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      [
                        m.rol.etiqueta,
                        if (m.zonaNombre != null) m.zonaNombre!,
                        if (m.desde != null) 'desde ${Fmt.mes(m.desde!)}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: p.tinta3),
                    ),
                  ],
                ),
              ),
              if (!m.activa)
                Pastilla(
                  texto: 'Sin acceso',
                  color: p.neutro,
                  lavado: p.neutroLavado,
                ),
            ],
          ),
          const SizedBox(height: Esp.lg),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Esp.md,
              vertical: Esp.sm + 2,
            ),
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
              border: Border.all(color: p.borde),
            ),
            child: Row(
              children: [
                Icon(Icons.mail_outline_rounded, size: 17, color: p.tinta3),
                const SizedBox(width: Esp.sm),
                Expanded(
                  child: SelectableText(
                    m.email,
                    style: TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 14,
                      color: p.tinta,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar el usuario',
                  icon: Icon(Icons.copy_outlined, size: 18, color: p.tinta3),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: m.email));
                    confirmarGuardado(context, 'Usuario copiado');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: Esp.sm),
          _QueVe(rol: m.rol),

          if (_claveNueva != null) ...[
            const SizedBox(height: Esp.md),
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.bienLavado,
                borderRadius: BorderRadius.circular(Curva.md),
                border: Border.all(color: p.bien),
              ),
              child: Row(
                children: [
                  Icon(Icons.key_outlined, size: 18, color: p.bien),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: SelectableText(
                      _claveNueva!,
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: p.tinta,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'se muestra una sola vez',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, color: p.bien),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: Esp.md),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: p.critico, height: 1.4),
            ),
          ],

          if (puedo && !yo) ...[
            const SizedBox(height: Esp.lg),
            Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _trabajando ? null : _nuevaClave,
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Generar clave nueva'),
                ),
                OutlinedButton.icon(
                  onPressed: _trabajando ? null : _cambiarRol,
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Cambiar rol'),
                ),
                OutlinedButton.icon(
                  onPressed: _trabajando ? null : _cambiarAcceso,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: m.activa ? p.critico : p.bien,
                  ),
                  icon: Icon(
                    m.activa
                        ? Icons.lock_outline_rounded
                        : Icons.lock_open_outlined,
                    size: 18,
                  ),
                  label: Text(
                    m.activa ? 'Sacarle el acceso' : 'Devolverle el acceso',
                  ),
                ),
              ],
            ),
          ] else if (yo) ...[
            const SizedBox(height: Esp.md),
            Text(
              'Esta es tu cuenta. El rol y el acceso propios se cambian desde '
              'otra cuenta de dueño, así nadie se deja afuera sin querer.',
              style: TextStyle(fontSize: 13, height: 1.45, color: p.tinta3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo que ve y lo que no, escrito. Es la pregunta real cuando alguien mira
/// una ficha: "¿este ve lo que pagué por los autos?".
class _QueVe extends StatelessWidget {
  const _QueVe({required this.rol});

  final RolMembresia rol;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rol.descripcion,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: p.tinta2),
          ),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              Icon(
                rol.vePlata
                    ? Icons.monetization_on_outlined
                    : Icons.money_off_csred_outlined,
                size: 17,
                color: rol.vePlata ? p.acentoTexto : p.tinta3,
              ),
              const SizedBox(width: Esp.sm - 2),
              Expanded(
                child: Text(
                  rol.vePlata
                      ? 'Ve el precio de compra, el costo y la ganancia'
                      : 'No ve el precio de compra ni la ganancia',
                  style: TextStyle(fontSize: 13, color: p.tinta2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ElegirRol extends StatelessWidget {
  const _ElegirRol({required this.actual});

  final RolMembresia actual;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Cambiar el rol',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Es lo único que decide qué ve y qué puede tocar. La zona no.',
            style: TextStyle(fontSize: 13.5, color: p.tinta3),
          ),
          const SizedBox(height: Esp.lg),
          for (final r in RolMembresia.values)
            if (r != RolMembresia.owner) ...[
              Pulsable(
                onTap: () => Navigator.pop(context, r),
                child: Container(
                  padding: const EdgeInsets.all(Esp.md),
                  margin: const EdgeInsets.only(bottom: Esp.sm),
                  decoration: BoxDecoration(
                    color: r == actual ? p.acento : p.superficie,
                    borderRadius: BorderRadius.circular(Curva.md),
                    border: Border.all(
                      color: r == actual ? p.acentoTinta : p.borde,
                      width: r == actual ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        switch (r) {
                          RolMembresia.admin => Icons.shield_outlined,
                          RolMembresia.vendedor => Icons.person_outline,
                          _ => Icons.visibility_outlined,
                        },
                        size: 20,
                        color: p.tinta2,
                      ),
                      const SizedBox(width: Esp.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.etiqueta,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.tinta,
                              ),
                            ),
                            Text(
                              r.descripcion,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: p.tinta2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}
