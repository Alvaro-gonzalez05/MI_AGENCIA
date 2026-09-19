import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../dominio/bcra.dart';
import '../../dominio/modelos.dart';

/// Informe crediticio en PDF.
///
/// Es el papel que queda en la carpeta de la operación: por qué se financió
/// o por qué no. Por eso imprime la fuente, el período y quién lo generó, y
/// no solo el color del semáforo. Un informe sin fecha ni origen no sirve
/// para defender una decisión seis meses después.
///
/// Se arma en la app y no en el servidor porque todos los datos ya están en
/// pantalla: mandarlos de vuelta para que un servidor los dibuje sería un
/// viaje de ida y vuelta por un documento que se lee una vez.
abstract final class InformeCrediticio {
  /// Genera el PDF listo para imprimir, guardar o compartir.
  static Future<List<int>> generar({
    required Interesado interesado,
    String? agencia,
    String? generadoPor,
  }) async {
    final tipografia = await _tipografia();
    final doc = pw.Document(
      title: 'Informe crediticio — ${interesado.nombre}',
      author: agencia ?? 'Mi Agencia',
      subject: 'Situación en la Central de Deudores del BCRA',
      theme: tipografia,
    );

    final c = interesado.consulta;
    final generadoEl = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 30),
        header: (ctx) =>
            ctx.pageNumber == 1 ? pw.SizedBox() : _encabezadoCorto(interesado),
        footer: (ctx) => _pie(ctx, generadoEl, generadoPor),
        build: (ctx) => [
          _portada(agencia, generadoEl),
          pw.SizedBox(height: 18),
          _veredicto(interesado),
          pw.SizedBox(height: 16),
          _datosPersonales(interesado),
          pw.SizedBox(height: 14),
          _laOperacion(interesado),
          if (c != null) ...[
            pw.SizedBox(height: 14),
            _resumenBcra(c),
            // Los 24 meses: sin esto el informe decia "sin deudas" de alguien
            // que fue irrecuperable (checklist del cliente, punto 3.1).
            if (c.historico.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _historial(c),
            ],
            if (c.entidades.isNotEmpty) ...[
              pw.SizedBox(height: 14),
              _entidades(c),
            ],
            if (c.cheques.isNotEmpty) ...[pw.SizedBox(height: 14), _cheques(c)],
          ],
          pw.SizedBox(height: 10),
          _comoSeLee(c),
        ],
      ),
    );

    return doc.save();
  }

  /// Nombre de archivo sin espacios ni acentos: viaja por WhatsApp, mail y
  /// carpetas de Windows, y cualquiera de los tres lo puede romper.
  static String nombreArchivo(Interesado i) {
    final limpio = i.nombre
        .toLowerCase()
        .replaceAll(RegExp('[áàä]'), 'a')
        .replaceAll(RegExp('[éèë]'), 'e')
        .replaceAll(RegExp('[íìï]'), 'i')
        .replaceAll(RegExp('[óòö]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-|-\$'), '');
    final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'informe-crediticio-$limpio-$hoy.pdf';
  }

  // ------------------------------------------------------------------
  // Bloques
  // ------------------------------------------------------------------

  static pw.Widget _portada(String? agencia, DateTime cuando) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
                    letterSpacing: 1.6,
                    fontWeight: pw.FontWeight.bold,
                    color: _tinta3,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Informe de situación crediticia',
                  style: pw.TextStyle(
                    fontSize: 21,
                    fontWeight: pw.FontWeight.bold,
                    color: _tinta,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Central de Deudores del Banco Central de la República '
                  'Argentina',
                  style: const pw.TextStyle(fontSize: 9.5, color: _tinta3),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: pw.BoxDecoration(
                color: _hundido,
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'EMITIDO',
                    style: pw.TextStyle(
                      fontSize: 7,
                      letterSpacing: 1.2,
                      color: _tinta3,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    DateFormat("d 'de' MMMM 'de' y", 'es_AR').format(cuando),
                    style: const pw.TextStyle(fontSize: 9, color: _tinta2),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Container(height: 2.5, color: _acento),
      ],
    );
  }

  static pw.Widget _encabezadoCorto(Interesado i) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _borde)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Informe de situación crediticia',
          style: const pw.TextStyle(fontSize: 8.5, color: _tinta3),
        ),
        pw.Text(
          i.nombre,
          style: pw.TextStyle(
            fontSize: 8.5,
            color: _tinta2,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  /// El bloque grande con el color y la recomendación. Es lo único que
  /// muchos van a leer, así que dice la conclusión completa y no una palabra.
  static pw.Widget _veredicto(Interesado i) {
    final c = i.consulta;
    final (color, lavado) = _colores(i.semaforo);

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: lavado,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: color, width: 1.2),
      ),
      padding: const pw.EdgeInsets.all(16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 42,
            height: 42,
            decoration: pw.BoxDecoration(
              color: color,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  i.nombre,
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: _tinta,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  i.semaforo.etiqueta.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  c?.recomendacion ??
                      'Todavía no se consultó el BCRA para esta persona. Sin '
                          'esa consulta no hay forma de evaluar el riesgo.',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: _tinta2,
                    lineSpacing: 2.5,
                  ),
                ),
                if (c != null) ...[
                  pw.SizedBox(height: 9),
                  ...c.motivos.map(
                    (m) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2.5),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 3,
                            height: 3,
                            margin: const pw.EdgeInsets.only(top: 4, right: 6),
                            decoration: pw.BoxDecoration(
                              color: color,
                              shape: pw.BoxShape.circle,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              m,
                              style: const pw.TextStyle(
                                fontSize: 9.5,
                                color: _tinta2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _datosPersonales(Interesado i) => _seccion(
    'Datos de la persona',
    _grilla([
      ('Nombre', i.nombre),
      ('CUIT / CUIL', i.cuit == null ? _sinDato : formatearCuit(i.cuit!)),
      ('DNI', i.dni ?? _sinDato),
      ('Teléfono', i.telefono ?? _sinDato),
      ('WhatsApp', i.whatsapp ?? _sinDato),
      ('Email', i.email ?? _sinDato),
      ('Localidad', i.localidad ?? _sinDato),
      ('Provincia', i.provincia ?? _sinDato),
      ('Origen del contacto', i.origen ?? _sinDato),
      ('Cargado el', _fecha(i.fecha)),
      if (i.consulta?.denominacion != null)
        ('Razón social en el BCRA', i.consulta!.denominacion!),
    ]),
  );

  static pw.Widget _laOperacion(Interesado i) => _seccion(
    'La operación',
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _grilla([
          (
            'Unidad de interés',
            i.vehiculoTitulo == null
                ? 'Sin unidad definida'
                : '${i.vehiculoCodigo ?? ''} ${i.vehiculoTitulo}'.trim(),
          ),
          ('Precio de la unidad', _pesos(i.vehiculoPrecio)),
          ('Presupuesto declarado', _pesos(i.presupuestoMax)),
          ('Pide financiación', i.necesitaFinanciacion ? 'Sí' : 'No'),
          ('Entrega un usado', i.entregaUsado ? 'Sí' : 'No'),
          if (i.entregaUsado)
            ('Usado que entrega', i.usadoDescripcion ?? _sinDato),
          if (i.entregaUsado)
            ('Valor estimado del usado', _pesos(i.usadoValorEstimado)),
          ('Estado del interés', _estado(i.estadoOportunidad)),
          ('Nivel de interés', i.interes == null ? _sinDato : '${i.interes}/5'),
          if (i.proximaAccion != null) ('Próxima acción', i.proximaAccion!),
          if (i.proximaAccionFecha != null)
            ('Fecha de esa acción', _fecha(i.proximaAccionFecha)),
        ]),
        if ((i.notas ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 9),
          _nota('Notas del interés', i.notas!),
        ],
        if ((i.notasCliente ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 7),
          _nota('Notas de la persona', i.notasCliente!),
        ],
      ],
    ),
  );

  static pw.Widget _resumenBcra(ConsultaBcra c) => _seccion(
    'Situación en el BCRA',
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            _dato(
              'Situación hoy',
              c.situacionMaxima == null ? '—' : '${c.situacionMaxima}',
              detalle: c.entidades.isEmpty
                  ? 'sin deuda hoy'
                  : c.entidades.first.descripcionSituacion,
            ),
            // Sin esta tarjeta, alguien que fue irrecuperable y ya pago se
            // veia igual que alguien que nunca debio.
            _dato(
              'Peor en 24 meses',
              c.situacionMax24m == null ? '—' : '${c.situacionMax24m}',
              detalle: c.situacionMax24m == null
                  ? 'sin deudas'
                  : _nombreSituacion(c.situacionMax24m!),
            ),
            _dato('Deuda informada', _pesos(c.totalDeuda)),
            _dato(
              'Atraso máximo',
              c.diasAtrasoMax == 0 ? '0' : '${c.diasAtrasoMax} d',
            ),
            _dato(
              'Cheques impagos',
              '${c.chequesSinPagar}',
              detalle: c.chequesSinPagar > 0 ? 'sin pagar' : null,
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            if (c.tieneProcesoJudicial)
              _bandera('Proceso judicial', _rojo, _rojoLavado),
            if (c.chequesRechazados)
              _bandera('Cheques rechazados', _amarillo, _amarilloLavado),
            if (c.tieneRefinanciaciones)
              _bandera('Deuda refinanciada', _amarillo, _amarilloLavado),
            if (c.enRevision)
              _bandera('Clasificación en revisión', _amarillo, _amarilloLavado),
            if (c.vencida)
              _bandera(
                'Consulta de más de 30 días',
                _amarillo,
                _amarilloLavado,
              ),
            if (c.sinDeudasInformadas)
              _bandera('Sin deudas en 24 meses', _verde, _verdeLavado),
            if (c.regularizo &&
                (c.situacionMax24m ?? 0) >= 2 &&
                c.alDiaDesde.isNotEmpty)
              _bandera('Al día desde ${c.alDiaDesde}', _verde, _verdeLavado),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Período informado: ${c.periodoLegible.isEmpty ? '—' : c.periodoLegible}'
          '   ·   Consultado el ${_fechaHora(c.consultadoEl)}',
          style: const pw.TextStyle(fontSize: 8.5, color: _tinta3),
        ),
      ],
    ),
  );

  /// La línea de tiempo de 24 meses: un cuadradito por mes, del más viejo
  /// al más nuevo, pintado con la peor situación de ese mes.
  static pw.Widget _historial(ConsultaBcra c) {
    final meses = c.historico.reversed.toList();
    return _seccion(
      'Últimos ${meses.length} meses',
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: 22,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < meses.length; i++) ...[
                  if (i > 0) pw.SizedBox(width: 2),
                  pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: _colorSituacion(meses[i].situacion),
                        borderRadius: pw.BorderRadius.circular(2),
                        border: meses[i].sinDeuda
                            ? pw.Border.all(color: _borde, width: 0.6)
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                meses.first.corto,
                style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
              ),
              pw.Text(
                meses.last.corto,
                style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Wrap(
            spacing: 10,
            runSpacing: 3,
            children: [
              for (final (sit, texto) in const [
                (0, 'Sin deuda'),
                (1, 'Normal'),
                (2, 'Riesgo bajo'),
                (3, 'Riesgo medio'),
                (4, 'Alto / irrecuperable'),
              ])
                pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: 7,
                      height: 7,
                      decoration: pw.BoxDecoration(
                        color: _colorSituacion(sit),
                        border: sit == 0
                            ? pw.Border.all(color: _borde, width: 0.6)
                            : null,
                      ),
                    ),
                    pw.SizedBox(width: 3),
                    pw.Text(
                      texto,
                      style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static PdfColor _colorSituacion(int s) => switch (s) {
    0 => _hundido,
    1 => _verde,
    2 => const PdfColor.fromInt(0xFFD9A62B),
    3 => const PdfColor.fromInt(0xFFE0782F),
    _ => _rojo,
  };

  static String _nombreSituacion(int s) => switch (s) {
    1 => 'normal',
    2 => 'riesgo bajo',
    3 => 'riesgo medio',
    4 => 'riesgo alto',
    5 => 'irrecuperable',
    6 => 'irrecuperable (téc.)',
    _ => '',
  };

  /// Doce filas entran holgadas en lo que queda de una hoja; mas que eso
  /// puede necesitar partirse, y ahi vale mas partir que dejar la tabla a
  /// medio mostrar.
  static const _filasQueEntranEnUnaHoja = 12;

  static pw.Widget _entidades(ConsultaBcra c) => _seccion(
    'Detalle por entidad',
    juntos: c.entidades.length <= _filasQueEntranEnUnaHoja,
    pw.TableHelper.fromTextArray(
      border: null,
      headerDecoration: const pw.BoxDecoration(color: _hundido),
      headerHeight: 22,
      cellHeight: 20,
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: _tinta2,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: _tinta2),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.5)),
      ),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerLeft,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(3.1),
        1: const pw.FlexColumnWidth(0.7),
        2: const pw.FlexColumnWidth(1.6),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(0.9),
        5: const pw.FlexColumnWidth(1.5),
      },
      headers: const [
        'Entidad',
        'Sit.',
        'Significado',
        'Deuda',
        'Atraso',
        'Observaciones',
      ],
      data: c.entidades
          .map(
            (e) => [
              e.entidad,
              '${e.situacion}',
              e.descripcionSituacion,
              _pesos(e.monto),
              e.diasAtraso == 0 ? '—' : '${e.diasAtraso} d',
              [
                if (e.refinanciaciones) 'refinanciada',
                if (e.situacionJuridica) 'sit. jurídica',
                if (e.procesoJudicial) 'juicio',
                if (e.enRevision) 'en revisión',
              ].join(', '),
            ],
          )
          .toList(),
    ),
  );

  static pw.Widget _cheques(ConsultaBcra c) => _seccion(
    'Cheques rechazados',
    juntos: c.cheques.length <= _filasQueEntranEnUnaHoja,
    pw.TableHelper.fromTextArray(
      border: null,
      headerDecoration: const pw.BoxDecoration(color: _hundido),
      headerHeight: 22,
      cellHeight: 20,
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: _tinta2,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: _tinta2),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.5)),
      ),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
      },
      headers: const ['Nº', 'Entidad', 'Monto', 'Rechazado', 'Estado'],
      data: c.cheques
          .map(
            (q) => [
              q.numero,
              q.entidad ?? '—',
              _pesos(q.monto),
              _fecha(q.fechaRechazo),
              q.pagado ? 'pagado ${_fecha(q.fechaPago)}' : 'SIN PAGAR',
            ],
          )
          .toList(),
    ),
  );

  /// El criterio, escrito. Sin esto el informe es una opinión con colores.
  static pw.Widget _comoSeLee(ConsultaBcra? c) => pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: _hundido,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Cómo se lee este informe',
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: _tinta,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _notasLectura([
                'Verde: situación 1 en todas las entidades, sin cheques impagos ni juicios.',
                'Amarillo: situación 2 o 3, cheques ya pagados o más de 30 días de atraso.',
              ]),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _notasLectura([
                'Rojo: situación 4 a 6, cheques sin pagar o proceso judicial informado.',
                'Gris: faltan datos o la consulta venció; nunca equivale a una aprobación.',
              ]),
            ),
          ],
        ),
        if (c != null) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'Fuente: BCRA, Central de Deudores. Los montos publicados en miles de pesos se muestran convertidos a pesos. '
            'La información se actualiza mensualmente y no reemplaza el análisis de la agencia.',
            style: pw.TextStyle(
              fontSize: 6.8,
              color: _tinta3,
              fontStyle: pw.FontStyle.italic,
              lineSpacing: 1,
            ),
          ),
        ],
      ],
    ),
  );

  static pw.Widget _notasLectura(List<String> notas) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: notas
        .map(
          (texto) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '· ',
                  style: const pw.TextStyle(fontSize: 7.2, color: _tinta3),
                ),
                pw.Expanded(
                  child: pw.Text(
                    texto,
                    style: const pw.TextStyle(
                      fontSize: 7.2,
                      color: _tinta3,
                      lineSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );

  static pw.Widget _pie(pw.Context ctx, DateTime cuando, String? quien) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _borde)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              quien == null
                  ? 'Generado el ${_fechaHora(cuando)}'
                  : 'Generado por $quien el ${_fechaHora(cuando)}',
              style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
            ),
            pw.Text(
              '${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------
  // Piezas chicas
  // ------------------------------------------------------------------

  /// Titulo mas contenido.
  ///
  /// En un MultiPage una Column se parte sola entre paginas, y eso dejaba el
  /// titulo solo al pie de una hoja con su contenido en la siguiente.
  /// `Inseparable` es justo para esto: la seccion entera se va a la hoja que
  /// viene en vez de partirse. Envolverla en un Container no alcanza, porque
  /// el Container deja que la Column de adentro se siga partiendo.
  ///
  /// [juntos] en false es para las tablas largas. Ahi si tiene que poder
  /// partirse: una tabla de veinte entidades no entra en una hoja, y
  /// forzarla a no partirse la dejaria cortada.
  static pw.Widget _seccion(
    String titulo,
    pw.Widget cuerpo, {
    bool juntos = true,
  }) {
    final columna = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8.5,
            letterSpacing: 1.3,
            fontWeight: pw.FontWeight.bold,
            color: _tinta3,
          ),
        ),
        pw.SizedBox(height: 7),
        cuerpo,
      ],
    );
    return juntos ? pw.Inseparable(child: columna) : columna;
  }

  /// Dos columnas de etiqueta/valor. Se reparte por filas y no por columnas
  /// para que al leer en voz alta el orden sea el mismo que en pantalla.
  static pw.Widget _grilla(List<(String, String)> datos) {
    final filas = <pw.Widget>[];
    for (var i = 0; i < datos.length; i += 2) {
      filas.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _par(datos[i])),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: i + 1 < datos.length ? _par(datos[i + 1]) : pw.SizedBox(),
            ),
          ],
        ),
      );
    }
    return pw.Column(children: filas);
  }

  static pw.Widget _par((String, String) d) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _borde, width: 0.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 4,
          child: pw.Text(
            d.$1,
            style: const pw.TextStyle(fontSize: 8.5, color: _tinta3),
          ),
        ),
        pw.Expanded(
          flex: 5,
          child: pw.Text(
            d.$2,
            style: pw.TextStyle(
              fontSize: 9,
              color: _tinta,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _dato(String etiqueta, String valor, {String? detalle}) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borde),
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                etiqueta,
                style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                valor,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _tinta,
                ),
              ),
              if (detalle != null)
                pw.Text(
                  detalle,
                  style: const pw.TextStyle(fontSize: 7, color: _tinta3),
                ),
            ],
          ),
        ),
      );

  /// Una etiqueta de riesgo.
  ///
  /// El fondo va como color plano y no como el mismo color con alfa: el PDF
  /// aplana la transparencia distinto que la pantalla, y la pastilla salia
  /// maciza con el texto del mismo color adentro, o sea invisible. Tinte
  /// explicito y se ve.
  static pw.Widget _bandera(String texto, PdfColor color, PdfColor tinte) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: pw.BoxDecoration(
          color: tinte,
          // Radio 8 y no 20: con un radio mayor a la mitad del alto, el
          // trazado de la esquina se cruza consigo mismo y las pastillas
          // salen con punta de flecha en vez de redondeadas.
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: color, width: 0.7),
        ),
        child: pw.Text(
          texto,
          style: pw.TextStyle(
            fontSize: 8,
            color: color,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _nota(String titulo, String texto) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      color: _hundido,
      borderRadius: pw.BorderRadius.circular(7),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: const pw.TextStyle(fontSize: 7.5, color: _tinta3),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          texto,
          style: const pw.TextStyle(
            fontSize: 9,
            color: _tinta2,
            lineSpacing: 2,
          ),
        ),
      ],
    ),
  );

  // ------------------------------------------------------------------
  // Formato y tipografía
  // ------------------------------------------------------------------

  static const _sinDato = '—';

  static const _tinta = PdfColor.fromInt(0xFF111112);
  static const _tinta2 = PdfColor.fromInt(0xFF44454A);
  static const _tinta3 = PdfColor.fromInt(0xFF8B8B90);
  static const _borde = PdfColor.fromInt(0xFFE2E2DC);
  static const _hundido = PdfColor.fromInt(0xFFF4F4F0);
  static const _acento = PdfColor.fromInt(0xFFE8B923);
  static const _verde = PdfColor.fromInt(0xFF2E7D4F);
  static const _amarillo = PdfColor.fromInt(0xFFB8860B);
  static const _rojo = PdfColor.fromInt(0xFFC0392B);
  static const _gris = PdfColor.fromInt(0xFF8B8B90);

  // Calculados a mano sobre blanco, no con alfa: ver _bandera.
  static const _verdeLavado = PdfColor.fromInt(0xFFEDF6F0);
  static const _amarilloLavado = PdfColor.fromInt(0xFFFBF4E2);
  static const _rojoLavado = PdfColor.fromInt(0xFFFAEDEB);

  static (PdfColor, PdfColor) _colores(SemaforoCrediticio s) => switch (s) {
    SemaforoCrediticio.verde => (_verde, _verdeLavado),
    SemaforoCrediticio.amarillo => (_amarillo, _amarilloLavado),
    SemaforoCrediticio.rojo => (_rojo, _rojoLavado),
    SemaforoCrediticio.sinDatos => (_gris, _hundido),
  };

  /// La misma tipografía que la app. Va embebida en el PDF: si se usara una
  /// fuente del sistema, el informe se vería distinto en cada máquina que lo
  /// abra, y encima los acentos se rompen en varios visores.
  static Future<pw.ThemeData> _tipografia() async {
    Future<pw.Font> cargar(String archivo) async =>
        pw.Font.ttf(await rootBundle.load('assets/fuentes/$archivo'));

    return pw.ThemeData.withFont(
      base: await cargar('IBMPlexSans-Regular.ttf'),
      bold: await cargar('IBMPlexSans-SemiBold.ttf'),
      italic: await cargar('IBMPlexSans-Regular.ttf'),
    );
  }

  static final _formatoPesos = NumberFormat.decimalPattern('es_AR');

  static String _pesos(double? n) =>
      n == null ? _sinDato : '\$ ${_formatoPesos.format(n.round())}';

  static String _fecha(DateTime? f) =>
      f == null ? _sinDato : DateFormat('dd/MM/yyyy').format(f);

  static String _fechaHora(DateTime? f) =>
      f == null ? _sinDato : DateFormat("dd/MM/yyyy 'a las' HH:mm").format(f);

  static String _estado(String? s) => switch (s) {
    'nuevo' => 'Nuevo',
    'contactado' => 'Contactado',
    'visita_agendada' => 'Visita agendada',
    'visita_realizada' => 'Visita realizada',
    'negociacion' => 'En negociación',
    'reservado' => 'Reservado',
    'ganado' => 'Ganado',
    'perdido' => 'Perdido',
    null => _sinDato,
    _ => s,
  };
}
