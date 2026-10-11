import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/cobranzas.dart';
import '../../dominio/modelos.dart';
import '../../dominio/motor_calculo.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// El plan de pagos de un cliente: cuánto debe, qué cuota viene y cuáles
/// están vencidas.
///
/// La agencia financia de su bolsillo. Hasta ahora eso vivía en un cuaderno
/// y el cuaderno no avisa: acá cada cuota tiene su vencimiento, y lo que se
/// atrasó aparece en rojo y en el Inicio.
class BloquePlanDePagos extends ConsumerWidget {
  const BloquePlanDePagos({super.key, required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final planes = ref.watch(planesDeProvider(interesado.id)).value ?? const [];

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Plan de pagos',
                  descripcion: planes.isEmpty
                      ? 'Si le financiás, acá se lleva la cuenta'
                      : '${planes.length} '
                            '${planes.length == 1 ? 'plan' : 'planes'}',
                ),
              ),
              const SizedBox(width: Esp.sm),
              OutlinedButton.icon(
                onPressed: () => HojaPlanDePagos.abrir(context, interesado),
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('Nuevo plan'),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),

          if (planes.isEmpty)
            Container(
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20, color: p.tinta3),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      'Todavía no tiene plan. Cuando armes uno, cada cuota '
                      'queda con su vencimiento y las que se atrasen te '
                      'aparecen en el Inicio.',
                      style: TextStyle(
                        fontSize: 14,
                        color: p.tinta2,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final plan in planes) _Plan(plan: plan),
        ],
      ),
    );
  }
}

class _Plan extends ConsumerWidget {
  const _Plan({required this.plan});

  final PlanPago plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final cuotas = ref.watch(cuotasProvider(plan.id)).value ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${plan.cantidadCuotas} cuotas de '
                  '${Fmt.pesos(plan.totalPlan / plan.cantidadCuotas)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Pastilla(
                texto: plan.terminado
                    ? 'Terminado'
                    : plan.alDia
                    ? 'Al día'
                    : '${plan.cuotasVencidas} '
                          '${plan.cuotasVencidas == 1 ? 'vencida' : 'vencidas'}',
                color: plan.terminado
                    ? p.tinta2
                    : plan.alDia
                    ? p.bien
                    : p.critico,
                lavado: plan.terminado
                    ? p.superficieHundida
                    : plan.alDia
                    ? p.bienLavado
                    : p.criticoLavado,
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          BarraProgreso(
            valor: plan.avance,
            color: plan.alDia ? p.bien : p.observar,
          ),
          const SizedBox(height: Esp.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pagó ${Fmt.pesos(plan.totalPagado)} de '
                  '${Fmt.pesos(plan.totalPlan)}',
                  style: TextStyle(fontSize: 14, color: p.tinta2),
                ),
              ),
              Text(
                'Debe ${Fmt.pesos(plan.deuda)}',
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: plan.deudaVencida > 0 ? p.critico : p.tinta,
                ),
              ),
            ],
          ),

          const SizedBox(height: Esp.md),
          for (final c in cuotas) _Cuota(cuota: c, plan: plan),
        ],
      ),
    );
  }
}

class _Cuota extends ConsumerWidget {
  const _Cuota({required this.cuota, required this.plan});

  final CuotaPlan cuota;
  final PlanPago plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final c = cuota;
    final color = c.saldada
        ? p.bien
        : c.vencida
        ? p.critico
        : p.tinta2;

    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.sm - 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Esp.md,
          vertical: Esp.sm + 2,
        ),
        decoration: BoxDecoration(
          color: c.vencida ? p.criticoLavado : p.superficieHundida,
          borderRadius: BorderRadius.circular(Curva.md),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${c.numero}',
                style: TextStyle(
                  fontFamily: TemaApp.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vence el ${Fmt.fecha(c.venceEl)}',
                    style: TextStyle(fontSize: 15, color: p.tinta),
                  ),
                  Text(
                    c.parcial
                        ? 'Pagó ${Fmt.pesos(c.pagado)} · falta '
                              '${Fmt.pesos(c.saldo)}'
                        : c.cuando,
                    style: TextStyle(fontSize: 14, color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Esp.sm),
            Text(
              Fmt.pesos(c.importe),
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.saldada ? p.tinta3 : p.tinta,
              ),
            ),
            const SizedBox(width: Esp.sm),
            if (c.saldada)
              Icon(Icons.check_circle_rounded, size: 24, color: p.bien)
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Esp.md,
                    vertical: Esp.sm,
                  ),
                  minimumSize: const Size(0, 40),
                ),
                onPressed: () => HojaPago.abrir(context, cuota: c, plan: plan),
                child: const Text('Cobrar'),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Armar un plan
// ---------------------------------------------------------------------------

class HojaPlanDePagos extends ConsumerStatefulWidget {
  const HojaPlanDePagos({super.key, required this.interesado});

  final Interesado interesado;

  static Future<bool> abrir(BuildContext context, Interesado i) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (_) => HojaPlanDePagos(interesado: i),
      ) ??
      false;

  @override
  ConsumerState<HojaPlanDePagos> createState() => _HojaPlanDePagosState();
}

class _HojaPlanDePagosState extends ConsumerState<HojaPlanDePagos> {
  late AltaPlan _p = AltaPlan(
    clienteNombre: widget.interesado.nombre,
    clienteTelefono: widget.interesado.telefono,
    oportunidadId: widget.interesado.id,
    montoFinanciado: 0,
    cantidadCuotas: 12,
  );

  Map<String, String> _errores = {};
  bool _guardando = false;

  Future<void> _guardar() async {
    final errores = _p.validar();
    setState(() => _errores = errores);
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).crearPlan(_p);
      ref
        ..invalidate(planesProvider)
        ..invalidate(planesDeProvider(widget.interesado.id))
        ..invalidate(cuotasVencidasProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo armar el plan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final r = Motor.financiacionPor(
      sistema: SistemaAmortizacion.desde(_p.sistema),
      monto: _p.montoFinanciado,
      cuotas: _p.cantidadCuotas,
      tna: _p.tna,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Armar un plan de pagos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Para ${widget.interesado.nombre}',
            style: TextStyle(fontSize: 15, color: p.tinta2),
          ),
          const SizedBox(height: Esp.lg),

          CampoMonto(
            etiqueta: 'Cuánto se financia',
            obligatorio: true,
            ayuda: 'Lo que queda después de la entrega',
            valor: _p.montoFinanciado == 0 ? null : _p.montoFinanciado,
            error: _errores['monto'],
            onCambio: (x) =>
                setState(() => _p = _p.copiar(montoFinanciado: x ?? 0)),
          ),
          const SizedBox(height: Esp.md),
          FilaCampos(
            children: [
              CampoNumero(
                etiqueta: 'Cuotas',
                obligatorio: true,
                valor: '${_p.cantidadCuotas}',
                error: _errores['cuotas'],
                onCambio: (x) => setState(
                  () => _p = _p.copiar(cantidadCuotas: int.tryParse(x) ?? 0),
                ),
              ),
              CampoNumero(
                etiqueta: 'Tasa anual (TNA)',
                sufijo: '%',
                ayuda: 'Dejalo en 0 si no cobrás interés',
                valor: _p.tna == 0 ? '' : (_p.tna * 100).round().toString(),
                error: _errores['tna'],
                onCambio: (x) => setState(
                  () => _p = _p.copiar(tna: (double.tryParse(x) ?? 0) / 100),
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          CampoFormulario(
            etiqueta: 'Sistema',
            hijo: Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                for (final s in SistemaAmortizacion.values)
                  ChipSeleccion(
                    etiqueta: s.etiqueta,
                    activo: _p.sistema == s.valorBd,
                    onTap: () =>
                        setState(() => _p = _p.copiar(sistema: s.valorBd)),
                  ),
              ],
            ),
          ),

          if (_p.montoFinanciado > 0) ...[
            const SizedBox(height: Esp.lg),
            Container(
              padding: const EdgeInsets.all(Esp.lg),
              decoration: BoxDecoration(
                color: p.negro,
                borderRadius: BorderRadius.circular(Curva.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.primera == r.ultima
                        ? 'Cuota mensual'
                        : 'Primera cuota (van bajando)',
                    style: TextStyle(fontSize: 15, color: p.sobreNegro2),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Fmt.pesos(r.primera),
                      style: TextStyle(
                        fontFamily: TemaApp.titulo,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: p.acento,
                      ),
                    ),
                  ),
                  const SizedBox(height: Esp.xs),
                  Text(
                    'Total a cobrar ${Fmt.pesos(r.total)} · intereses '
                    '${Fmt.pesos(r.interes)}',
                    style: TextStyle(fontSize: 14, color: p.sobreNegro2),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: Esp.md),
          CampoTexto(
            etiqueta: 'Notas',
            ayuda: 'Lo que se acordó de palabra',
            valor: _p.notas,
            lineas: 2,
            onCambio: (x) => _p = _p.copiar(notas: x),
          ),

          const SizedBox(height: Esp.lg),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.check_rounded, size: 22),
            label: const Text('Armar el plan'),
          ),
          const SizedBox(height: Esp.sm),
          Text(
            'Las cuotas se crean con vencimiento mensual, la primera al mes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.tinta3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Asentar un pago
// ---------------------------------------------------------------------------

class HojaPago extends ConsumerStatefulWidget {
  const HojaPago({super.key, required this.cuota, required this.plan});

  final CuotaPlan cuota;
  final PlanPago plan;

  static Future<bool> abrir(
    BuildContext context, {
    required CuotaPlan cuota,
    required PlanPago plan,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => HojaPago(cuota: cuota, plan: plan),
      ) ??
      false;

  @override
  ConsumerState<HojaPago> createState() => _HojaPagoState();
}

class _HojaPagoState extends ConsumerState<HojaPago> {
  late double _importe = widget.cuota.saldo;
  MedioPago _medio = MedioPago.efectivo;
  DateTime _fecha = DateTime.now();
  String _notas = '';
  Map<String, String> _errores = {};
  bool _guardando = false;

  Future<void> _guardar() async {
    final alta = AltaPago(
      cuotaId: widget.cuota.id,
      importe: _importe,
      fecha: _fecha,
      medio: _medio,
      notas: _notas,
    );
    final errores = alta.validar(saldoCuota: widget.cuota.saldo);
    setState(() => _errores = errores);
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).registrarPago(alta);
      ref
        ..invalidate(cuotasProvider(widget.cuota.planId))
        ..invalidate(planesProvider)
        ..invalidate(cuotasVencidasProvider);
      if (widget.plan.oportunidadId != null) {
        ref.invalidate(planesDeProvider(widget.plan.oportunidadId!));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo asentar el pago: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = widget.cuota;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Asentar un pago',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Cuota ${c.numero} de ${widget.plan.cantidadCuotas} · '
            '${c.clienteNombre.isEmpty ? widget.plan.clienteNombre : c.clienteNombre}',
            style: TextStyle(fontSize: 15, color: p.tinta2),
          ),
          const SizedBox(height: Esp.lg),

          Container(
            padding: const EdgeInsets.all(Esp.md),
            decoration: BoxDecoration(
              color: c.vencida ? p.criticoLavado : p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vence el ${Fmt.fecha(c.venceEl)}',
                        style: TextStyle(fontSize: 15, color: p.tinta),
                      ),
                      Text(
                        c.cuando,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.vencida ? p.critico : p.tinta2,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Saldo ${Fmt.pesos(c.saldo)}',
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.tinta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),

          CampoMonto(
            etiqueta: 'Cuánto entró',
            obligatorio: true,
            ayuda: 'Puede ser una parte: queda como pago parcial',
            valor: _importe == 0 ? null : _importe,
            error: _errores['importe'],
            onCambio: (x) => setState(() => _importe = x ?? 0),
          ),
          const SizedBox(height: Esp.md),
          CampoFecha(
            etiqueta: 'Cuándo',
            valor: _fecha,
            onCambio: (x) => setState(() => _fecha = x),
          ),
          const SizedBox(height: Esp.md),
          CampoFormulario(
            etiqueta: 'Cómo pagó',
            hijo: Wrap(
              spacing: Esp.sm,
              runSpacing: Esp.sm,
              children: [
                for (final m in MedioPago.values)
                  ChipSeleccion(
                    etiqueta: m.etiqueta,
                    activo: _medio == m,
                    onTap: () => setState(() => _medio = m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Esp.md),
          CampoTexto(
            etiqueta: 'Notas',
            valor: _notas,
            onCambio: (x) => _notas = x,
          ),

          const SizedBox(height: Esp.lg),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: p.bien,
              foregroundColor: Colors.white,
            ),
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.check_rounded, size: 22),
            label: const Text('Asentar el pago'),
          ),
        ],
      ),
    );
  }
}
