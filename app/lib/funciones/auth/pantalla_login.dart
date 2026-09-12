import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';

class PantallaLogin extends ConsumerStatefulWidget {
  const PantallaLogin({super.key});

  @override
  ConsumerState<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends ConsumerState<PantallaLogin> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  bool _verClave = false;

  @override
  void dispose() {
    _email.dispose();
    _clave.dispose();
    super.dispose();
  }

  void _ingresar() {
    if (!_form.currentState!.validate()) return;
    ref
        .read(sesionProvider.notifier)
        .ingresar(email: _email.text, clave: _clave.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final estado = ref.watch(sesionProvider);
    final cargando = estado is SesionCargando;
    final error = estado is SesionCerrada ? estado.error : null;
    final anchoAmplio = MediaQuery.sizeOf(context).width >= Corte.tablet;

    final formulario = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Esp.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!anchoAmplio) ...[
                  const _Logo(tamano: 44),
                  const SizedBox(height: Esp.xl),
                ],
                Text('Ingresá a tu cuenta',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: Esp.sm),
                Text(
                  'Gestión de stock, costos y rentabilidad de tu agencia.',
                  style: TextStyle(fontSize: 13.5, color: p.tinta3, height: 1.5),
                ),
                const SizedBox(height: Esp.xxl),

                Text('Email',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.tinta2)),
                const SizedBox(height: Esp.sm),
                TextFormField(
                  controller: _email,
                  enabled: !cargando,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'vos@tuagencia.com.ar',
                    prefixIcon: Icon(Icons.alternate_email, size: 18),
                  ),
                  validator: (v) {
                    if (Config.modoDemo) return null;
                    if (v == null || v.trim().isEmpty) {
                      return 'Escribí tu email.';
                    }
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Ese email no parece válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Esp.lg),

                Text('Contraseña',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: p.tinta2)),
                const SizedBox(height: Esp.sm),
                TextFormField(
                  controller: _clave,
                  enabled: !cargando,
                  obscureText: !_verClave,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _ingresar(),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _verClave = !_verClave),
                      icon: Icon(
                        _verClave
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                    ),
                  ),
                  validator: (v) {
                    if (Config.modoDemo) return null;
                    if (v == null || v.isEmpty) return 'Escribí tu contraseña.';
                    return null;
                  },
                ),

                if (error != null) ...[
                  const SizedBox(height: Esp.lg),
                  Container(
                    padding: const EdgeInsets.all(Esp.md),
                    decoration: BoxDecoration(
                      color: p.criticoLavado,
                      borderRadius: BorderRadius.circular(Curva.md),
                      border:
                          Border.all(color: p.critico.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: p.critico),
                        const SizedBox(width: Esp.sm),
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(fontSize: 12.5, color: p.critico),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: Esp.xl),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: cargando ? null : _ingresar,
                    child: cargando
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.acentoTinta,
                            ),
                          )
                        : const Text('Ingresar'),
                  ),
                ),

                const SizedBox(height: Esp.lg),
                Center(
                  child: Text(
                    Config.modoDemo
                        ? 'Modo demo: entrá con cualquier dato'
                        : 'Las cuentas las da de alta el administrador',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: p.tinta3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!anchoAmplio) {
      return Scaffold(backgroundColor: p.fondo, body: formulario);
    }

    // En pantallas anchas, panel de marca a la izquierda y formulario a la
    // derecha: llenar 1400 px con un formulario de 380 centrado se ve vacio.
    return Scaffold(
      backgroundColor: p.fondo,
      body: Row(
        children: [
          const Expanded(flex: 5, child: _PanelMarca()),
          Expanded(
            flex: 4,
            child: Container(color: p.superficie, child: formulario),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.tamano = 36});
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tamano,
          height: tamano,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [p.acento, p.acento.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(tamano * 0.28),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.directions_car_filled,
            size: tamano * 0.52,
            color: p.acentoTinta,
          ),
        ),
        SizedBox(width: tamano * 0.32),
        Text(
          'Mi Agencia',
          style: TextStyle(
            fontSize: tamano * 0.46,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: p.tinta,
          ),
        ),
      ],
    );
  }
}

class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.fondo,
            Color.alphaBlend(p.acento.withValues(alpha: 0.10), p.fondo),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Malla tenue de fondo. Aporta textura sin competir con nada.
          Positioned.fill(
            child: CustomPaint(painter: _MallaPainter(p.borde)),
          ),
          Padding(
            padding: const EdgeInsets.all(Esp.xxxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Logo(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        'Cuánto ganás de verdad\ncon cada unidad.',
                        style: TextStyle(
                          fontSize: 34,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          color: p.tinta,
                        ),
                      ),
                    ),
                    const SizedBox(height: Esp.lg),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        'Costos reales, márgenes ajustados por inflación y '
                        'alertas de rotación. Para que el precio de venta no '
                        'sea una corazonada.',
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: p.tinta2,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _Punto(color: p.bien, texto: 'Rotación'),
                    const SizedBox(width: Esp.xl),
                    _Punto(color: p.observar, texto: 'Márgenes'),
                    const SizedBox(width: Esp.xl),
                    _Punto(color: p.acento, texto: 'Riesgo BCRA'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, required this.texto});
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Esp.sm),
        Text(
          texto,
          style: TextStyle(fontSize: 12.5, color: context.paleta.tinta2),
        ),
      ],
    );
  }
}

class _MallaPainter extends CustomPainter {
  _MallaPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    const paso = 56.0;
    for (var x = 0.0; x < size.width; x += paso) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pincel);
    }
    for (var y = 0.0; y < size.height; y += paso) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pincel);
    }
  }

  @override
  bool shouldRepaint(_MallaPainter anterior) => anterior.color != color;
}
