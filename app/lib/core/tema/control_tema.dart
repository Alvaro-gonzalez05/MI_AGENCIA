import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modo de tema elegido por el usuario.
///
/// Arranca en oscuro, no en "seguir al sistema": es la identidad visual
/// elegida para el producto, y la mayoria de las agencias usan Windows en
/// claro por defecto, con lo cual "sistema" mostraria el tema que menos
/// trabajamos. Quien prefiera claro lo cambia y queda.
///
/// PENDIENTE: persistir la eleccion (shared_preferences). Hoy se pierde al
/// cerrar la app.
class ControlTema extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void alternar() => state =
      state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

  void poner(ThemeMode modo) => state = modo;
}

final temaProvider = NotifierProvider<ControlTema, ThemeMode>(ControlTema.new);
