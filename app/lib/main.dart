import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/router.dart';
import 'core/tema/control_tema.dart';
import 'core/tema/tema.dart';

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
