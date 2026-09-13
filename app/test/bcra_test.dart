import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/dominio/bcra.dart';
import 'package:mi_agencia/dominio/modelos.dart';

/// El semaforo crediticio y el parseo de lo que devuelve el BCRA.
///
/// Los casos del semaforo salen de tests/casos_semaforo.json, el MISMO
/// archivo que corre tests/semaforo_bcra.mjs contra Postgres. Si el criterio
/// se cambia en un solo lado, una de las dos suites falla. Eso es a
/// proposito: son dos implementaciones del mismo criterio y tienen que
/// seguir diciendo lo mismo.
void main() {
  group('Semaforo crediticio', () {
    final archivo = File('../tests/casos_semaforo.json');

    test('el archivo de casos existe', () {
      expect(
        archivo.existsSync(),
        isTrue,
        reason:
            'tests/casos_semaforo.json es el contrato entre el semaforo en '
            'SQL y el semaforo en Dart. Sin el archivo no hay nada que atar.',
      );
    });

    final casos =
        (jsonDecode(archivo.readAsStringSync())
                as Map<String, dynamic>)['casos']
            as List;

    for (final crudo in casos) {
      final c = crudo as Map<String, dynamic>;
      final nombre = c['caso'] as String;

      test(nombre, () {
        final consultado = c['consultado'] as bool? ?? true;
        final cantidad = c['entidades'] as int? ?? 1;
        final situacion = c['situacion'] as int?;

        if (!consultado) {
          // Nunca consultado no es una consulta vacia: es que no hay consulta.
          const i = Interesado(id: 'x', clienteId: 'x', nombre: 'Sin datos');
          expect(i.semaforo, SemaforoCrediticio.sinDatos);
          expect(_texto(i.semaforo), c['esperado']);
          return;
        }

        final consulta = ConsultaBcra(
          cuit: '20111111112',
          consultadoEl: DateTime(2026, 9, 1),
          // La peor situacion primero y el resto normales: es como llega la
          // lista de entidades una vez ordenada.
          entidades: [
            for (var n = 0; n < cantidad; n++)
              EntidadBcra(
                entidad: 'Entidad ${n + 1}',
                situacion: n == 0 ? (situacion ?? 1) : 1,
                montoMiles: 100,
              ),
          ],
          situacionMaxima: cantidad == 0 ? null : situacion,
          chequesSinPagar: c['chequesSinPagar'] as int? ?? 0,
          chequesRechazados: c['chequesRechazados'] as bool? ?? false,
          tieneProcesoJudicial: c['procesoJudicial'] as bool? ?? false,
          tieneRefinanciaciones: c['refinanciaciones'] as bool? ?? false,
          diasAtrasoMax: c['diasAtraso'] as int? ?? 0,
        );

        expect(
          _texto(consulta.semaforo),
          c['esperado'],
          reason:
              'El criterio en Dart se separo del que tiene la base. '
              'Compara ConsultaBcra.semaforo con v_clientes_semaforo.',
        );

        expect(consulta.sinDeudasInformadas, cantidad == 0);

        // Cualquiera sea el color, siempre se explica por que. Un semaforo
        // sin motivo no le sirve al vendedor para hablar con el cliente.
        expect(consulta.motivos, isNotEmpty);
        expect(consulta.recomendacion, isNotEmpty);
      });
    }
  });

  group('Validacion de CUIT', () {
    test('acepta CUIT reales', () {
      // Consultados de verdad contra el BCRA: son personas juridicas y sus
      // CUIT son publicos. 30500003193 es el Banco BBVA Argentina.
      for (final cuit in ['30500003193', '33693450239', '27230938607']) {
        expect(cuitValido(cuit), isTrue, reason: cuit);
      }
    });

    test('rechaza un digito verificador equivocado', () {
      // 30500003193 es valido; cambiarle el ultimo digito no lo es.
      expect(cuitValido('30500003194'), isFalse);

      // Este numero parece un CUIT y no lo es. Salio de una prueba contra el
      // BCRA: sin validar el digito, se manda igual, el BCRA contesta 404 y
      // ese 404 se lee como "no tiene deudas". Un error de tipeo pintaria de
      // verde a cualquiera, que es exactamente lo que no puede pasar aca.
      expect(cuitValido('30546676497'), isFalse);
    });

    test('rechaza largos que no sean 11', () {
      expect(cuitValido('3050000319'), isFalse);
      expect(cuitValido('305000031933'), isFalse);
      expect(cuitValido(''), isFalse);
    });

    test('rechaza letras', () {
      expect(cuitValido('3050000319A'), isFalse);
    });

    test('ignora guiones y espacios', () {
      expect(cuitValido('30-50000319-3'), isTrue);
      expect(cuitValido(' 30 50000319 3 '), isTrue);
    });

    test('formatea con guiones', () {
      expect(formatearCuit('30500003193'), '30-50000319-3');
      // Si no son 11 digitos se devuelve tal cual: mejor mostrar lo que hay
      // que inventar un formato sobre un dato incompleto.
      expect(formatearCuit('123'), '123');
    });
  });

  group('Parseo de la respuesta del BCRA', () {
    test('convierte los miles de pesos que informa el BCRA', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-09-01T10:00:00Z',
        'total_deuda_miles': 1500,
        'entidades': [
          {'entidad': 'BANCO X', 'situacion': 1, 'monto': 1500},
        ],
      });

      // 1500 "miles" son 1.500.000 pesos. Mostrar 1500 seria informar mil
      // veces menos deuda de la que la persona tiene.
      expect(c.totalDeuda, 1500000);
      expect(c.entidades.single.monto, 1500000);
    });

    test('lee los numeric que Postgres manda como string', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-09-01T10:00:00Z',
        'total_deuda_miles': '2500.50',
      });
      expect(c.totalDeuda, 2500500);
    });

    test('ordena las entidades de peor a mejor', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-09-01T10:00:00Z',
        'entidades': [
          {'entidad': 'A', 'situacion': 1, 'monto': 10},
          {'entidad': 'B', 'situacion': 4, 'monto': 20},
          {'entidad': 'C', 'situacion': 2, 'monto': 30},
        ],
      });
      expect(c.entidades.map((e) => e.entidad), ['B', 'C', 'A']);
    });

    test('aplana los cheques y pone los impagos primero', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-09-01T10:00:00Z',
        'cheques': [
          {
            'causal': 'SIN FONDOS',
            'entidades': [
              {
                'entidad': 'BANCO X',
                'detalle': [
                  {
                    'nroCheque': '111',
                    'monto': 5000,
                    'fechaRechazo': '2026-05-10',
                    'fechaPago': '2026-05-20',
                  },
                  {
                    'nroCheque': '222',
                    'monto': 8000,
                    'fechaRechazo': '2026-06-01',
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(c.cheques.length, 2);
      expect(c.cheques.first.numero, '222');
      expect(c.cheques.first.pagado, isFalse);
      expect(c.cheques.last.pagado, isTrue);
      expect(c.cheques.first.causal, 'SIN FONDOS');
      expect(c.cheques.first.entidad, 'BANCO X');
    });

    test('una respuesta sin deudas no es un error', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-09-01T10:00:00Z',
        'situacion_maxima': null,
        'entidades': [],
      });

      expect(c.sinDeudasInformadas, isTrue);
      expect(c.semaforo, SemaforoCrediticio.verde);
      // Pero el informe tiene que aclarar que no tiene historial: verde por
      // ausencia de datos no es lo mismo que verde por buen cumplimiento.
      expect(c.recomendacion, contains('historial'));
    });

    test('traduce el periodo del BCRA a algo legible', () {
      ConsultaBcra conPeriodo(String? p) => ConsultaBcra(
        cuit: '20111111112',
        consultadoEl: DateTime(2026, 9, 1),
        entidades: const [],
        periodo: p,
      );

      expect(conPeriodo('202607').periodoLegible, 'julio 2026');
      expect(conPeriodo('202601').periodoLegible, 'enero 2026');
      expect(conPeriodo('202612').periodoLegible, 'diciembre 2026');
      // Basura adentro, nada afuera: mejor no mostrar periodo que mostrar uno
      // inventado.
      expect(conPeriodo('2026').periodoLegible, '');
      expect(conPeriodo('202699').periodoLegible, '');
      expect(conPeriodo(null).periodoLegible, '');
    });

    test('marca como vencida la consulta que la vista dio por vencida', () {
      final c = ConsultaBcra.desdeJson({
        'cuit': '20111111112',
        'consultado_at': '2026-01-01T10:00:00Z',
        'consulta_vencida': true,
      });
      expect(c.vencida, isTrue);
    });
  });

  group('Descripcion de cada situacion', () {
    test('las seis situaciones del BCRA tienen texto propio', () {
      final textos = <String>{};
      for (var s = 1; s <= 6; s++) {
        final e = EntidadBcra(entidad: 'X', situacion: s, montoMiles: 0);
        expect(e.descripcionSituacion, isNotEmpty);
        expect(e.queSignifica, isNotEmpty);
        textos.add(e.descripcionSituacion);
      }
      // Ninguna repetida: si dos situaciones dijeran lo mismo, el desglose
      // por entidad no serviria para nada.
      expect(textos.length, 6);
    });
  });
}

String _texto(SemaforoCrediticio s) => switch (s) {
  SemaforoCrediticio.verde => 'verde',
  SemaforoCrediticio.amarillo => 'amarillo',
  SemaforoCrediticio.rojo => 'rojo',
  SemaforoCrediticio.sinDatos => 'sin_datos',
};
