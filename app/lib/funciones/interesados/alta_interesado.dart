import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../datos/repositorio.dart';
import '../../dominio/alta_interesado.dart';
import '../../dominio/bcra.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import '../../ui/confirmacion.dart';
import '../../ui/formulario.dart';
import 'ficha_interesado.dart';
import 'informe_pdf.dart';

class FormularioInteresado extends ConsumerStatefulWidget {
  const FormularioInteresado({super.key});
  @override
  ConsumerState<FormularioInteresado> createState() =>
      _FormularioInteresadoState();
}

class _FormularioInteresadoState extends ConsumerState<FormularioInteresado> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController(),
      _cuit = TextEditingController(),
      _telefono = TextEditingController(),
      _email = TextEditingController(),
      _localidad = TextEditingController(),
      _presupuesto = TextEditingController(),
      _notas = TextEditingController();
  final _solicitud =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  int _paso = 0;
  bool _ocupado = false, _financia = false, _pdfGuardado = false;

  /// Consentimiento para mails. Arranca en no: se pregunta, no se asume.
  bool _aceptaMails = false;
  String? _vehiculo, _error;
  String _progreso = '';
  Interesado? _guardado;

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _cuit,
      _telefono,
      _email,
      _localidad,
      _presupuesto,
      _notas,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opcional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _evaluar() async {
    if (_ocupado) return;
    if (_guardado == null && !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _ocupado = true;
      _error = null;
      _progreso = 'Guardando cliente e interés…';
    });
    final repo = ref.read(repositorioProvider);
    try {
      _guardado ??= await repo.crearInteresado(
        AltaInteresado(
          solicitud: _solicitud,
          nombre: _nombre.text,
          cuit: _cuit.text.replaceAll(RegExp(r'\D'), ''),
          telefono: _opcional(_telefono),
          email: _opcional(_email),
          localidad: _opcional(_localidad),
          vehiculoId: _vehiculo,
          presupuesto: double.tryParse(
            _presupuesto.text.replaceAll('.', '').replaceAll(',', '.'),
          ),
          financiacion: _financia,
          notas: _opcional(_notas),
          aceptaMarketing: _aceptaMails,
        ),
      );
      ref.invalidate(interesadosProvider);
      if (!mounted) return;
      setState(() {
        _paso = 2;
        _progreso = 'Consultando deudas y cheques en el BCRA…';
      });
      if (_guardado!.consulta == null || _guardado!.consulta!.vencida) {
        final c = await repo.consultarBcra(
          clienteId: _guardado!.clienteId,
          cuit: _guardado!.cuit!,
        );
        _guardado = _guardado!.copiar(consulta: c);
        ref.invalidate(interesadosProvider);
      }
      if (!mounted) return;
      setState(() => _progreso = 'Preparando y archivando el informe PDF…');
      final usuario = ref.read(usuarioProvider);
      final bytes = await InformeCrediticio.generar(
        interesado: _guardado!,
        agencia:
            ref.read(miAgenciaProvider).value?.nombre ?? usuario?.agenciaNombre,
        generadoPor: usuario?.nombre,
      );
      await repo.guardarInforme(_guardado!, bytes);
      if (!mounted) return;
      setState(() => _pdfGuardado = true);
      confirmarGuardado(context, 'Cliente, evaluación e informe guardados');
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _salir() async {
    if (_ocupado) return;
    if (_guardado == null &&
        [
          _nombre,
          _cuit,
          _telefono,
          _email,
          _localidad,
          _presupuesto,
          _notas,
        ].any((c) => c.text.isNotEmpty)) {
      final salir = await confirmarAccion(
        context,
        titulo: '¿Salir sin guardar?',
        descripcion: 'Los datos que escribiste todavía no se guardaron.',
        confirmar: 'Salir',
        cancelar: 'Seguir cargando',
        icono: Icons.exit_to_app_rounded,
        peligrosa: true,
      );
      if (salir != true) return;
    }
    if (mounted) Navigator.pop(context, _guardado);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _salir();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nuevo interesado'),
          leading: IconButton(
            onPressed: _ocupado ? null : _salir,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Row(
                  children: [
                    for (var n = 0; n < 3; n++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                height: 4,
                                decoration: BoxDecoration(
                                  color: n <= _paso ? p.acento : p.borde,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  '01 · Cliente',
                                  '02 · Interés',
                                  '03 · Evaluación',
                                ][n],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: n == _paso ? p.tinta : p.tinta3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                if (_paso < 2)
                  Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animacion) => FadeTransition(
                        opacity: animacion,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0.035, 0),
                            end: Offset.zero,
                          ).animate(animacion),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_paso),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _paso == 0
                                ? 'Conocé a tu próximo cliente'
                                : '¿Qué está buscando?',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _paso == 0
                                ? 'Cargá sus datos. Usamos el CUIT/CUIL para consultar el BCRA.'
                                : 'Podés vincular una unidad ahora o dejarla para más adelante.',
                            style: TextStyle(color: p.tinta3),
                          ),
                          const SizedBox(height: 24),
                          if (_paso == 0) ...[
                            _campo(
                              _nombre,
                              'Nombre y apellido',
                              obligatorio: true,
                            ),
                            _campo(
                              _cuit,
                              'CUIT / CUIL',
                              tipo: TextInputType.number,
                              validar: (v) =>
                                  cuitValido(
                                    (v ?? '').replaceAll(RegExp(r'\D'), ''),
                                  )
                                  ? null
                                  : 'Revisá los 11 dígitos y el verificador.',
                            ),
                            _campo(
                              _telefono,
                              'Teléfono (opcional)',
                              tipo: TextInputType.phone,
                            ),
                            _campo(
                              _email,
                              'Email (opcional)',
                              tipo: TextInputType.emailAddress,
                              validar: (v) =>
                                  v == null ||
                                      v.trim().isEmpty ||
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(v.trim())
                                  ? null
                                  : 'Revisá el email.',
                            ),
                            // Se pregunta, no se asume (checklist 4.1). Solo se
                            // habilita con un email cargado: sin email no hay a
                            // donde mandar nada.
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _email,
                              builder: (context, valor, _) {
                                final hayEmail = valor.text.trim().isNotEmpty;
                                return SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Acepta recibir novedades por email',
                                  ),
                                  subtitle: Text(
                                    hayEmail
                                        ? 'Preguntáselo. Solo a quien acepta le llegan las campañas.'
                                        : 'Cargá un email para poder marcarlo.',
                                  ),
                                  value: hayEmail && _aceptaMails,
                                  onChanged: _ocupado || !hayEmail
                                      ? null
                                      : (v) => setState(() => _aceptaMails = v),
                                );
                              },
                            ),
                            _campo(_localidad, 'Localidad (opcional)'),
                          ] else ...[
                            ref
                                .watch(inventarioProvider)
                                .when(
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, _) => TextButton.icon(
                                    onPressed: () =>
                                        ref.invalidate(inventarioProvider),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text(
                                      'Reintentar cargar unidades',
                                    ),
                                  ),
                                  data: (unidades) =>
                                      DropdownButtonFormField<String>(
                                        initialValue: _vehiculo,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Unidad de interés',
                                        ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: '',
                                            child: Text(
                                              'Todavía sin unidad definida',
                                            ),
                                          ),
                                          for (final v in unidades.where(
                                            (v) => !v.vendido,
                                          ))
                                            DropdownMenuItem(
                                              value: v.id,
                                              child: Text(
                                                '${v.codigo} · ${v.titulo}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: _ocupado
                                            ? null
                                            : (v) => setState(
                                                () => _vehiculo = v == ''
                                                    ? null
                                                    : v,
                                              ),
                                      ),
                                ),
                            const SizedBox(height: 20),
                            _campo(
                              _presupuesto,
                              'Presupuesto en pesos (opcional)',
                              tipo: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              validar: (v) {
                                if (v == null || v.isEmpty) return null;
                                final n = double.tryParse(
                                  v.replaceAll('.', '').replaceAll(',', '.'),
                                );
                                return n != null && n.isFinite && n > 0
                                    ? null
                                    : 'Ingresá un importe mayor a cero.';
                              },
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Necesita financiación'),
                              value: _financia,
                              onChanged: _ocupado
                                  ? null
                                  : (v) => setState(() => _financia = v),
                            ),
                            _campo(
                              _notas,
                              'Qué busca / notas (opcional)',
                              lineas: 3,
                            ),
                            const Text(
                              'Al continuar se guardan el cliente y su interés, se consulta el BCRA y se archiva el PDF en la agencia.',
                            ),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_paso == 2) ...[
                  if (!_ocupado && _pdfGuardado)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SelloConfirmacion(),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    _guardado!.nombre,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _pdfGuardado
                        ? 'La ficha y el informe ya están en tu agencia.'
                        : 'Cliente e interés guardados.',
                  ),
                  if (_guardado!.consulta case final c?) ...[
                    const SizedBox(height: 20),
                    Tarjeta(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Pastilla(
                            texto: c.semaforo.etiqueta,
                            color: c.semaforo.color(p),
                            lavado: c.semaforo.lavado(p),
                          ),
                          const SizedBox(height: 12),
                          Text(c.recomendacion),
                          for (final motivo in c.motivos)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('• $motivo'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
                if (_ocupado)
                  Semantics(
                    liveRegion: true,
                    child: Column(
                      children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(_progreso),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  AvisoError(
                    mensaje:
                        '${_guardado == null ? '' : 'Tus datos están guardados. '}${_error!}',
                  ),
                  const SizedBox(height: 16),
                ],
                if (_paso < 2)
                  Row(
                    children: [
                      if (_paso == 1) ...[
                        OutlinedButton(
                          onPressed: _ocupado
                              ? null
                              : () => setState(() {
                                  _paso = 0;
                                  _error = null;
                                }),
                          child: const Text('Atrás'),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _ocupado
                              ? null
                              : () {
                                  if (_paso == 0) {
                                    if (_form.currentState!.validate()) {
                                      FocusScope.of(context).unfocus();
                                      setState(() => _paso = 1);
                                    }
                                  } else {
                                    _evaluar();
                                  }
                                },
                          icon: Icon(
                            _paso == 0
                                ? Icons.arrow_forward_rounded
                                : Icons.fact_check_outlined,
                          ),
                          label: Text(
                            _paso == 0 ? 'Continuar' : 'Guardar y evaluar',
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_paso == 2 && !_ocupado) ...[
                  if (!_pdfGuardado)
                    FilledButton.icon(
                      onPressed: _evaluar,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _guardado!.consulta == null
                            ? 'Reintentar consulta'
                            : 'Reintentar guardar PDF',
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FichaInteresado(interesado: _guardado!),
                      ),
                    ),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Ver ficha e informes'),
                  ),
                  TextButton(
                    onPressed: _salir,
                    child: const Text('Volver a interesados'),
                  ),
                ],
                if (Config.modoDemo)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Modo demo: los datos duran esta sesión. La consulta real requiere iniciar sesión.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo(
    TextEditingController c,
    String etiqueta, {
    bool obligatorio = false,
    TextInputType? tipo,
    String? Function(String?)? validar,
    int lineas = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: c,
      enabled: !_ocupado,
      maxLines: lineas,
      keyboardType: tipo,
      textCapitalization: tipo == null
          ? TextCapitalization.words
          : TextCapitalization.none,
      decoration: InputDecoration(labelText: etiqueta),
      inputFormatters: c == _cuit
          ? [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9\- ]')),
              LengthLimitingTextInputFormatter(15),
            ]
          : null,
      validator:
          validar ??
          (v) => obligatorio && (v ?? '').trim().length < 2
              ? 'Ingresá el nombre y apellido.'
              : null,
    ),
  );
}
