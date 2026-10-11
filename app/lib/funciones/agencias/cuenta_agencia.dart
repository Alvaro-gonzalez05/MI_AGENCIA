import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';
import '../../ui/formulario.dart';

/// Dar de alta la cuenta con la que entra una agencia.
///
/// La agencia no se registra sola: se le entrega la app andando, con un
/// usuario y una clave. Esta hoja hace las dos cosas de una —crea el usuario
/// y lo deja como dueño de la agencia— y después muestra la clave UNA vez,
/// para anotarla o pasarla por teléfono. No queda guardada en ningún lado.
class HojaCuentaAgencia extends ConsumerStatefulWidget {
  const HojaCuentaAgencia({super.key, required this.agencia});

  final Agencia agencia;

  static Future<void> abrir(BuildContext context, Agencia agencia) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => HojaCuentaAgencia(agencia: agencia),
      );

  @override
  ConsumerState<HojaCuentaAgencia> createState() => _HojaCuentaAgenciaState();
}

class _HojaCuentaAgenciaState extends ConsumerState<HojaCuentaAgencia> {
  late String _email = '${widget.agencia.slug}@miagencia.com';
  late String _nombre = widget.agencia.nombre;
  RolMembresia _rol = RolMembresia.owner;

  String? _error;
  bool _creando = false;

  /// Cuando esto deja de ser null, la hoja pasa a mostrar la credencial.
  CuentaCreada? _creada;

  Future<void> _crear() async {
    final email = _email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Ese email no parece válido.');
      return;
    }

    setState(() {
      _error = null;
      _creando = true;
    });

    try {
      final cuenta = await ref
          .read(repositorioProvider)
          .crearCuentaAgencia(
            agenciaId: widget.agencia.id,
            email: email,
            nombre: _nombre.trim().isEmpty ? widget.agencia.nombre : _nombre,
            rol: _rol,
          );
      ref.invalidate(agenciasProvider);
      if (mounted) setState(() => _creada = cuenta);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final creada = _creada;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: creada == null
                    ? Icons.person_add_alt_1_outlined
                    : Icons.verified_user_outlined,
                tamano: 44,
                color: creada == null ? p.acentoTinta : p.bien,
                fondo: creada == null ? p.acento : p.bienLavado,
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      creada == null ? 'Dar de alta la cuenta' : 'Cuenta lista',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      widget.agencia.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.tinta3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),

          if (creada == null) ..._formulario(p) else ..._credencial(p, creada),
        ],
      ),
    );
  }

  List<Widget> _formulario(Paleta p) => [
    Text(
      'Se crea el usuario y queda con acceso a esta agencia. La clave la '
      'genera el sistema y se muestra una sola vez.',
      style: TextStyle(fontSize: 14, height: 1.45, color: p.tinta2),
    ),
    const SizedBox(height: Esp.lg),

    CampoTexto(
      etiqueta: 'Usuario (email)',
      obligatorio: true,
      ayuda: 'Con el que va a entrar a la app',
      valor: _email,
      onCambio: (x) => _email = x,
    ),
    const SizedBox(height: Esp.md),
    CampoTexto(
      etiqueta: 'Nombre de quien la usa',
      ayuda: 'Aparece arriba, en el saludo',
      valor: _nombre,
      capitalizar: true,
      onCambio: (x) => _nombre = x,
    ),

    const SizedBox(height: Esp.lg),
    Text(
      '¿Qué puede hacer?',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: p.tinta,
      ),
    ),
    const SizedBox(height: Esp.sm),
    for (final r in RolMembresia.values) ...[
      _OpcionRol(
        rol: r,
        activo: _rol == r,
        onTap: () => setState(() => _rol = r),
      ),
      const SizedBox(height: Esp.xs),
    ],

    if (_error != null) ...[
      const SizedBox(height: Esp.md),
      AvisoError(mensaje: _error!),
    ],

    const SizedBox(height: Esp.lg),
    BotoneraFormulario(
      guardando: _creando,
      etiquetaGuardar: 'Crear la cuenta',
      onCancelar: () => Navigator.pop(context),
      onGuardar: _crear,
    ),
  ];

  List<Widget> _credencial(Paleta p, CuentaCreada c) => [
    if (c.yaExistia)
      Container(
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: p.observarLavado,
          borderRadius: BorderRadius.circular(Curva.md),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: p.observar),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Text(
                'Ese usuario ya existía. Le dimos acceso a esta agencia y '
                'sigue entrando con la clave que ya tenía.',
                style: TextStyle(fontSize: 13, height: 1.4, color: p.tinta2),
              ),
            ),
          ],
        ),
      )
    else
      Text(
        'Anotá la clave ahora: no se guarda en ningún lado. Si se pierde, se '
        'genera otra.',
        style: TextStyle(fontSize: 14, height: 1.45, color: p.tinta2),
      ),

    const SizedBox(height: Esp.lg),
    _Credencial(etiqueta: 'Usuario', valor: c.email),
    if (c.clave != null) ...[
      const SizedBox(height: Esp.sm),
      _Credencial(etiqueta: 'Clave', valor: c.clave!, destacado: true),
    ],

    const SizedBox(height: Esp.md),
    FilaDato(etiqueta: 'Entra como', valor: RolMembresia.desde(c.rol).etiqueta),

    const SizedBox(height: Esp.lg),
    Row(
      children: [
        if (c.clave != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text:
                        'Mi Agencia — ${c.agencia}\n'
                        'Usuario: ${c.email}\n'
                        'Clave: ${c.clave}',
                  ),
                );
                confirmarGuardado(context, 'Copiado para pasárselo');
              },
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copiar todo'),
            ),
          ),
        if (c.clave != null) const SizedBox(width: Esp.sm),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo'),
          ),
        ),
      ],
    ),
  ];
}

/// Un rol con lo que implica escrito al lado. Sin eso nadie elige bien:
/// "vendedor" no dice por sí solo que no ve la ganancia.
class _OpcionRol extends StatelessWidget {
  const _OpcionRol({
    required this.rol,
    required this.activo,
    required this.onTap,
  });

  final RolMembresia rol;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Pulsable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(Esp.md),
        decoration: BoxDecoration(
          color: activo ? p.acento : p.superficie,
          borderRadius: BorderRadius.circular(Curva.md),
          border: Border.all(
            color: activo ? p.acentoTinta : p.borde,
            width: activo ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              activo
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: activo ? p.acentoTinta : p.tinta3,
            ),
            const SizedBox(width: Esp.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rol.etiqueta,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.tinta,
                    ),
                  ),
                  Text(
                    rol.descripcion,
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
    );
  }
}

/// Un dato para dictar o copiar: monoespaciado, grande y seleccionable.
class _Credencial extends StatelessWidget {
  const _Credencial({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  final String etiqueta, valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.md,
        vertical: Esp.sm + 2,
      ),
      decoration: BoxDecoration(
        color: destacado ? p.bienLavado : p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: destacado ? p.bien : p.borde),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: TextStyle(fontSize: 13, color: p.tinta3)),
                SelectableText(
                  valor,
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: destacado ? 1.2 : 0,
                    color: p.tinta,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            icon: Icon(Icons.copy_outlined, size: 18, color: p.tinta3),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valor));
              confirmarGuardado(context, '$etiqueta copiado');
            },
          ),
        ],
      ),
    );
  }
}
