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
