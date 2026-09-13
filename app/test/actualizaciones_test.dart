import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/core/actualizaciones.dart';

void main() {
  group('Comparación de versiones', () {
    test('compara número por número, no como texto', () {
      // Como texto "0.10.0" < "0.9.0"; como versión es al revés.
      expect(compararVersiones('0.10.0', '0.9.0'), greaterThan(0));
      expect(compararVersiones('0.2.0', '0.3.0'), lessThan(0));
      expect(compararVersiones('1.0.0', '1.0.0'), 0);
    });

    test('ignora la v del tag y el número de build', () {
      expect(compararVersiones('v0.3.0', '0.3.0'), 0);
      expect(compararVersiones('0.3.0+7', '0.3.0'), 0);
    });

    test('las partes que faltan valen cero', () {
      expect(compararVersiones('1.2', '1.2.0'), 0);
      expect(compararVersiones('1.2.1', '1.2'), greaterThan(0));
    });
  });

  group('Ficha de la última versión', () {
    test('lee el JSON que publica el workflow', () {
      final v = VersionDisponible.desdeJson({
        'version': '0.3.0',
        'notas': '  Arreglos varios  ',
        'obligatoria': true,
        'windows': 'https://x/MiAgencia-Setup-0.3.0.exe',
        'android_arm64': 'https://x/arm64.apk',
        'android_arm32': 'https://x/arm32.apk',
      });
      expect(v.version, '0.3.0');
      expect(v.notas, 'Arreglos varios');
      expect(v.obligatoria, isTrue);
      expect(v.urlWindows, endsWith('.exe'));
    });

    test('sin notas ni marca de obligatoria no rompe', () {
      final v = VersionDisponible.desdeJson({'version': '0.3.0'});
      expect(v.notas, isEmpty);
      expect(v.obligatoria, isFalse);
    });
  });
}
