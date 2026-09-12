/// Configuracion de entorno.
///
/// Las credenciales entran por --dart-define, nunca hardcodeadas en el codigo
/// ni en un .env commiteado:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
///
/// El script scripts/dev.ps1 las toma de las variables de entorno y las pasa
/// solo. Si no estan, la app arranca en MODO DEMO.
abstract final class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Sin backend configurado la app corre contra los datos de ejemplo del
  /// sistema original del cliente, en memoria.
  ///
  /// No es un atajo para salir del paso: permite mostrar la app completa antes
  /// de que exista la base, y deja las pantallas probables sin depender de la
  /// red. Cuando se definen las dos variables, se apaga solo.
  static bool get modoDemo => supabaseUrl.isEmpty || supabaseAnonKey.isEmpty;
}
