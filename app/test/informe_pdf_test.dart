import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/dominio/modelos.dart';
import 'package:mi_agencia/funciones/interesados/informe_pdf.dart';

/// El informe crediticio en PDF.
///
/// Arma el documento de verdad, con las fuentes reales. No compara pixeles:
/// compara que no explote y que el archivo salga. Un PDF se arma con un
/// arbol de widgets propio, y ahi los errores de layout (una fila que no
/// entra, una tabla sin ancho) recien aparecen al generar, nunca al
/// compilar. Este test es lo que los caza antes que el cliente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting('es_AR'));

  /// Alguien con de todo: deuda en varias entidades, atraso, cheques
  /// rechazados (uno pagado y otro no) y un usado en parte de pago. Es el
  /// caso que mas secciones dibuja, asi que es el que mas puede romperse.
  Interesado elPeorCaso() => Interesado(
    id: 'op-1',
    clienteId: 'cl-1',
    nombre: 'María Fernández Iriarte',
    telefono: '2615551234',
    whatsapp: '2615551234',
    email: 'maria@example.com',
    cuit: '27230938607',
    dni: '23093860',
    localidad: 'Godoy Cruz',
    provincia: 'Mendoza',
    origen: 'MercadoLibre',
    vehiculoCodigo: 'V007',
    vehiculoTitulo: 'Toyota Hilux',
    vehiculoPrecio: 42000000,
    estadoOportunidad: 'negociacion',
    interes: 4,
    presupuestoMax: 38000000,
    necesitaFinanciacion: true,
    entregaUsado: true,
    usadoDescripcion: 'Ford Ranger 2016, 180.000 km',
    usadoValorEstimado: 19000000,
    proximaAccion: 'Llamar para cerrar la financiación',
    proximaAccionFecha: DateTime(2026, 9, 20),
    notas: 'Vino dos veces. Quiere entregar la Ranger y financiar el resto.',
    notasCliente: 'Prefiere que la llamen después de las 18.',
    fecha: DateTime(2026, 8, 14),
    consulta: ConsultaBcra(
      cuit: '27230938607',
      consultadoEl: DateTime(2026, 9, 10, 11, 32),
      denominacion: 'FERNANDEZ IRIARTE MARIA',
      periodo: '202607',
      situacionMaxima: 4,
      totalDeudaMiles: 8450.75,
      diasAtrasoMax: 210,
      tieneProcesoJudicial: true,
      tieneRefinanciaciones: true,
      enRevision: true,
      chequesRechazados: true,
      chequesSinPagar: 1,
      entidades: const [
        EntidadBcra(
          entidad: 'BANCO DE LA NACION ARGENTINA',
          situacion: 4,
          montoMiles: 5200.5,
          diasAtraso: 210,
          procesoJudicial: true,
          refinanciaciones: true,
        ),
        EntidadBcra(
          entidad: 'TARJETA NARANJA S.A.',
          situacion: 3,
          montoMiles: 2100,
          diasAtraso: 95,
          enRevision: true,
        ),
        EntidadBcra(
          entidad: 'BANCO SUPERVIELLE S.A.',
          situacion: 1,
          montoMiles: 1150.25,
        ),
      ],
      cheques: [
        ChequeBcra(
          numero: '00012345',
          monto: 850000,
          causal: 'SIN FONDOS SUFICIENTES',
          entidad: 'BANCO DE LA NACION ARGENTINA',
          fechaRechazo: DateTime(2026, 6, 3),
        ),
        ChequeBcra(
          numero: '00012301',
          monto: 420000,
          causal: 'SIN FONDOS SUFICIENTES',
          entidad: 'BANCO DE LA NACION ARGENTINA',
          fechaRechazo: DateTime(2026, 3, 12),
          fechaPago: DateTime(2026, 3, 28),
        ),
      ],
    ),
  );

  test('genera el informe de alguien con deuda, juicio y cheques', () async {
    final bytes = await InformeCrediticio.generar(
      interesado: elPeorCaso(),
      agencia: 'Agencia del Oeste',
      generadoPor: 'Álvaro González',
    );

    expect(bytes, isNotEmpty);
    // %PDF-: si no arranca asi, no es un PDF y ningun visor lo va a abrir.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // Con fuentes embebidas y tres tablas, un informe real pesa bastante mas
    // que esto. El piso detecta el caso "salio una hoja en blanco".
    expect(bytes.length, greaterThan(20000));
  });

  test('genera el informe de alguien limpio', () async {
    final bytes = await InformeCrediticio.generar(
      interesado: Interesado(
        id: 'op-2',
        clienteId: 'cl-2',
        nombre: 'Juan Pérez',
        cuit: '30500003193',
        consulta: ConsultaBcra(
          cuit: '30500003193',
          consultadoEl: DateTime(2026, 9, 10),
          periodo: '202607',
          entidades: const [],
        ),
      ),
      agencia: 'Agencia del Oeste',
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('genera el informe con el historial de 24 meses', () async {
    // El caso del reclamo del cliente (checklist 3.1): hoy sin deuda, pero
    // irrecuperable hace mas de un anio. El PDF decia "sin deudas".
    final bytes = await InformeCrediticio.generar(
      interesado: Interesado(
        id: 'op-4',
        clienteId: 'cl-4',
        nombre: 'Con Historial',
        cuit: '27230938607',
        consulta: ConsultaBcra(
          cuit: '27230938607',
          consultadoEl: DateTime(2026, 9, 18),
          entidades: const [],
          situacionMax24m: 5,
          ultimoPeriodoIrregular: '202503',
          historico: [
            for (final per in const [
              '202607',
              '202606',
              '202605',
              '202604',
              '202603',
              '202602',
              '202601',
              '202512',
              '202511',
              '202510',
              '202509',
              '202508',
              '202507',
              '202506',
              '202505',
              '202504',
            ])
              MesBcra(periodo: per, situacion: 0),
            const MesBcra(periodo: '202503', situacion: 4),
            const MesBcra(periodo: '202412', situacion: 5),
          ],
        ),
      ),
      agencia: 'Agencia del Oeste',
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  group('Detalle por entidad y por mes (tanda 2, 2.4)', () {
    // Tres entidades en 24 meses: un banco que llegó a juicio, una tarjeta
    // que se atrasó y regularizó, y otro banco siempre normal. Datos
    // inventados: no hay personas reales en el repositorio.
    final meses = [
      for (var i = 0; i < 24; i++)
        () {
          final anio = 2026 - ((12 - 7 + i) ~/ 12);
          final mes = ((7 - 1 - i) % 12 + 12) % 12 + 1;
          final per = '$anio${mes.toString().padLeft(2, '0')}';
          final entidades = [
            EntidadMes(
              entidad: 'BANCO DE PRUEBA S.A.',
              situacion: i < 6 ? 5 : 1,
              montoMiles: 5200.5 + i,
              procesoJudicial: i < 4,
            ),
            if (i >= 3 && i < 15)
              EntidadMes(
                entidad: 'TARJETA DE PRUEBA S.A.',
                situacion: i < 8 ? 3 : 1,
                montoMiles: 800,
                enRevision: i == 5,
              ),
            const EntidadMes(
              entidad: 'OTRO BANCO S.A.',
              situacion: 1,
              montoMiles: 120,
            ),
          ]..sort((a, b) => b.situacion.compareTo(a.situacion));
          return MesBcra(
            periodo: per,
            situacion: entidades.first.situacion,
            entidades: entidades,
          );
        }(),
    ];
    final consulta = ConsultaBcra(
      cuit: '20111111112',
      consultadoEl: DateTime(2026, 9, 21),
      entidades: const [],
      historico: meses,
    );

    test('agrupa por entidad, la peor primero, meses del más nuevo', () {
      final por = consulta.historialPorEntidad;
      expect(por.map((e) => e.$1), [
        'BANCO DE PRUEBA S.A.',
        'TARJETA DE PRUEBA S.A.',
        'OTRO BANCO S.A.',
      ]);
      expect(por[0].$2, hasLength(24));
      expect(por[1].$2, hasLength(12)); // solo los meses en que aparece
      expect(por[0].$2.first.$1.periodo, '202607');
      expect(por[0].$2.first.$2.procesoJudicial, isTrue);
      expect(por[0].$2.first.$2.monto, 5200500);
    });

    test('lee el detalle guardado por la base', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'historico': [
          {
            'periodo': '202607',
            'situacion': 3,
            'entidades': [
              {
                'entidad': 'TARJETA DE PRUEBA S.A.',
                'situacion': 3,
                'monto': 800.5,
                'procesoJud': true,
                'enRevision': false,
              },
            ],
          },
        ],
      });
      final e = c.historico.single.entidades.single;
      expect(e.entidad, 'TARJETA DE PRUEBA S.A.');
      expect(e.monto, 800500);
      expect(e.procesoJudicial, isTrue);
    });

    test('el PDF sale con las tres tablas y los cheques', () async {
      final bytes = await InformeCrediticio.generar(
        interesado: Interesado(
          id: 'op-5',
          clienteId: 'cl-5',
          nombre: 'Con Detalle',
          cuit: '20111111112',
          consulta: consulta,
        ),
        agencia: 'Agencia del Oeste',
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(20000));
    });
  });

  test('genera el informe aunque no se haya consultado nada', () async {
    // Sin consulta el PDF igual tiene que salir: sirve como ficha del
    // interesado, y decir "no se consulto" tambien es informacion.
    final bytes = await InformeCrediticio.generar(
      interesado: const Interesado(
        id: 'op-3',
        clienteId: 'cl-3',
        nombre: 'Sin Consultar',
      ),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  group('Nombre del archivo', () {
    String nombre(String persona) => InformeCrediticio.nombreArchivo(
      Interesado(id: 'x', clienteId: 'x', nombre: persona),
    );

    test('saca acentos, enies y espacios', () {
      expect(
        nombre('María Ñandú Pérez'),
        startsWith('informe-crediticio-maria-nandu-perez-'),
      );
    });

    test('no deja caracteres que rompan un nombre de archivo en Windows', () {
      final n = nombre('Juan / Pérez : "El Turco"');
      expect(n, isNot(contains('/')));
      expect(n, isNot(contains(':')));
      expect(n, isNot(contains('"')));
    });

    test('termina en .pdf', () {
      expect(nombre('Ana'), endsWith('.pdf'));
    });
  });
}
