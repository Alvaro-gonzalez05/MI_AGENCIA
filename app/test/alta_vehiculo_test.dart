import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/dominio/alta_vehiculo.dart';

void main() {
  final hoy = DateTime.now();
  final ayer = hoy.subtract(const Duration(days: 1));

  AltaVehiculo valido({
    DateTime? compra,
    DateTime? ingreso,
    double? precioCompra,
    double? precioObjetivo,
    int? anio,
    int? km,
  }) => AltaVehiculo(
    marca: 'Toyota',
    modelo: 'Corolla',
    anio: anio ?? 2021,
    km: km,
    fechaCompra: compra ?? ayer,
    fechaIngreso: ingreso ?? hoy,
    precioCompra: precioCompra ?? 19800000,
    precioObjetivo: precioObjetivo ?? 22500000,
  );

  group('Validacion del alta', () {
    test('una carga completa y coherente no tiene errores', () {
      expect(valido().validar(), isEmpty);
    });

    test('marca y modelo son obligatorios', () {
      const vacio = AltaVehiculo();
      final e = vacio.validar();
      expect(e['marca'], isNotNull);
      expect(e['modelo'], isNotNull);
    });

    test('no se puede ingresar al predio antes de haber comprado', () {
      // Es la misma regla que el check fecha_ingreso_coherente de la base.
      final v = valido(compra: hoy, ingreso: ayer);
      expect(v.validar()['fechaIngreso'], isNotNull);
    });

    test('ninguna fecha puede ser futura', () {
      final manana = hoy.add(const Duration(days: 1));
      expect(valido(compra: manana).validar()['fechaCompra'], isNotNull);
      expect(valido(ingreso: manana).validar()['fechaIngreso'], isNotNull);
    });

    test('el precio objetivo tiene que superar al de compra', () {
      // Cargar una unidad a perdida casi siempre es un error de tipeo.
      final v = valido(precioCompra: 20000000, precioObjetivo: 18000000);
      expect(v.validar()['precioObjetivo'], isNotNull);
    });

    test('los precios no pueden ser cero ni negativos', () {
      expect(valido(precioCompra: 0).validar()['precioCompra'], isNotNull);
      expect(valido(precioObjetivo: 0).validar()['precioObjetivo'], isNotNull);
    });

    test('el anio tiene que ser plausible', () {
      expect(valido(anio: 1800).validar()['anio'], isNotNull);
      expect(valido(anio: hoy.year + 5).validar()['anio'], isNotNull);
      // El modelo del anio que viene es normal en el rubro.
      expect(valido(anio: hoy.year + 1).validar()['anio'], isNull);
    });

    test('el kilometraje es opcional pero no negativo', () {
      expect(valido(km: null).validar()['km'], isNull);
      expect(valido(km: 0).validar()['km'], isNull);
      expect(valido(km: -5).validar()['km'], isNotNull);
    });
  });

  group('Margen inicial', () {
    test('se mide sobre el precio de venta, no sobre el costo', () {
      // Compra 100, objetivo 125 => 20% sobre venta (no 25% sobre costo).
      final v = valido(precioCompra: 100, precioObjetivo: 125);
      expect(v.margenInicial, closeTo(0.20, 0.0001));
    });

    test('sin los dos precios no hay margen que mostrar', () {
      expect(const AltaVehiculo().margenInicial, isNull);
      expect(const AltaVehiculo(precioCompra: 100).margenInicial, isNull);
    });
  });

  group('Edicion', () {
    test('sin id es un alta, con id es una edicion', () {
      expect(const AltaVehiculo().esEdicion, isFalse);
      expect(const AltaVehiculo(id: 'abc').esEdicion, isTrue);
    });

    test('copiar conserva el id y el codigo', () {
      const v = AltaVehiculo(id: 'abc', codigo: 'V007');
      final c = v.copiar(marca: 'Ford');
      expect(c.id, 'abc');
      expect(c.codigo, 'V007');
      expect(c.marca, 'Ford');
    });
  });
}
