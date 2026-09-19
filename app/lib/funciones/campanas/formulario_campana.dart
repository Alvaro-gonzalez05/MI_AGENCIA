import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/campanas.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Armado de una campaña.
///
/// Se escribe en texto plano y el sistema arma el HTML. Pedirle etiquetas a
/// un vendedor no tiene sentido, y un editor visual completo sería otro
/// proyecto: con párrafos y dos variables alcanza para lo que una agencia
/// manda de verdad.
class FormularioCampana extends ConsumerStatefulWidget {
  const FormularioCampana({super.key});

  @override
  ConsumerState<FormularioCampana> createState() => _FormularioCampanaState();
}

class _FormularioCampanaState extends ConsumerState<FormularioCampana> {
  AltaCampana _c = const AltaCampana();
  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _errorGeneral;

  final _cuerpoCtrl = TextEditingController();

  @override
  void dispose() {
    _cuerpoCtrl.dispose();
    super.dispose();
  }

  void _insertarVariable(String v) {
    final t = _cuerpoCtrl.text;
    final pos = _cuerpoCtrl.selection.baseOffset;
    final corte = pos < 0 ? t.length : pos;
    final nuevo = t.substring(0, corte) + v + t.substring(corte);
    _cuerpoCtrl.value = TextEditingValue(
      text: nuevo,
      selection: TextSelection.collapsed(offset: corte + v.length),
    );
    setState(() => _c = _c.copiar(cuerpo: nuevo));
  }

  Future<void> _guardar() async {
    final errores = _c.validar();
    setState(() {
      _errores = errores;
      _errorGeneral = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearCampana(_c);
      ref.invalidate(campanasProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorGeneral = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final cantidad = ref.watch(destinatariosProvider).value;
    final conEmail = ref.watch(conEmailProvider).value ?? 0;

    return Scaffold(
      backgroundColor: p.fondo,
      appBar: AppBar(title: const Text('Nueva campaña')),
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
                    Tarjeta(
                      padding: const EdgeInsets.all(Esp.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CabeceraBloque(
                            titulo: 'El mensaje',
                            descripcion: cantidad == null
                                ? null
                                : cantidad == 0
                                // Con cero se explica por qué, en vez de un
                                // "0 personas" que parece un error.
                                ? textoAudiencia(0, conEmail)
                                : 'Lo van a recibir $cantidad '
                                      '${cantidad == 1 ? 'persona' : 'personas'}',
                          ),
                          const SizedBox(height: Esp.lg),

                          CampoFormulario(
                            etiqueta: 'Nombre de la campaña',
                            ayuda: 'Solo para vos, no lo ve el destinatario',
                            error: _errores['nombre'],
                            hijo: TextFormField(
                              onChanged: (s) =>
                                  setState(() => _c = _c.copiar(nombre: s)),
                              decoration: const InputDecoration(
                                hintText: 'Pickups en stock — septiembre',
                              ),
                            ),
                          ),

                          const SizedBox(height: Esp.lg),
                          CampoFormulario(
                            etiqueta: 'Asunto',
                            ayuda: 'Es lo único que se ve antes de abrirlo',
                            error: _errores['asunto'],
                            hijo: TextFormField(
                              onChanged: (s) =>
                                  setState(() => _c = _c.copiar(asunto: s)),
                              decoration: const InputDecoration(
                                hintText:
                                    '{{nombre}}, entró la pickup que buscabas',
                              ),
                            ),
                          ),

                          const SizedBox(height: Esp.lg),
                          CampoFormulario(
                            etiqueta: 'Mensaje',
                            error: _errores['cuerpo'],
                            hijo: TextFormField(
                              controller: _cuerpoCtrl,
                              maxLines: 8,
                              onChanged: (s) =>
                                  setState(() => _c = _c.copiar(cuerpo: s)),
                              decoration: const InputDecoration(
                                hintText:
                                    'Hola {{nombre}},\n\nTe escribo porque entró '
                                    'una unidad que puede interesarte…',
                              ),
                            ),
                          ),

                          const SizedBox(height: Esp.md),
                          Text(
                            'Insertar en el mensaje',
                            style: TextStyle(fontSize: 11.5, color: p.tinta3),
                          ),
                          const SizedBox(height: Esp.sm),
                          Wrap(
                            spacing: Esp.sm,
                            runSpacing: Esp.sm,
                            children: [
                              for (final v in AltaCampana.variables.entries)
                                ChipSeleccion(
                                  etiqueta: v.key,
                                  activo: false,
                                  onTap: () => _insertarVariable(v.key),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: Esp.md),
                    _previsualizacion(),

                    if (_errorGeneral != null) ...[
                      const SizedBox(height: Esp.md),
                      AvisoError(mensaje: _errorGeneral!),
                    ],

                    const SizedBox(height: Esp.xl),
                    BotoneraFormulario(
                      guardando: _guardando,
                      etiquetaGuardar: 'Guardar borrador',
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

  /// Cómo le va a llegar, con las variables ya reemplazadas por un ejemplo.
  Widget _previsualizacion() {
    final p = context.paleta;
    if (_c.cuerpo.trim().isEmpty) return const SizedBox.shrink();

    String ejemplo(String s) => s
        .replaceAll(RegExp(r'\{\{\s*nombre\s*\}\}'), 'Laura')
        .replaceAll(RegExp(r'\{\{\s*agencia\s*\}\}'), 'tu agencia');

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Cómo se ve',
            descripcion: 'Con las variables reemplazadas por un ejemplo',
          ),
          const SizedBox(height: Esp.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Esp.lg),
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
              border: Border.all(color: p.borde),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ejemplo(_c.asunto.isEmpty ? '(sin asunto)' : _c.asunto),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.tinta,
                  ),
                ),
                const SizedBox(height: Esp.md),
                Text(
                  ejemplo(_c.cuerpo),
                  style: TextStyle(fontSize: 13, color: p.tinta2, height: 1.6),
                ),
                const SizedBox(height: Esp.md),
                Divider(color: p.borde, height: 1),
                const SizedBox(height: Esp.sm),
                Text(
                  'Recibís este mail porque dejaste tus datos en tu agencia. '
                  'Si no querés recibir más, respondé con la palabra BAJA.',
                  style: TextStyle(fontSize: 11, color: p.tinta3, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.gpp_good_outlined, size: 15, color: p.tinta3),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Text(
                  'El pie con la opción de baja se agrega solo y no se puede '
                  'sacar. Sin eso, los mails terminan en spam y la reputación '
                  'del dominio se quema para siempre.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: p.tinta3,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
