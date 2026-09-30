import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/formato.dart';
import 'core/router.dart';
import 'core/tema/control_tema.dart';
import 'core/tema/preferencias.dart';
import 'core/tema/tema.dart';
import 'ui/aviso_actualizacion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nombres de meses y separadores de miles en castellano rioplatense.
  await initializeDateFormatting('es_AR');

  if (!Config.modoDemo) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  }

  runApp(const ProviderScope(child: MiAgencia()));
}

class MiAgencia extends ConsumerWidget {
  const MiAgencia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Mi Agencia',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      // El tamaño de letra elegido en "Más" se aplica acá, una sola vez,
      // multiplicando el del sistema: si alguien ya agrandó la letra en
      // Windows o en Android, se respeta y se suma.
      builder: (context, child) {
        final escala = ref.watch(tamanoLetraProvider).escala;
        // Los montos se formatean con una funcion estatica (Fmt.pesos), asi
        // que la preferencia se copia ahi y se repinta todo con una clave
        // distinta: es la unica forma de que cambien las cifras ya dibujadas
        // sin pasar la preferencia por las cien pantallas que las muestran.
        final ocultar = ref.watch(ocultarMontosProvider);
        Fmt.ocultarMontos = ocultar;
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: escala,
          maxScaleFactor: escala * 1.3,
          child: KeyedSubtree(
            key: ValueKey(ocultar),
            child: CapaActualizacion(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
      theme: TemaApp.claro(),
      darkTheme: TemaApp.oscuro(),
      themeMode: ref.watch(temaProvider),
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
