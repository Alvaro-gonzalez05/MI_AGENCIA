import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../ui/componentes.dart';

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

    Widget etiqueta(String texto) => Padding(
      padding: const EdgeInsets.only(left: Esp.xs, bottom: Esp.sm),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.tinta,
        ),
      ),
    );

    final campos = <Widget>[
      if (anchoAmplio) ...[
        Text(
          'Bienvenido de nuevo',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: Esp.sm),
        Text(
          'Ingresá para ver el estado de tu agencia.',
          style: TextStyle(fontSize: 14, color: p.tinta3, height: 1.5),
        ),
        const SizedBox(height: Esp.xxl),
      ],

      etiqueta('Email'),
      TextFormField(
        controller: _email,
        enabled: !cargando,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          hintText: 'vos@tuagencia.com.ar',
          prefixIcon: Icon(Icons.alternate_email_rounded, size: 19),
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
      const SizedBox(height: Esp.lg + 2),

      etiqueta('Contraseña'),
      TextFormField(
        controller: _clave,
        enabled: !cargando,
        obscureText: !_verClave,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _ingresar(),
        decoration: InputDecoration(
          hintText: '••••••••',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _verClave = !_verClave),
            icon: Icon(
              _verClave
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 19,
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

      AnimatedSize(
        duration: Duracion.media,
        curve: Curves.easeOutCubic,
        child: error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: Esp.lg),
                child: Container(
                  padding: const EdgeInsets.all(Esp.md + 2),
                  decoration: BoxDecoration(
                    color: p.criticoLavado,
                    borderRadius: BorderRadius.circular(Curva.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 17,
                        color: p.critico,
                      ),
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
              ),
      ),

      const SizedBox(height: Esp.xl + 4),
      SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: cargando ? null : _ingresar,
          child: AnimatedSwitcher(
            duration: Duracion.media,
            child: cargando
                ? SizedBox(
                    key: const ValueKey('cargando'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: p.tinta2,
                    ),
                  )
                : const Row(
                    key: ValueKey('ingresar'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ingresar', style: TextStyle(fontSize: 15)),
                      SizedBox(width: Esp.sm + 2),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
          ),
        ),
      ),

      const SizedBox(height: Esp.lg + 2),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Esp.md + 2,
            vertical: 6,
          ),
          decoration: ShapeDecoration(
            color: Config.modoDemo ? p.acentoLavado : p.superficieHundida,
            shape: const StadiumBorder(),
          ),
          child: Text(
            Config.modoDemo
                ? 'Modo demo: entrá con cualquier dato'
                : 'Las cuentas las da de alta el administrador',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: p.tinta2,
            ),
          ),
        ),
      ),
    ];

    final formulario = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < campos.length; i++)
            Aparecer(indice: (i / 2).floor(), child: campos[i]),
        ],
      ),
    );

    if (!anchoAmplio) {
      // Movil: portada negra arriba con esquinas redondeadas abajo, y el
      // formulario debajo, como la pantalla de bienvenida de una app.
      return Scaffold(
        backgroundColor: p.fondo,
        body: SingleChildScrollView(
          child: Column(
            children: [
              const _PortadaMovil(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Esp.xl,
                  Esp.xl + 4,
                  Esp.xl,
                  Esp.xl,
                ),
                child: SafeArea(top: false, child: formulario),
              ),
            ],
          ),
        ),
      );
    }

    // En pantallas anchas, panel de marca a la izquierda y formulario a la
    // derecha: llenar 1400 px con un formulario de 380 centrado se ve vacio.
    return Scaffold(
      backgroundColor: p.fondo,
      body: Padding(
        padding: const EdgeInsets.all(Esp.md),
        child: Row(
          children: [
            const Expanded(flex: 5, child: _PanelMarca()),
            Expanded(
              flex: 4,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Esp.xxl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: formulario,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.tamano = 40});
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
            color: p.acento,
            borderRadius: BorderRadius.circular(tamano * 0.32),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/icono/icono.png',
            semanticLabel: 'Mi Agencia',
          ),
        ),
        SizedBox(width: tamano * 0.3),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Mi ',
                style: TextStyle(color: p.sobreNegro),
              ),
              TextSpan(
                text: 'Agencia',
                style: TextStyle(color: p.acento),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: tamano * 0.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

/// Titular en dos lineas: la segunda en amarillo.
class _Titular extends StatelessWidget {
  const _Titular({required this.tamano});
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Cuánto ganás\n',
            style: TextStyle(color: p.sobreNegro),
          ),
          TextSpan(
            text: 'de verdad.',
            style: TextStyle(color: p.acento),
          ),
        ],
      ),
      style: TextStyle(
        fontSize: tamano,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -tamano * 0.035,
      ),
    );
  }
}

class _PortadaMovil extends StatelessWidget {
  const _PortadaMovil();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.negro,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(Curva.xl + 6),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _AnillosPainter(p.acento)),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Esp.xl,
                Esp.lg,
                Esp.xl,
                Esp.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Aparecer(child: _Logo(tamano: 36)),
                  const SizedBox(height: Esp.xxxl),
                  const Aparecer(indice: 1, child: _Titular(tamano: 36)),
                  const SizedBox(height: Esp.md),
                  Aparecer(
                    indice: 2,
                    child: Text(
                      'Stock, costos y márgenes reales de tu agencia.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: p.sobreNegro2,
                      ),
                    ),
                  ),
                  const SizedBox(height: Esp.xl),
                  const Aparecer(indice: 3, child: _Puntos()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelMarca extends StatelessWidget {
  const _PanelMarca();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.negro,
        borderRadius: BorderRadius.circular(Curva.xl + 6),
      ),
      child: Stack(
        children: [
          // Anillos amarillos tenues: textura sin competir con el titular.
          Positioned.fill(
            child: CustomPaint(painter: _AnillosPainter(p.acento)),
          ),
          Padding(
            padding: const EdgeInsets.all(Esp.xxxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Aparecer(child: _Logo()),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Aparecer(indice: 1, child: _Titular(tamano: 56)),
                    const SizedBox(height: Esp.xl),
                    Aparecer(
                      indice: 2,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Text(
                          'Costos reales, márgenes ajustados por inflación y '
                          'alertas de rotación. Para que el precio de venta no '
                          'sea una corazonada.',
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.6,
                            color: p.sobreNegro2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Aparecer(indice: 3, child: _Puntos()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Puntos extends StatelessWidget {
  const _Puntos();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Wrap(
      spacing: Esp.sm,
      runSpacing: Esp.sm,
      children: [
        _Punto(icono: Icons.speed_rounded, texto: 'Rotación', color: p.bien),
        _Punto(
          icono: Icons.percent_rounded,
          texto: 'Márgenes',
          color: p.acento,
        ),
        _Punto(
          icono: Icons.account_balance_rounded,
          texto: 'Riesgo BCRA',
          color: p.sobreNegro,
        ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.icono, required this.texto, required this.color});
  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.fromLTRB(Esp.sm, Esp.sm, Esp.md + 2, Esp.sm),
      decoration: ShapeDecoration(
        color: p.negroElevado,
        shape: StadiumBorder(side: BorderSide(color: p.negroBorde)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 13, color: color),
          ),
          const SizedBox(width: Esp.sm),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: p.sobreNegro,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circulos concentricos desde la esquina inferior derecha.
class _AnillosPainter extends CustomPainter {
  _AnillosPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width * 0.95, size.height * 0.92);
    final maximo = math.max(size.width, size.height) * 1.1;

    // Resplandor suave detras de los anillos.
    canvas.drawCircle(
      centro,
      maximo * 0.35,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centro, radius: maximo * 0.35)),
    );

    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 7; i++) {
      pincel.color = color.withValues(alpha: 0.16 - i * 0.018);
      canvas.drawCircle(centro, maximo * 0.1 * i, pincel);
    }
  }

  @override
  bool shouldRepaint(_AnillosPainter anterior) => anterior.color != color;
}
