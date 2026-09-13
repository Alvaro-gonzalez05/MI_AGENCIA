import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/dominio/campanas.dart';

void main() {
  AltaCampana valida({String? asunto, String? cuerpo, String? nombre}) =>
      AltaCampana(
        nombre: nombre ?? 'Pickups en stock',
        asunto: asunto ?? 'Entró la pickup que buscabas',
        cuerpo:
            cuerpo ??
            'Hola, te escribo porque entró una unidad que puede interesarte.',
      );

  group('Validación de la campaña', () {
    test('una campaña completa no tiene errores', () {
      expect(valida().validar(), isEmpty);
    });

    test('el asunto y el mensaje son obligatorios', () {
      expect(valida(asunto: '').validar()['asunto'], isNotNull);
      expect(valida(cuerpo: 'corto').validar()['cuerpo'], isNotNull);
    });

    test('un asunto larguísimo se rechaza', () {
      // Los clientes de mail lo cortan y baja la apertura.
      expect(valida(asunto: 'a' * 200).validar()['asunto'], isNotNull);
    });

    test('acepta las variables conocidas', () {
      expect(
        valida(
          asunto: '{{nombre}}, mirá esto',
          cuerpo:
              'Hola {{nombre}}, saludos de {{agencia}}. Pasá cuando quieras.',
        ).validar(),
        isEmpty,
      );
    });

    test('una variable mal escrita no pasa', () {
      // Sin esto se manda literal: "Hola {{nombe}}".
      final e = valida(
        cuerpo: 'Hola {{nombe}}, te escribo por la unidad que viste.',
      ).validar();
      expect(e['cuerpo'], contains('{{nombe}}'));
    });
  });

  group('HTML del mail', () {
    test('escapa lo que el usuario escribe', () {
      // Si alguien escribe <b> tiene que VERSE <b>, no ponerse en negrita.
      final html = valida(
        cuerpo: 'Mirá esta <b>oferta</b> & mucho más, no te la pierdas.',
      ).html;
      expect(html, contains('&lt;b&gt;'));
      expect(html, contains('&amp;'));
      expect(html, isNot(contains('<b>oferta')));
    });

    test('arma un párrafo por bloque separado por línea en blanco', () {
      final html = valida(cuerpo: 'Primer parrafo largo.\n\nSegundo parrafo.')
          .html;
      expect('<p'.allMatches(html).length, greaterThanOrEqualTo(3));
    });

    test('el pie con la baja va siempre', () {
      // Sin eso los mails caen en spam y se quema la reputación del dominio.
      expect(valida().html.toUpperCase(), contains('BAJA'));
    });
  });

  group('Estados', () {
    test('una campaña enviada ya no se edita', () {
      expect(EstadoCampana.enviada.editable, isFalse);
      expect(EstadoCampana.enviando.editable, isFalse);
      expect(EstadoCampana.borrador.editable, isTrue);
      expect(EstadoCampana.programada.editable, isTrue);
    });

    test('un estado desconocido cae en borrador y no rompe', () {
      expect(EstadoCampana.desde('estado_nuevo'), EstadoCampana.borrador);
      expect(EstadoCampana.desde(null), EstadoCampana.borrador);
    });
  });

  group('Métricas', () {
    test('sin envíos no hay tasas que mostrar', () {
      const c = Campana(
        id: '1',
        nombre: 'x',
        asunto: 'y',
        estado: EstadoCampana.borrador,
      );
      expect(c.tasaApertura, isNull);
      expect(c.tasaClick, isNull);
    });

    test('las tasas se calculan sobre los enviados', () {
      const c = Campana(
        id: '1',
        nombre: 'x',
        asunto: 'y',
        estado: EstadoCampana.enviada,
        enviados: 200,
        aperturas: 50,
        clicks: 10,
      );
      expect(c.tasaApertura, closeTo(0.25, 0.0001));
      expect(c.tasaClick, closeTo(0.05, 0.0001));
    });
  });
}
