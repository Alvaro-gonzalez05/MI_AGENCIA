import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../dominio/motor_calculo.dart';

/// El plan de cuotas en PDF, para imprimirlo o mandárselo al cliente.
///
/// Es lo que el diseño pone como "Descargar PDF" abajo del resultado del
/// simulador. No es un contrato ni una oferta: es la misma simulación que se
/// ve en pantalla, con el detalle cuota por cuota y la aclaración de que es
/// orientativa.
abstract final class PlanPdf {
  static final _pesos = NumberFormat.decimalPattern('es_AR');
  static final _fecha = DateFormat('dd/MM/yyyy', 'es_AR');

  static String _plata(num n) => '\$ ${_pesos.format(n.round())}';

  static Future<List<int>> generar({
    required SistemaAmortizacion sistema,
    required double monto,
    required int cuotas,
    required double tna,
    String? agencia,
  }) async {
    final doc = pw.Document(
      title: 'Plan de financiación',
      author: agencia ?? 'Mi Agencia',
      subject: 'Simulación orientativa de cuotas',
      theme: await _tipografia(),
    );

    final r = Motor.financiacionPor(
      sistema: sistema,
      monto: monto,
      cuotas: cuotas,
      tna: tna,
    );
    final filas = _cuotas(
      sistema: sistema,
      monto: monto,
      cuotas: cuotas,
      tna: tna,
    );
    final hoy = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 38, 38, 30),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Simulación orientativa. No incluye gastos de otorgamiento, '
                'seguros ni sellados.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    (agencia ?? 'Mi Agencia').toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.2,
                      color: PdfColors.grey700,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Plan de financiación',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Sistema ${sistema.etiqueta.toLowerCase()} · '
                    '${sistema.explicacion.toLowerCase()}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'Emitido el ${_fecha.format(hoy)}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          pw.Row(
            children: [
              _dato('Monto a financiar', _plata(monto)),
              pw.SizedBox(width: 10),
              _dato('Cuotas', '$cuotas'),
              pw.SizedBox(width: 10),
              _dato('Tasa anual (TNA)', '${(tna * 100).round()} %'),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _dato(
                sistema == SistemaAmortizacion.global
                    ? 'Pago único al final'
                    : r.primera == r.ultima
                    ? 'Cuota mensual'
                    : 'Primera cuota',
                _plata(
                  sistema == SistemaAmortizacion.global ? r.total : r.primera,
                ),
                destacado: true,
              ),
              pw.SizedBox(width: 10),
              _dato('Total a pagar', _plata(r.total)),
              pw.SizedBox(width: 10),
              _dato('Intereses', _plata(r.interes)),
            ],
          ),
          pw.SizedBox(height: 20),

          pw.Text(
            'Detalle cuota por cuota',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Cuota',
              'Vencimiento',
              'Capital',
              'Interés',
              'A pagar',
              'Saldo',
            ],
            data: [
              for (final f in filas)
                [
                  '${f.numero}',
                  _fecha.format(
                    DateTime(hoy.year, hoy.month + f.numero, hoy.day),
                  ),
                  _plata(f.capital),
                  _plata(f.interes),
                  _plata(f.cuota),
                  _plata(f.saldo),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _dato(
    String etiqueta,
    String valor, {
    bool destacado = false,
  }) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: destacado ? PdfColors.amber100 : PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            etiqueta.toUpperCase(),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destacado ? 14 : 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  /// El cuadro de marcha: qué parte de cada cuota es capital y qué parte es
  /// interés, y cuánto queda debiendo después de pagarla.
  static List<
    ({int numero, double capital, double interes, double cuota, double saldo})
  >
  _cuotas({
    required SistemaAmortizacion sistema,
    required double monto,
    required int cuotas,
    required double tna,
  }) {
    final i = tna / 12;
    final filas =
        <
          ({
            int numero,
            double capital,
            double interes,
            double cuota,
            double saldo,
          })
        >[];
    var saldo = monto;

    final total = Motor.financiacionPor(
      sistema: sistema,
      monto: monto,
      cuotas: cuotas,
      tna: tna,
    );

    for (var n = 1; n <= cuotas; n++) {
      late double capital, interes, cuota;
      switch (sistema) {
        case SistemaAmortizacion.frances:
          cuota = total.primera;
          interes = saldo * i;
          capital = cuota - interes;
        case SistemaAmortizacion.aleman:
          capital = monto / cuotas;
          interes = saldo * i;
          cuota = capital + interes;
        case SistemaAmortizacion.directo:
          cuota = total.primera;
          capital = monto / cuotas;
          interes = cuota - capital;
        case SistemaAmortizacion.global:
          // No se paga nada hasta el final: el interés se acumula.
          capital = n == cuotas ? monto : 0;
          interes = n == cuotas ? total.interes : 0;
          cuota = n == cuotas ? total.total : 0;
      }
      saldo = (saldo - capital).clamp(0, monto);
      filas.add((
        numero: n,
        capital: capital,
        interes: interes,
        cuota: cuota,
        saldo: saldo,
      ));
    }
    return filas;
  }

  /// Las mismas tipografías que la app, para que el papel se lea igual que
  /// la pantalla.
  static Future<pw.ThemeData> _tipografia() async => pw.ThemeData.withFont(
    base: pw.Font.ttf(
      await rootBundle.load(
        'assets/fuentes/AtkinsonHyperlegibleNext-Regular.ttf',
      ),
    ),
    bold: pw.Font.ttf(
      await rootBundle.load('assets/fuentes/AtkinsonHyperlegibleNext-Bold.ttf'),
    ),
  );
}
