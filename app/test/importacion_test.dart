import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/dominio/importacion.dart';
import 'package:mi_agencia/dominio/modelos.dart';

/// Lo que devuelve el modelo no se guarda como viene: se normaliza. Estas
/// pruebas cubren justamente los casos en los que una planilla real difiere
/// de lo que uno esperaría, que es siempre.
void main() {
  final hoy = DateTime(2026, 9, 19);

  group('Una fila del modelo', () {
    test('sin marca ni modelo no es un vehículo', () {
      // Es una fila de totales o un encabezado que se coló.
      expect(FilaImportada.desdeJson({'precio_objetivo': 999}), isNull);
      expect(FilaImportada.desdeJson({'marca': '  '}), isNull);
    });

    test('lee precios en formato argentino', () {
      final f = FilaImportada.desdeJson({
        'marca': 'Fiat',
        'modelo': 'Cronos',
        'precio_compra': '\$ 18.500.000',
        'precio_objetivo': '21.900.000,50',
      }, hoy: hoy)!;

      expect(f.alta.precioCompra, 18500000);
      expect(f.alta.precioObjetivo, closeTo(21900000.5, 0.001));
    });

    test('acepta la fecha en ISO y también en dd/mm/aaaa', () {
      final iso = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'fecha_compra': '2026-03-07',
      }, hoy: hoy)!;
      expect(iso.alta.fechaCompra, DateTime(2026, 3, 7));

      final criolla = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'fecha_compra': '07/03/2026',
      }, hoy: hoy)!;
      expect(criolla.alta.fechaCompra, DateTime(2026, 3, 7));
    });

    test('si falta una fecha usa la otra, y avisa si faltan las dos', () {
      final unaSola = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'fecha_compra': '2026-03-07',
      }, hoy: hoy)!;
      expect(unaSola.alta.fechaIngreso, DateTime(2026, 3, 7));
      expect(unaSola.advertencias, isNot(contains(contains('hoy'))));

      final ninguna = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
      }, hoy: hoy)!;
      expect(ninguna.alta.fechaCompra, hoy);
      expect(ninguna.advertencias.any((a) => a.contains('hoy')), isTrue);
    });

    test('una fecha futura se corrige al día de hoy', () {
      // La base rechaza fechas futuras: mejor corregir y avisar que perder
      // la fila entera por un año mal tipeado.
      final f = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'fecha_compra': '2027-01-10',
      }, hoy: hoy)!;
      expect(f.alta.fechaCompra, hoy);
      expect(f.advertencias.any((a) => a.contains('futuro')), isTrue);
    });

    test('la patente se normaliza, y si no es argentina se descarta', () {
      final vieja = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'patente': 'abc 123',
      }, hoy: hoy)!;
      expect(vieja.alta.patente, 'ABC123');

      final nueva = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'patente': 'ad-123-xz',
      }, hoy: hoy)!;
      expect(nueva.alta.patente, 'AD123XZ');

      final basura = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'patente': 'sin patente',
      }, hoy: hoy)!;
      expect(basura.alta.patente, isEmpty);
      expect(basura.advertencias.any((a) => a.contains('patente')), isTrue);
    });

    test('el kilometraje viene con puntos y se guarda como número', () {
      final f = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'km': '96.000',
      }, hoy: hoy)!;
      expect(f.alta.km, 96000);
    });

    test('el precio que falta queda vacío y sale como error, una sola vez', () {
      final f = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'precio_objetivo': 21000000,
      }, hoy: hoy)!;
      expect(f.alta.precioCompra, isNull);
      // Falta un dato obligatorio: no se puede cargar sin que alguien lo mire.
      expect(f.completa, isFalse);
      expect(f.errores['precioCompra'], isNotNull);
      // Y no se repite como advertencia: seria el mismo problema dos veces.
      expect(f.advertencias.any((a) => a.contains('precio')), isFalse);
    });

    test('recuerda si la fila salió de una foto', () {
      final planilla = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
      }, hoy: hoy)!;
      expect(planilla.desdeFoto, isFalse);

      final foto = FilaImportada.desdeJson(
        {'marca': 'VW', 'modelo': 'Gol'},
        hoy: hoy,
        desdeFoto: true,
      )!;
      expect(foto.desdeFoto, isTrue);
      // Y sobrevive a que el usuario la destilde en la revision.
      expect(foto.copiar(incluir: false).desdeFoto, isTrue);
    });

    test('confianza cero es desconfianza, no dato faltante', () {
      final f = FilaImportada.desdeJson({
        'marca': 'VW',
        'modelo': 'Gol',
        'confianza': 0,
      }, hoy: hoy)!;
      expect(f.confianza, 0);
      expect(f.dudosa, isTrue);
    });
  });

  group('Duplicados', () {
    /// La vista trae veinticuatro columnas calculadas; para esta prueba solo
    /// importan las que identifican la unidad, el resto va en cero.
    VehiculoInventario enStock({
      required String codigo,
      String? patente,
      String marca = 'Volkswagen',
      String modelo = 'Amarok',
      int anio = 2019,
    }) => VehiculoInventario(
      id: codigo,
      codigo: codigo,
      marca: marca,
      modelo: modelo,
      anio: anio,
      patente: patente,
      estado: EstadoVehiculo.enStock,
      alerta: AlertaRotacion.normal,
      fechaIngreso: DateTime(2026, 1, 10),
      precioCompra: 0,
      precioObjetivo: 0,
      costoTotal: 0,
      gastosAcum: 0,
      cantidadGastos: 0,
      diasEnStock: 0,
      precioActual: 0,
      capitalInmovilizado: 0,
      gananciaEstimada: 0,
      margenActual: 0,
      margenEsperado: 0,
      precioParaMargenObjetivo: 0,
      precioSugerido: 0,
      costoTotalHoy: 0,
      gananciaRealIpc: 0,
      gananciaRealUsd: 0,
    );

    FilaImportada fila({String? patente, String modelo = 'Amarok'}) =>
        FilaImportada.desdeJson({
          'marca': 'Volkswagen',
          'modelo': modelo,
          'anio': 2019,
          'patente': patente,
          'precio_compra': 1000,
          'precio_objetivo': 2000,
          'fecha_compra': '2026-01-10',
        }, hoy: hoy)!;

    test('la que ya está en el inventario viene destildada', () {
      final r = marcarDuplicados(
        [fila(patente: 'AD123XZ')],
        [enStock(codigo: 'V007', patente: 'AD123XZ')],
      );
      expect(r.single.incluir, isFalse);
      expect(r.single.advertencias.any((a) => a.contains('V007')), isTrue);
    });

    test('sin patente compara por marca, modelo y año', () {
      final r = marcarDuplicados([fila()], [enStock(codigo: 'V008')]);
      expect(r.single.incluir, isFalse);
    });

    test('la repetida dentro del mismo archivo se destilda una sola vez', () {
      final r = marcarDuplicados([
        fila(patente: 'AD123XZ'),
        fila(patente: 'AD123XZ'),
      ], const []);
      expect(r.first.incluir, isTrue);
      expect(r.last.incluir, isFalse);
    });

    test('una unidad nueva pasa intacta', () {
      final r = marcarDuplicados(
        [fila(patente: 'AA111BB')],
        [enStock(codigo: 'V009', patente: 'AD123XZ')],
      );
      expect(r.single.incluir, isTrue);
      expect(r.single.advertencias, isEmpty);
    });
  });
}
