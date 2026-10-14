import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../dominio/bcra.dart';
import '../../ui/componentes.dart';

/// Todo lo que el BCRA informa, mes por mes y entidad por entidad.
///
/// Es lo que muestra la web del Banco Central y lo que la agencia pidió ver
/// adentro del sistema: no alcanza con "situación 4", hace falta saber con
/// quién, desde cuándo, por cuánto, y si eso sigue abierto o quedó atrás.
///
/// Cada entidad arranca cerrada: la mayoría de las veces se mira el resumen
/// y se sigue. El que necesita el detalle, lo abre.
class DetalleBcra extends StatelessWidget {
  const DetalleBcra({super.key, required this.consulta});

  final ConsultaBcra consulta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final porEntidad = consulta.historialPorEntidad;
    if (porEntidad.isEmpty) return const SizedBox.shrink();

    final tramo = consulta.peorTramo;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Historia de 24 meses',
            descripcion: 'Lo que informó cada entidad, mes por mes',
          ),

          if (tramo != null) ...[
            const SizedBox(height: Esp.md),
            _PeorTramo(tramo: tramo),
          ],

          const SizedBox(height: Esp.md),
          for (final (entidad, meses) in porEntidad)
            _EntidadDesplegable(entidad: entidad, meses: meses),

          const SizedBox(height: Esp.sm),
          Text(
            'Fuente: Central de Deudores del BCRA. Los montos se informan en '
            'miles de pesos y acá se muestran convertidos.',
            style: TextStyle(fontSize: 13, height: 1.4, color: p.tinta3),
          ),
        ],
      ),
    );
  }
}

/// "¿De cuándo es esto y con quién fue?": la pregunta que sigue siempre que
/// el semáforo da rojo por el pasado.
class _PeorTramo extends StatelessWidget {
  const _PeorTramo({required this.tramo});

  final TramoIrregular tramo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final t = tramo;
    final color = t.situacion >= 4 ? p.critico : p.atencion;

    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: t.regularizado
            ? p.superficieHundida
            : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Esp.sm,
            runSpacing: Esp.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pastilla(
                texto: 'Situación ${t.situacion}',
                color: color,
                lavado: color.withValues(alpha: 0.14),
              ),
              Text(
                t.regularizado
                    ? 'Ya no le debe a esta entidad'
                    : 'Sigue informada hoy',
                style: TextStyle(fontSize: 14, color: p.tinta2),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          Text(
            '${t.entidad}: ${t.duracion} entre '
            '${_capitalizar(t.desde.largo)} y ${_capitalizar(t.hasta.largo)}. '
            'Llegó a deber ${Fmt.pesos(t.montoMaximo)}'
            '${t.montoUltimo == t.montoMaximo ? '' : ', y lo último informado '
                      'fueron ${Fmt.pesos(t.montoUltimo)}'}.',
            style: TextStyle(fontSize: 14, height: 1.45, color: p.tinta),
          ),
          if (t.refinanciada || t.procesoJudicial) ...[
            const SizedBox(height: Esp.xs),
            Text(
              [
                if (t.refinanciada) 'Deuda refinanciada',
                if (t.procesoJudicial) 'Con proceso judicial informado',
              ].join(' · '),
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
          const SizedBox(height: Esp.xs),
          Text(
            t.estadoHoy,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.regularizado ? p.bien : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntidadDesplegable extends StatefulWidget {
  const _EntidadDesplegable({required this.entidad, required this.meses});

  final String entidad;
  final List<(MesBcra, EntidadMes)> meses;

  @override
  State<_EntidadDesplegable> createState() => _EntidadDesplegableState();
}

class _EntidadDesplegableState extends State<_EntidadDesplegable> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final peor = widget.meses.fold<int>(
      0,
      (a, x) => x.$2.situacion > a ? x.$2.situacion : a,
    );
    final color = _colorSituacion(peor, p);

    return Container(
      margin: const EdgeInsets.only(bottom: Esp.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.borde),
      ),
      child: Column(
        children: [
          Pulsable(
            onTap: () => setState(() => _abierta = !_abierta),
            escala: 1,
            child: Padding(
              padding: const EdgeInsets.all(Esp.md),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '$peor',
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entidad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.tinta),
                        ),
                        Text(
                          '${widget.meses.length} '
                          '${widget.meses.length == 1 ? 'mes informado' : 'meses informados'}'
                          ' · peor situación: ${_nombreSituacion(peor)}',
                          style: TextStyle(fontSize: 13, color: p.tinta3),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _abierta
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: p.tinta3,
                  ),
                ],
              ),
            ),
          ),
          if (_abierta) ...[
            Divider(color: p.borde, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Esp.md,
                Esp.sm,
                Esp.md,
                Esp.sm,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Columna('Período', ancho: 2),
                      _Columna('Situación', ancho: 3),
                      _Columna('Monto', ancho: 2, alinear: TextAlign.end),
                      _Columna('Juicio / revisión', ancho: 2),
                    ],
                  ),
                  const SizedBox(height: Esp.xs),
                  for (final (mes, e) in widget.meses)
                    _FilaMes(mes: mes, entidad: e),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna(this.texto, {required this.ancho, this.alinear});

  final String texto;
  final int ancho;
  final TextAlign? alinear;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: ancho,
    child: Text(
      texto,
      textAlign: alinear,
      style: TextStyle(fontSize: 13, color: context.paleta.tinta3),
    ),
  );
}

class _FilaMes extends StatelessWidget {
  const _FilaMes({required this.mes, required this.entidad});

  final MesBcra mes;
  final EntidadMes entidad;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final e = entidad;
    final color = _colorSituacion(e.situacion, p);
    final marcas = [
      if (e.procesoJudicial) 'Juicio',
      if (e.enRevision) 'En revisión',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              mes.largo,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 13,
                color: p.tinta2,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              e.situacion == 0
                  ? 'Sin deuda'
                  : '${e.situacion} · ${_nombreSituacion(e.situacion)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              e.monto > 0 ? Fmt.pesosCompacto(e.monto) : '—',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 13,
                color: p.tinta2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              marcas.isEmpty ? '—' : marcas,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                color: marcas.isEmpty ? p.tinta3 : p.atencion,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalizar(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _nombreSituacion(int s) => switch (s) {
  0 => 'sin deuda',
  1 => 'normal',
  2 => 'riesgo bajo',
  3 => 'riesgo medio',
  4 => 'riesgo alto',
  5 => 'irrecuperable',
  6 => 'irrecuperable por disposición técnica',
  _ => 'sin informar',
};

Color _colorSituacion(int s, Paleta p) => switch (s) {
  0 => p.tinta3,
  1 => p.bien,
  2 => p.observar,
  3 => p.atencion,
  _ => p.critico,
};
