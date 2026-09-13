import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

/// Actualizaciones automaticas.
///
/// Cada vez que se publica una version, el workflow de GitHub sube los
/// instaladores a Storage y reescribe `ultima.json`. La app lee ese archivo
/// al abrir y cada unas horas; si hay una version mas nueva, avisa.
///
/// Es un archivo publico y no una consulta a la base a proposito: funciona
/// antes de iniciar sesion, en modo demo, y sin tocar el RLS.
@immutable
class VersionDisponible {
  const VersionDisponible({
    required this.version,
    required this.notas,
    required this.obligatoria,
    this.urlWindows,
    this.urlAndroidArm64,
    this.urlAndroidArm32,
  });

  factory VersionDisponible.desdeJson(Map<String, dynamic> j) =>
      VersionDisponible(
        version: j['version'] as String,
        notas: (j['notas'] as String?)?.trim() ?? '',
        obligatoria: j['obligatoria'] == true,
        urlWindows: j['windows'] as String?,
        urlAndroidArm64: j['android_arm64'] as String?,
        urlAndroidArm32: j['android_arm32'] as String?,
      );

  final String version;
  final String notas;

  /// Si es obligatoria la app no deja seguir hasta actualizar. Para cuando
  /// cambia algo de la base que las versiones viejas no entienden.
  final bool obligatoria;

  final String? urlWindows;
  final String? urlAndroidArm64;
  final String? urlAndroidArm32;

  /// El instalador que corresponde a este equipo, o null si no hay.
  String? get urlParaEstaPlataforma {
    if (kIsWeb) return null;
    if (Platform.isWindows) return urlWindows;
    if (Platform.isAndroid) {
      // Platform.version termina en "android_arm64", "android_arm" o
      // "android_x64". Los celulares de 32 bits son los unicos que necesitan
      // el APK arm32; todo lo demas usa el de 64.
      final es32 =
          Platform.version.contains('android_arm') &&
          !Platform.version.contains('android_arm64');
      return es32
          ? (urlAndroidArm32 ?? urlAndroidArm64)
          : (urlAndroidArm64 ?? urlAndroidArm32);
    }
    return null;
  }
}

/// Compara versiones "mayor.menor.parche". Negativo si a < b.
int compararVersiones(String a, String b) {
  List<int> partes(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^v'), '')
      .split('+')
      .first
      .split('.')
      .map((x) => int.tryParse(x) ?? 0)
      .toList();

  final pa = partes(a);
  final pb = partes(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Devuelve la version nueva si hay una para esta plataforma, o null.
///
/// Nunca tira excepcion: sin internet, o si el archivo todavia no existe, la
/// app tiene que seguir funcionando igual.
Future<VersionDisponible?> buscarActualizacion() async {
  if (kIsWeb || Config.version.isEmpty) return null;

  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    // El parametro evita que la CDN devuelva una copia vieja del archivo.
    final uri = Uri.parse(Config.urlActualizaciones).replace(
      queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    final pedido = await cliente.getUrl(uri);
    final respuesta = await pedido.close().timeout(const Duration(seconds: 10));
    if (respuesta.statusCode != 200) return null;

    final cuerpo = await respuesta.transform(utf8.decoder).join();
    final v = VersionDisponible.desdeJson(
      jsonDecode(cuerpo) as Map<String, dynamic>,
    );
    if (compararVersiones(v.version, Config.version) <= 0) return null;
    if (v.urlParaEstaPlataforma == null) return null;
    return v;
  } catch (_) {
    return null;
  } finally {
    cliente.close();
  }
}

/// Version nueva disponible. Se vuelve a consultar sola cada 6 horas: en una
/// agencia la app queda abierta todo el dia.
final actualizacionProvider = FutureProvider<VersionDisponible?>((ref) {
  final temporizador = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(temporizador.cancel);
  return buscarActualizacion();
});

/// Descarga e instala la version.
///
/// - **Windows**: baja el instalador, lo ejecuta en modo silencioso y cierra
///   la app. El instalador reemplaza los archivos y la vuelve a abrir.
/// - **Android**: abre la descarga del APK. Android no permite instalar sin
///   que el usuario confirme, asi que el ultimo toque es suyo.
Future<void> instalarActualizacion(
  VersionDisponible v, {
  required void Function(double? progreso) alProgresar,
}) async {
  final url = v.urlParaEstaPlataforma;
  if (url == null) {
    throw StateError('No hay instalador para este equipo.');
  }

  if (!kIsWeb && Platform.isWindows) {
    final destino = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'MiAgencia-Setup-${v.version}.exe',
    );

    final cliente = HttpClient();
    try {
      final respuesta = await (await cliente.getUrl(Uri.parse(url))).close();
      if (respuesta.statusCode != 200) {
        throw HttpException('El servidor respondió ${respuesta.statusCode}');
      }
      final total = respuesta.contentLength;
      var recibidos = 0;
      final salida = destino.openWrite();
      try {
        await for (final bloque in respuesta) {
          salida.add(bloque);
          recibidos += bloque.length;
          alProgresar(total > 0 ? recibidos / total : null);
        }
      } finally {
        await salida.close();
      }
    } finally {
      cliente.close();
    }

    await Process.start(destino.path, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
    // La app tiene que estar cerrada para que el instalador pueda pisar el
    // ejecutable.
    exit(0);
  }

  final abierta = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!abierta) {
    throw StateError('No se pudo abrir la descarga.');
  }
}
