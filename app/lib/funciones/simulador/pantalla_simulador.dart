import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/motor_calculo.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Simulador de financiamiento (pantalla propia, como en el diseño nuevo).
///
/// Antes vivía adentro de la ficha de cada auto y calculaba siempre con
/// interés directo. Ahora es una herramienta aparte, porque se usa con el
/// cliente sentado enfrente y no siempre sobre una unidad concreta, y tiene
/// los cuatro sistemas con los que trabajan las financieras.
class PantallaSimulador extends ConsumerStatefulWidget {
  const PantallaSimulador({super.key});

  @override
  ConsumerState<PantallaSimulador> createState() => _PantallaSimuladorState();
}

class _PantallaSimuladorState extends ConsumerState<PantallaSimulador> {
  double _monto = 10000000;
  int _cuotas = 12;
  double _tna = 0.72;
  SistemaAmortizacion _sistema = SistemaAmortizacion.frances;

  late final _montoCtrl = TextEditingController(
    text: _monto.round().toString(),
  );
  late final _tnaCtrl = TextEditingController(
    text: (_tna * 100).round().toString(),
  );

  @override
  void initState() {
    super.initState();
    // La tasa mensual configurada por la agencia, llevada a nominal anual:
    // es el número con el que ya venía trabajando.
    final cfg = ref.read(configProvider);
    _tna = cfg.tasaFinanciacionMensual * 12;
    _tnaCtrl.text = (_tna * 100).round().toString();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _tnaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final ancho = MediaQuery.sizeOf(context).width;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;

    final r = Motor.financiacionPor(
      sistema: _sistema,
      monto: _monto,
      cuotas: _cuotas,
      tna: _tna,
    );
    final fija = r.primera == r.ultima;

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.sm, margen, Esp.xxl),
      children: [
        Aparecer(
          child: const CabeceraPantalla(
            titulo: 'Simulador de financiamiento',
            subtitulo: 'Calculá la cuota de forma rápida y sencilla.',
          ),
        ),
        const SizedBox(height: Esp.lg),
        Aparecer(
          indice: 1,
          child: Tarjeta(
            padding: const EdgeInsets.all(Esp.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CampoFormulario(
                  etiqueta: 'Monto a financiar',
                  error: _monto <= 0 ? 'Tiene que ser mayor a cero.' : null,
                  hijo: TextFormField(
                    controller: _montoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 18,
                    ),
                    onChanged: (t) =>
                        setState(() => _monto = double.tryParse(t) ?? 0),
                    decoration: InputDecoration(
                      prefixText: r'$ ',
                      prefixStyle: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 18,
                        color: p.tinta3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Esp.lg),

                Text(
                  'Sistema de amortización',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.tinta,
                  ),
                ),
                const SizedBox(height: Esp.sm),
                Wrap(
                  spacing: Esp.sm,
                  runSpacing: Esp.sm,
                  children: [
                    for (final s in SistemaAmortizacion.values)
                      ChipSeleccion(
                        etiqueta: s.etiqueta,
                        activo: _sistema == s,
                        onTap: () => setState(() => _sistema = s),
                      ),
                  ],
                ),
                const SizedBox(height: Esp.xs + 2),
                Text(
                  _sistema.explicacion,
                  style: TextStyle(fontSize: 14, color: p.tinta2),
                ),
                const SizedBox(height: Esp.lg),

                LayoutBuilder(
                  builder: (context, restricciones) {
                    final tasa = CampoFormulario(
                      etiqueta: 'Tasa anual (TNA)',
                      ayuda: 'Mensual: ${Fmt.porcentaje(_tna / 12)}',
                      hijo: TextFormField(
                        controller: _tnaCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 18,
                        ),
                        onChanged: (t) => setState(
                          () => _tna = (double.tryParse(t) ?? 0) / 100,
                        ),
                        decoration: const InputDecoration(suffixText: '%'),
                      ),
                    );
                    final cuotas = CampoFormulario(
                      etiqueta: 'Cuotas',
                      hijo: _Contador(
                        valor: _cuotas,
                        onCambio: (v) => setState(() => _cuotas = v),
                      ),
                    );
                    return restricciones.maxWidth >= 560
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: tasa),
                              const SizedBox(width: Esp.md),
                              Expanded(child: cuotas),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              tasa,
                              const SizedBox(height: Esp.md),
                              cuotas,
                            ],
                          );
                  },
                ),

                const SizedBox(height: Esp.xl),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Esp.xl),
                  decoration: BoxDecoration(
                    color: p.negro,
                    borderRadius: BorderRadius.circular(Curva.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fija ? 'Cuota mensual' : 'Primera cuota (van bajando)',
                        style: TextStyle(fontSize: 15, color: p.sobreNegro2),
                      ),
                      const SizedBox(height: Esp.xs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Fmt.pesos(
                            _sistema == SistemaAmortizacion.global
                                ? r.total
                                : r.primera,
                          ),
                          style: TextStyle(
                            fontFamily: TemaApp.titulo,
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: p.acento,
                          ),
                        ),
                      ),
                      if (!fija && _sistema != SistemaAmortizacion.global) ...[
                        const SizedBox(height: Esp.xs),
                        Text(
                          'Última cuota: ${Fmt.pesos(r.ultima)}',
                          style: TextStyle(fontSize: 15, color: p.sobreNegro2),
                        ),
                      ],
                      const SizedBox(height: Esp.md),
                      Divider(color: p.negroBorde, height: 1),
                      const SizedBox(height: Esp.md),
                      Wrap(
                        spacing: Esp.xl,
                        runSpacing: Esp.sm,
                        children: [
                          _Total(
                            etiqueta: 'Total a pagar',
                            valor: Fmt.pesos(r.total),
                          ),
                          _Total(
                            etiqueta: 'Intereses',
                            valor: Fmt.pesos(r.interes),
                          ),
                          _Total(
                            etiqueta: 'Sobre el capital',
                            valor: _monto > 0
                                ? Fmt.porcentaje(r.interes / _monto)
                                : Fmt.sinDato,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Esp.md),
                Text(
                  'Simulación orientativa: no incluye gastos de otorgamiento, '
                  'seguros ni sellados.',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Menos / número / más. Es el control del diseño, y de paso evita tipear
/// un número de cuotas imposible.
class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.onCambio});

  final int valor;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: p.superficieElevada,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.bordeFuerte, width: 1.6),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: valor > 1 ? () => onCambio(valor - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 24),
            tooltip: 'Una cuota menos',
          ),
          Expanded(
            child: Center(
              child: Text(
                '$valor',
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: p.tinta,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: valor < 120 ? () => onCambio(valor + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 24),
            tooltip: 'Una cuota más',
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.etiqueta, required this.valor});

  final String etiqueta, valor;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 14, color: p.sobreNegro2)),
        Text(
          valor,
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.sobreNegro,
          ),
        ),
      ],
    );
  }
}
