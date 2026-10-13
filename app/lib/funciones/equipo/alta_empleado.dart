import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../dominio/equipo.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';
import '../../ui/formulario.dart';

/// Dar de alta a un empleado: la cuenta con la que va a entrar.
///
/// Termina mostrando la clave una sola vez. No es un descuido: la clave no
/// se guarda en ningún lado, ni siquiera nosotros podemos leerla después.
/// Si se pierde, se genera otra desde la ficha de la persona.
class HojaAltaEmpleado extends ConsumerStatefulWidget {
  const HojaAltaEmpleado({super.key, this.zona});

  /// Si se entra desde una zona, queda puesta.
  final Zona? zona;

  static Future<void> abrir(
    BuildContext context,
    WidgetRef ref, {
    Zona? zona,
  }) async {
    final creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 580),
      builder: (_) => HojaAltaEmpleado(zona: zona),
    );
    if (creada == true) {
      ref.invalidate(equipoProvider);
      ref.invalidate(zonasProvider);
    }
  }

  @override
  ConsumerState<HojaAltaEmpleado> createState() => _HojaAltaEmpleadoState();
}

class _HojaAltaEmpleadoState extends ConsumerState<HojaAltaEmpleado> {
  late AltaMiembro _a = AltaMiembro(zonaId: widget.zona?.id);
  Map<String, String> _errores = {};
  String? _error;
  bool _creando = false;
  CuentaCreada? _creada;

  /// El usuario se sugiere solo mientras no lo escriban a mano.
  bool _emailAMano = false;

  void _nombre(String x) {
    setState(() {
      final slug = ref.read(miAgenciaProvider).value?.slug ?? '';
      _a = _a.copiar(
        nombre: x,
        email: _emailAMano ? null : AltaMiembro.sugerirEmail(x, slug),
      );
    });
  }

  Future<void> _crear() async {
    final errores = _a.validar();
    setState(() {
      _errores = errores;
      _error = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _creando = true);
    try {
      final cuenta = await ref
          .read(repositorioProvider)
          .crearCuentaEmpleado(_a);
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
                child: Text(
                  creada == null
                      ? widget.zona == null
                            ? 'Nuevo empleado'
                            : 'Nuevo en ${widget.zona!.nombre}'
                      : '${_a.nombre.split(' ').first} ya puede entrar',
                  style: Theme.of(context).textTheme.headlineSmall,
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
    FilaCampos(
      children: [
        CampoTexto(
          etiqueta: 'Nombre',
          obligatorio: true,
          valor: _a.nombre,
          capitalizar: true,
          error: _errores['nombre'],
          onCambio: _nombre,
        ),
        CampoTexto(
          etiqueta: 'Usuario',
          obligatorio: true,
          ayuda: 'Con el que va a entrar',
          valor: _a.email,
          error: _errores['email'],
          onCambio: (x) {
            _emailAMano = x.trim().isNotEmpty;
            _a = _a.copiar(email: x);
          },
        ),
      ],
    ),
    const SizedBox(height: Esp.lg),
    Text(
      '¿Qué va a poder hacer?',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: p.tinta,
      ),
    ),
    const SizedBox(height: Esp.sm),
    for (final r in RolMembresia.values)
      if (r != RolMembresia.owner) ...[
        _OpcionRol(
          rol: r,
          activo: _a.rol == r,
          onTap: () => setState(() => _a = _a.copiar(rol: r)),
        ),
        const SizedBox(height: Esp.xs),
      ],
    const SizedBox(height: Esp.md),
    _ElegirZona(
      elegida: _a.zonaId,
      onElegir: (id) => setState(
        () => _a = id == null
            ? _a.copiar(limpiarZona: true)
            : _a.copiar(zonaId: id),
      ),
    ),
    if (_error != null) ...[
      const SizedBox(height: Esp.md),
      AvisoError(mensaje: _error!),
    ],
    const SizedBox(height: Esp.lg),
    BotoneraFormulario(
      guardando: _creando,
      etiquetaGuardar: 'Crear la cuenta',
      onCancelar: () => Navigator.pop(context, false),
      onGuardar: _crear,
    ),
  ];

  List<Widget> _credencial(Paleta p, CuentaCreada c) => [
    Text(
      c.clave == null
          ? 'Esa persona ya tenía cuenta en el sistema: le dimos acceso a la '
                'agencia y sigue entrando con la clave que ya usaba.'
          : 'Anotá la clave ahora. No queda guardada en ningún lado: si se '
                'pierde, se genera otra desde su ficha.',
      style: TextStyle(fontSize: 14, height: 1.45, color: p.tinta2),
    ),
    const SizedBox(height: Esp.lg),
    _Credencial(etiqueta: 'Usuario', valor: c.email),
    if (c.clave != null) ...[
      const SizedBox(height: Esp.sm),
      _Credencial(etiqueta: 'Clave', valor: c.clave!, destacado: true),
    ],
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Listo'),
          ),
        ),
      ],
    ),
  ];
}

class _ElegirZona extends ConsumerWidget {
  const _ElegirZona({required this.elegida, required this.onElegir});

  final String? elegida;
  final ValueChanged<String?> onElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final zonas = ref.watch(zonasProvider).value ?? const <Zona>[];
    if (zonas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿En qué zona?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: p.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Es para ordenar la pizarra. No cambia lo que puede ver.',
          style: TextStyle(fontSize: 13, color: p.tinta3),
        ),
        const SizedBox(height: Esp.sm),
        Wrap(
          spacing: Esp.sm,
          runSpacing: Esp.sm,
          children: [
            ChipSeleccion(
              etiqueta: 'Sin zona',
              activo: elegida == null,
              onTap: () => onElegir(null),
            ),
            for (final z in zonas)
              ChipSeleccion(
                etiqueta: z.nombre,
                icono: z.dibujo,
                activo: elegida == z.id,
                onTap: () => onElegir(z.id),
              ),
          ],
        ),
      ],
    );
  }
}

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
        duration: Duracion.rapida,
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
