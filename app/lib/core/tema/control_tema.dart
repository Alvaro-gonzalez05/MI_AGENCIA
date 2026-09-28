import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Modo de tema elegido por el usuario.
///
/// Arranca en CLARO, no en "seguir al sistema": es la identidad del diseno
/// "Clarity Drive" (fondo papel calido, pensado para ocho horas de pantalla)
/// y es como el cliente aprobo las pantallas. Quien prefiera oscuro lo
/// cambia desde Mas y queda.
///
/// PENDIENTE: persistir la eleccion (shared_preferences). Hoy se pierde al
/// cerrar la app.
class ControlTema extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void alternar() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;

  void poner(ThemeMode modo) => state = modo;
}

final temaProvider = NotifierProvider<ControlTema, ThemeMode>(ControlTema.new);
