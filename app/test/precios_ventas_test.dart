import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/dominio/precios.dart';
import 'package:mi_agencia/dominio/ventas.dart';

void main() {
  final hoy = DateTime.now();
  final ayer = hoy.subtract(const Duration(days: 1));

  group('Cambio de precio', () {
    AltaPrecio valido({double? precio, DateTime? fecha}) => AltaPrecio(
      vehiculoId: 'V001',
      fecha: fecha ?? ayer,
      precioNuevo: precio ?? 22100000,
    );

    test('una carga coherente no tiene errores', () {
      expect(valido().validar(), isEmpty);
    });

    test('rechaza guardar el mismo precio que ya tiene', () {
      // Un cambio que no cambia nada ensucia el historial y falsea la lectura
      // de "cuantas veces hubo que bajarle el precio".
      final e = valido(precio: 20000000).validar(precioActual: 20000000);
      expect(e['precio'], isNotNull);
    });

    test('acepta un precio distinto al actual', () {
      expect(
        valido(precio: 21000000).validar(precioActual: 20000000)['precio'],
        isNull,
      );
    });

    test('rechaza fechas futuras y anteriores al ingreso', () {
      final manana = hoy.add(const Duration(days: 1));
      expect(valido(fecha: manana).validar()['fecha'], isNotNull);

      final ingreso = hoy.subtract(const Duration(days: 10));
      final antes = hoy.subtract(const Duration(days: 30));
      expect(
        valido(fecha: antes).validar(fechaIngreso: ingreso)['fecha'],
        isNotNull,
      );
    });

    test('la variacion se lee contra el precio anterior', () {
      final c = CambioPrecio(
        id: '1',
        vehiculoId: 'V001',
        fecha: _fechaFija,
        precioNuevo: 90,
        precioAnterior: 100,
      );
      expect(c.variacion, closeTo(-0.10, 0.0001));
      expect(c.esBaja, isTrue);
    });

    test('el primer registro no tiene variacion', () {
      final c = CambioPrecio(
        id: '1',
        vehiculoId: 'V001',
        fecha: _fechaFija,
        precioNuevo: 100,
      );
      expect(c.variacion, isNull);
      expect(c.esBaja, isFalse);
    });

    test('el impacto se mide contra el costo ya invertido', () {
      // Costo 100, precio nuevo 125 => 20% de margen sobre venta.
      final i = ImpactoPrecio.calcular(
        costoTotal: 100,
        precioActual: 150,
        precioNuevo: 125,
      );
      expect(i.margenNuevo, closeTo(0.20, 0.0001));
      expect(i.variacion, closeTo(-1 / 6, 0.0001));
      expect(i.quedaEnPerdida, isFalse);
    });

    test('detecta cuando el precio nuevo deja la unidad a perdida', () {
      final i = ImpactoPrecio.calcular(
        costoTotal: 100,
        precioActual: 150,
        precioNuevo: 90,
      );
      expect(i.quedaEnPerdida, isTrue);
      expect(i.gananciaNueva, -10);
    });
  });

  group('Venta', () {
    AltaVenta valida({
      double? precio,
      FormaPago? forma,
      int? cuotas,
      DateTime? fecha,
      double? gastos,
    }) => AltaVenta(
      vehiculoId: 'V001',
      fechaVenta: fecha ?? ayer,
      precioFinal: precio ?? 29500000,
      gastosFinales: gastos ?? 120000,
      formaPago: forma ?? FormaPago.contado,
      cuotas: cuotas,
    );

    test('una venta al contado no pide cuotas', () {
      expect(valida().validar(), isEmpty);
      expect(valida().pideCuotas, isFalse);
    });

    test('financiada sin cuotas no se puede guardar', () {
      final v = valida(forma: FormaPago.financiacionPropia);
      expect(v.pideCuotas, isTrue);
      expect(v.validar()['cuotas'], isNotNull);
      expect(
        valida(forma: FormaPago.financiacionPropia, cuotas: 12).validar(),
        isEmpty,
      );
    });

    test('no se puede vender antes de que la unidad ingresara', () {
      final ingreso = hoy.subtract(const Duration(days: 10));
      final antes = hoy.subtract(const Duration(days: 30));
      expect(
        valida(fecha: antes).validar(fechaIngreso: ingreso)['fecha'],
        isNotNull,
      );
    });

    test('los gastos de cierre no pueden ser negativos', () {
      expect(valida(gastos: -1).validar()['gastosFinales'], isNotNull);
      expect(valida(gastos: 0).validar()['gastosFinales'], isNull);
    });
  });

  group('Resultado de la venta', () {
    ResultadoVenta r({
      double costo = 100,
      double costoHoy = 110,
      double precio = 150,
      double gastos = 10,
      double tc = 1500,
    }) => ResultadoVenta(
      costoTotal: costo,
      costoTotalHoy: costoHoy,
      precioFinal: precio,
      gastosFinales: gastos,
      tipoCambio: tc,
    );

    test('los gastos de cierre entran en el costo', () {
      expect(r().costoConCierre, 110);
      expect(r().ganancia, 40);
    });

    test('la ganancia real descuenta la inflacion del periodo', () {
      // Costo nominal 100 pero a valor de hoy 110: la erosion son 10.
      expect(r().gananciaReal, 30);
      expect(r().erosion, 10);
    });

    test(
      'detecta la operacion que gana en pesos y pierde contra la inflacion',
      () {
        final x = r(costo: 100, costoHoy: 145, precio: 150, gastos: 10);
        expect(x.ganancia, greaterThan(0));
        expect(x.gananciaReal, lessThan(0));
        expect(x.perdioContraInflacion, isTrue);
        expect(x.perdioPlata, isFalse);
      },
    );

    test('detecta la que directamente perdio plata', () {
      final x = r(precio: 90);
      expect(x.perdioPlata, isTrue);
      expect(x.perdioContraInflacion, isFalse);
    });

    test('sin tipo de cambio no divide por cero', () {
      expect(r(tc: 0).gananciaRealUsd, 0);
    });
  });
}

final _fechaFija = DateTime.utc(2026, 1, 1);
