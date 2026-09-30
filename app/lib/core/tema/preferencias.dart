import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuánto más grande se lee todo.
///
/// Es la preferencia "Tamaño de la letra" del diseño (A / A+ / A++). No es
/// un capricho: el sistema lo usan ocho horas por día personas que ya usan
/// anteojos, y en una pantalla de escritorio a un metro de distancia el
/// tamaño cómodo no es el mismo que en un celular en la mano.
enum TamanoLetra {
  normal('A', 'Normal', 1.0),
  grande('A+', 'Grande', 1.15),
  enorme('A++', 'Muy grande', 1.3);

  const TamanoLetra(this.simbolo, this.etiqueta, this.escala);
  final String simbolo;
  final String etiqueta;
  final double escala;
}

class ControlTamano extends Notifier<TamanoLetra> {
  @override
  TamanoLetra build() => TamanoLetra.normal;

  void poner(TamanoLetra v) => state = v;
}

/// PENDIENTE: persistir la elección (shared_preferences), igual que el tema.
final tamanoLetraProvider = NotifierProvider<ControlTamano, TamanoLetra>(
  ControlTamano.new,
);

/// "Ocultar montos al abrir": la plata se ve como `$ ***` hasta que se
/// apaga la preferencia.
///
/// El valor vive en [Fmt.ocultarMontos] porque los montos se formatean en
/// cientos de lugares con una funcion estatica; la pantalla de "Mas" cambia
/// la preferencia y `main` la copia ahi y repinta la app.
class ControlOcultarMontos extends Notifier<bool> {
  @override
  bool build() => false;

  void alternar() => state = !state;
}

final ocultarMontosProvider = NotifierProvider<ControlOcultarMontos, bool>(
  ControlOcultarMontos.new,
);
