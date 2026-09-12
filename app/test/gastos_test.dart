import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/datos/datos_demo.dart';
import 'package:mi_agencia/dominio/gastos.dart';

void main() {
  final hoy = DateTime.now();
  final ayer = hoy.subtract(const Duration(days: 1));

  AltaGasto valido({DateTime? fecha, double? importe, String? vehiculo}) =>
      AltaGasto(
        vehiculoId: vehiculo ?? 'V001',
        fecha: fecha ?? ayer,
        categoria: CategoriaGasto.service,
        importe: importe ?? 320000,
      );

  group('Validacion del gasto', () {
    test('una carga completa no tiene errores', () {
      expect(valido().validar(), isEmpty);
    });

    test('hay que decir a que unidad se imputa', () {
      expect(const AltaGasto().validar()['vehiculo'], isNotNull);
      expect(valido(vehiculo: '').validar()['vehiculo'], isNotNull);
    });

    test('el importe tiene que ser positivo', () {
      expect(valido(importe: 0).validar()['importe'], isNotNull);
      expect(valido(importe: -100).validar()['importe'], isNotNull);
    });

    test('la fecha no puede ser futura', () {
      final manana = hoy.add(const Duration(days: 1));
      expect(valido(fecha: manana).validar()['fecha'], isNotNull);
    });

    test('un gasto anterior al ingreso de la unidad se rechaza', () {
      // Casi siempre es un error de tipeo; y si no lo es, igual no
      // corresponde imputarlo a esta unidad.
      final ingreso = hoy.subtract(const Duration(days: 10));
      final antes = hoy.subtract(const Duration(days: 20));
      expect(
        valido(fecha: antes).validar(fechaIngreso: ingreso)['fecha'],
        isNotNull,
      );
      expect(
        valido(fecha: ayer).validar(fechaIngreso: ingreso)['fecha'],
        isNull,
      );
    });

    test('un gasto el mismo dia del ingreso es valido', () {
      final ingreso = DateTime(
        hoy.year,
        hoy.month,
        hoy.day,
      ).subtract(const Duration(days: 5));
      expect(
        valido(fecha: ingreso).validar(fechaIngreso: ingreso)['fecha'],
        isNull,
      );
    });
  });

  group('Impacto en el margen', () {
    test('el gasto sube el costo y baja el margen', () {
      // Costo 100, precio 200 => margen 50%. Con 20 de gasto: 120/200 => 40%.
      final i = ImpactoGasto.calcular(
        costoTotal: 100,
        precioActual: 200,
        importe: 20,
      );
      expect(i.costoDespues, 120);
      expect(i.margenAntes, closeTo(0.50, 0.0001));
      expect(i.margenDespues, closeTo(0.40, 0.0001));
      expect(i.caidaDeMargen, closeTo(0.10, 0.0001));
    });

    test('detecta cuando la unidad pasa a perder plata', () {
      final i = ImpactoGasto.calcular(
        costoTotal: 190,
        precioActual: 200,
        importe: 30,
      );
      expect(i.margenDespues, lessThan(0));
    });

    test('sin precio publicado no divide por cero', () {
      final i = ImpactoGasto.calcular(
        costoTotal: 100,
        precioActual: 0,
        importe: 50,
      );
      expect(i.margenAntes, 0);
      expect(i.margenDespues, 0);
      expect(i.costoDespues, 150);
    });
  });

  group('Categorias', () {
    test('estan las diez del sistema original mas comision', () {
      expect(CategoriaGasto.values.length, 11);
    });

    test('se mapean desde el valor de la base', () {
      expect(
        CategoriaGasto.desde('chapa_y_pintura'),
        CategoriaGasto.chapaYPintura,
      );
      expect(
        CategoriaGasto.desde('lavado_detallado'),
        CategoriaGasto.lavadoDetallado,
      );
    });

    test('todas las categorias de los datos de demo se reconocen', () {
      // Un dato que no matchea no rompe nada: cae en "Otros" en silencio y la
      // pantalla miente. Por eso se chequea que ninguno caiga ahi salvo los
      // que de verdad son "otros".
      for (final g in DatosDemo.gastos) {
        final c = CategoriaGasto.desde(g.categoria);
        expect(
          c == CategoriaGasto.otros ? g.categoria : c.valorBd,
          g.categoria,
          reason: 'La categoria "${g.categoria}" no se reconoce',
        );
      }
    });

    test('un valor desconocido cae en Otros y no rompe', () {
      // Si manana se agrega una categoria en la base y la app es vieja, tiene
      // que seguir mostrando el gasto en vez de tirar una excepcion.
      expect(CategoriaGasto.desde('categoria_nueva'), CategoriaGasto.otros);
      expect(CategoriaGasto.desde(null), CategoriaGasto.otros);
    });
  });
}
