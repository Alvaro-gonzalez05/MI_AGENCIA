import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Alta de una agencia cliente.
class FormularioAgencia extends ConsumerStatefulWidget {
  const FormularioAgencia({super.key});

  @override
  ConsumerState<FormularioAgencia> createState() => _FormularioAgenciaState();
}

class _FormularioAgenciaState extends ConsumerState<FormularioAgencia> {
  AltaAgencia _a = const AltaAgencia();
  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;

  Future<void> _guardar() async {
    final errores = _a.validar();
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearAgencia(_a);
      ref.invalidate(agenciasProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorGeneral = _mensaje(e);
      });
    }
  }

  static String _mensaje(Object e) {
    final t = e.toString();
    if (t.contains('agencias_slug_key') || t.contains('duplicate key')) {
      return 'Ya existe una agencia con ese nombre.';
    }
    if (t.contains('row-level security') || t.contains('permission denied')) {
      return 'Solo la cuenta de desarrollador puede dar de alta agencias.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá internet y probá de nuevo.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(title: const Text('Nueva agencia')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Esp.xl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bloqueDatos(),
                    const SizedBox(height: Esp.md),
                    _bloqueDueno(),
                    const SizedBox(height: Esp.md),
                    _bloquePlan(),
                    if (_errorGeneral != null) ...[
                      const SizedBox(height: Esp.md),
                      AvisoError(mensaje: _errorGeneral!),
                    ],
                    const SizedBox(height: Esp.xl),
                    BotoneraFormulario(
                      guardando: _guardando,
                      etiquetaGuardar: 'Crear e invitar',
                      onCancelar: () => Navigator.of(context).pop(false),
                      onGuardar: _guardar,
                    ),
                    const SizedBox(height: Esp.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bloqueDatos() {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'La agencia'),
          const SizedBox(height: Esp.lg),

          CampoFormulario(
            etiqueta: 'Nombre',
            error: _errores['nombre'],
            ayuda: _a.slug.isEmpty ? null : 'Identificador: ${_a.slug}',
            hijo: TextFormField(
              textCapitalization: TextCapitalization.words,
              onChanged: (s) => setState(() => _a = _a.copiar(nombre: s)),
              decoration: const InputDecoration(
                hintText: 'Automotores del Oeste',
              ),
            ),
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'CUIT',
            ayuda: 'Opcional — 11 dígitos',
            error: _errores['cuit'],
            hijo: TextFormField(
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: const TextStyle(fontFamily: TemaApp.mono),
              onChanged: (s) => setState(() => _a = _a.copiar(cuit: s)),
            ),
          ),

          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Expanded(
                child: CampoFormulario(
                  etiqueta: 'Localidad',
                  hijo: TextFormField(
                    textCapitalization: TextCapitalization.words,
                    onChanged: (s) =>
                        setState(() => _a = _a.copiar(localidad: s)),
                  ),
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: CampoFormulario(
                  etiqueta: 'Provincia',
                  hijo: TextFormField(
                    textCapitalization: TextCapitalization.words,
                    onChanged: (s) =>
                        setState(() => _a = _a.copiar(provincia: s)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Teléfono',
            ayuda: 'Opcional',
            hijo: TextFormField(
              keyboardType: TextInputType.phone,
              style: TextStyle(fontFamily: TemaApp.mono, color: p.tinta),
              onChanged: (s) => setState(() => _a = _a.copiar(telefono: s)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueDueno() {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Quién la administra',
            descripcion: 'Se le manda una invitación a ese email',
          ),
          const SizedBox(height: Esp.lg),

          CampoFormulario(
            etiqueta: 'Email del dueño',
            error: _errores['emailDueno'],
            hijo: TextFormField(
              keyboardType: TextInputType.emailAddress,
              onChanged: (s) => setState(() => _a = _a.copiar(emailDueno: s)),
              decoration: const InputDecoration(
                hintText: 'dueño@suagencia.com.ar',
              ),
            ),
          ),

          const SizedBox(height: Esp.md),
          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: p.tinta3),
                const SizedBox(width: Esp.md),
                Expanded(
                  child: Text(
                    'No hace falta crearle la cuenta: cuando se registre con '
                    'ese email, la base lo vincula sola a esta agencia como '
                    'dueño. La invitación vale 7 días.',
                    style: TextStyle(
                      fontSize: 12,
                      color: p.tinta3,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Email de contacto de la agencia',
            ayuda: 'Opcional — si es distinto del anterior',
            error: _errores['emailContacto'],
            hijo: TextFormField(
              keyboardType: TextInputType.emailAddress,
              onChanged: (s) =>
                  setState(() => _a = _a.copiar(emailContacto: s)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloquePlan() {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'Plan y vigencia'),
          const SizedBox(height: Esp.lg),
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.sm,
            children: [
              for (final plan in ['basico', 'full'])
                ChipSeleccion(
                  etiqueta: plan == 'basico' ? 'Básico' : 'Full',
                  activo: _a.plan == plan,
                  onTap: () => setState(() => _a = _a.copiar(plan: plan)),
                ),
            ],
          ),

          const SizedBox(height: Esp.lg),
          CampoFormulario(
            etiqueta: 'Paga hasta',
            ayuda: _a.vigenteHasta == null ? 'Sin fecha: la cuenta no vence' : 'Pasada esa fecha queda marcada como vencida, pero sigue entrando',
            hijo: Row(
              children: [
                Expanded(
                  child: SelectorFecha(
                    valor: _a.vigenteHasta,
                    // A diferencia del resto de las fechas de la app, esta
                    // mira al futuro: es hasta cuándo está paga.
                    hasta: DateTime.now().add(const Duration(days: 365 * 5)),
                    onCambio: (f) =>
                        setState(() => _a = _a.copiar(vigenteHasta: f)),
                  ),
                ),
                if (_a.vigenteHasta != null)
                  IconButton(
                    tooltip: 'Sin vencimiento',
                    icon: Icon(Icons.close, size: 18, color: p.tinta3),
                    onPressed: () => setState(
                      () => _a = const AltaAgencia().copiar(
                        nombre: _a.nombre,
                        cuit: _a.cuit,
                        emailContacto: _a.emailContacto,
                        telefono: _a.telefono,
                        localidad: _a.localidad,
                        provincia: _a.provincia,
                        plan: _a.plan,
                        emailDueno: _a.emailDueno,
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
