import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/papeles.dart';

/// La ficha de la unidad en papel.
///
/// Es el "Imprimir ficha" del diseño. Sirve para dos cosas muy concretas:
/// pegarla en el parabrisas del auto en el salón, y dársela al cliente que
/// se la lleva para pensarlo. Por eso NO lleva ni el precio de compra ni la
/// ganancia: eso es información del dueño, no del comprador.
abstract final class FichaPdf {
  static final _pesos = NumberFormat.decimalPattern('es_AR');
  static final _fecha = DateFormat('dd/MM/yyyy', 'es_AR');

  static String _plata(num? n) =>
      n == null ? '—' : '\$ ${_pesos.format(n.round())}';

  /// Arma la ficha y abre el diálogo de impresión o de compartir.
  static Future<void> imprimir(
    BuildContext context,
    WidgetRef ref,
    VehiculoInventario v,
  ) async {
    try {
      final repo = ref.read(repositorioProvider);
      final papeles = await repo.papeles(v.id);
      final agencia = ref.read(miAgenciaProvider).value?.nombre;

      final bytes = await generar(
        vehiculo: v,
        papeles: papeles,
        agencia: agencia,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(bytes),
        name: 'ficha-${v.codigo}.pdf',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo armar la ficha: $e')));
    }
  }

  static Future<List<int>> generar({
    required VehiculoInventario vehiculo,
    PapelesVehiculo? papeles,
    String? agencia,
  }) async {
    final v = vehiculo;
    final doc = pw.Document(
      title: 'Ficha — ${v.titulo}',
      author: agencia ?? 'Mi Agencia',
      theme: await _tipografia(),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  (agencia ?? 'Mi Agencia').toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                if (v.patente != null && v.patente!.isNotEmpty)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 1.5),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      v.patente!.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 14,
                        letterSpacing: 2,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              v.titulo,
              style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              [
                'Año ${v.anio}',
                if (v.km != null) '${_pesos.format(v.km)} km',
                if (v.combustible != null) v.combustible!,
                if (v.transmision != null) v.transmision!,
                if (v.color != null) v.color!,
              ].join('  ·  '),
              style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey800),
            ),

            pw.SizedBox(height: 22),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.amber100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'PRECIO CONTADO',
                    style: pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _plata(v.precioActual),
                    style: pw.TextStyle(
                      fontSize: 34,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 22),
            pw.Text(
              'Ficha técnica',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              border: null,
              cellStyle: const pw.TextStyle(fontSize: 11),
              cellAlignments: {0: pw.Alignment.centerLeft},
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4),
              data: [
                ['Marca', v.marca],
                ['Modelo', v.modelo],
                if (v.version != null) ['Versión', v.version!],
                ['Año', '${v.anio}'],
                if (v.km != null) ['Kilómetros', '${_pesos.format(v.km)} km'],
                if (v.combustible != null) ['Combustible', v.combustible!],
                if (v.transmision != null) ['Transmisión', v.transmision!],
                if (v.color != null) ['Color', v.color!],
                ['Código interno', v.codigo],
              ],
            ),

            if (papeles != null) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Papeles',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _sello('Título', papeles.titulo),
                  _sello('Cédula verde', papeles.cedula),
                  _sello(
                    papeles.vtvVence == null
                        ? 'VTV'
                        : 'VTV hasta ${_fecha.format(papeles.vtvVence!)}',
                    papeles.vtv && !papeles.vtvVencida,
                  ),
                  _sello('Informe de dominio', papeles.informeDominio),
                  _sello('Patentes al día', papeles.patentesDeuda == 0),
                  _sello(
                    'Sin multas',
                    papeles.multasCantidad == 0 && papeles.multasMonto != null,
                  ),
                ],
              ),
            ],

            if (v.observaciones != null && v.observaciones!.isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                'Observaciones',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                v.observaciones!,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],

            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400),
            pw.Text(
              'Precio y disponibilidad sujetos a confirmación. '
              'Ficha generada el ${_fecha.format(DateTime.now())}.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Un tilde o una cruz: el comprador mira esto antes que nada.
  static pw.Widget _sello(String texto, bool listo) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: pw.BoxDecoration(
      color: listo ? PdfColors.green50 : PdfColors.grey200,
      borderRadius: pw.BorderRadius.circular(20),
    ),
    child: pw.Text(
      '${listo ? '✓' : '—'}  $texto',
      style: pw.TextStyle(
        fontSize: 10,
        color: listo ? PdfColors.green800 : PdfColors.grey700,
        fontWeight: listo ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

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
