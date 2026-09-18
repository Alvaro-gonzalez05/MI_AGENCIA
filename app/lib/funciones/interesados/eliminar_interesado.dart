import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/confirmacion.dart';

/// Pide confirmación y elimina una ficha completa de interés.
///
/// Devuelve `true` únicamente cuando la base confirmó el borrado. Los dos
/// accesos (lista y ficha) comparten este flujo para no tener mensajes ni
/// consecuencias distintas según desde dónde se borre.
Future<bool> eliminarInteresadoConConfirmacion(
  BuildContext context,
  WidgetRef ref,
  Interesado interesado,
) async {
  final confirmado = await confirmarAccion(
    context,
    titulo: '¿Eliminar a ${interesado.nombre}?',
    descripcion:
        'Se eliminarán este interés y sus informes PDF. Si la persona no '
        'tiene otra operación, también se borrarán su ficha y las consultas '
        'crediticias guardadas.',
    confirmar: 'Sí, eliminar',
    icono: Icons.person_remove_outlined,
    peligrosa: true,
  );
  if (!confirmado || !context.mounted) return false;

  try {
    await ref.read(repositorioProvider).eliminarInteresado(interesado);
    ref.invalidate(interesadosProvider);
    if (context.mounted) {
      confirmarEliminado(context, '${interesado.nombre} fue eliminado');
    }
    return true;
  } catch (error) {
    if (context.mounted) mostrarError(context, error);
    return false;
  }
}
