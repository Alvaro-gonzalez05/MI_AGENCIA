import 'package:flutter/material.dart';

import 'agencias.dart';

/// Un área de la agencia: Ventas, Taller, Administración, lo que cada una
/// use. Sirve para ordenar la pizarra y entender quién es quién.
///
/// Importante: **una zona no da permisos**. Lo que cada uno ve y toca lo
/// define su rol. "Administración" no habilita nada por llamarse así.
class Zona {
  const Zona({
    required this.id,
    required this.nombre,
    this.icono = 'folder',
    this.x = 0,
    this.y = 0,
    this.cuantos = 0,
  });

  final String id;
  final String nombre;

  /// El nombre del icono, no el dibujo: así se puede cambiar la biblioteca
  /// de iconos sin migrar lo que está guardado.
  final String icono;

  /// Dónde quedó en la pizarra. Es de la agencia, no de cada usuario: el
  /// dueño la acomoda una vez y todos la ven igual.
  final double x, y;

  final int cuantos;

  IconData get dibujo => IconosZona.de(icono);

  Zona copiar({String? nombre, String? icono, double? x, double? y}) => Zona(
    id: id,
    nombre: nombre ?? this.nombre,
    icono: icono ?? this.icono,
    x: x ?? this.x,
    y: y ?? this.y,
    cuantos: cuantos,
  );
}

/// Los iconos con los que se puede marcar una zona.
///
/// Son pocos a propósito: con diez alcanza para que cada área se reconozca
/// de lejos, y una grilla de doscientos no se elige, se abandona.
abstract final class IconosZona {
  static const opciones = <String, IconData>{
    'folder': Icons.folder_outlined,
    'car': Icons.directions_car_outlined,
    'speakerphone': Icons.campaign_outlined,
    'tool': Icons.build_outlined,
    'cash': Icons.payments_outlined,
    'building-store': Icons.storefront_outlined,
    'phone': Icons.phone_outlined,
    'truck': Icons.local_shipping_outlined,
    'clipboard': Icons.assignment_outlined,
    'calculator': Icons.calculate_outlined,
  };

  static IconData de(String nombre) =>
      opciones[nombre] ?? Icons.folder_outlined;
}

/// Una persona del equipo, tal como la dibuja la pizarra.
class Miembro {
  const Miembro({
    required this.membresiaId,
    required this.usuarioId,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.activa,
    this.zonaId,
    this.zonaNombre,
    this.desde,
    this.ultimaSesion,
  });

  final String membresiaId;
  final String usuarioId;
  final String nombre;
  final String email;
  final RolMembresia rol;

  /// Si sigue entrando. Al que se va no se lo borra: se le saca el acceso,
  /// y sus ventas, sus gastos y sus clientes siguen con su nombre.
  final bool activa;

  final String? zonaId;
  final String? zonaNombre;
  final DateTime? desde;
  final DateTime? ultimaSesion;

  bool get vePlata => rol.vePlata;

  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1))
        .toUpperCase();
  }

  IconData get icono => switch (rol) {
    RolMembresia.owner => Icons.workspace_premium_outlined,
    RolMembresia.admin => Icons.shield_outlined,
    RolMembresia.vendedor => Icons.person_outline,
    RolMembresia.soloLectura => Icons.visibility_outlined,
  };
}

/// El alta de un empleado: lo que escribe el dueño antes de que exista la
/// cuenta.
class AltaMiembro {
  const AltaMiembro({
    this.nombre = '',
    this.email = '',
    this.rol = RolMembresia.vendedor,
    this.zonaId,
  });

  final String nombre;
  final String email;
  final RolMembresia rol;
  final String? zonaId;

  AltaMiembro copiar({
    String? nombre,
    String? email,
    RolMembresia? rol,
    String? zonaId,
    bool limpiarZona = false,
  }) => AltaMiembro(
    nombre: nombre ?? this.nombre,
    email: email ?? this.email,
    rol: rol ?? this.rol,
    zonaId: limpiarZona ? null : (zonaId ?? this.zonaId),
  );

  /// El usuario que se sugiere a partir del nombre y del slug de la
  /// agencia: "Nico Fredes" en "del-valle" es nico@del-valle.com. Se puede
  /// cambiar, pero casi nunca hace falta.
  static String sugerirEmail(String nombre, String slugAgencia) {
    final pila = nombre
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .split(RegExp(r'\s+'))
        .first
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (pila.isEmpty || slugAgencia.isEmpty) return '';
    return '$pila@$slugAgencia.com';
  }

  Map<String, String> validar() {
    final e = <String, String>{};
    if (nombre.trim().length < 3) {
      e['nombre'] = 'Poné el nombre de la persona.';
    }
    if (email.trim().isEmpty) {
      e['email'] = 'Poné el usuario con el que va a entrar.';
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      e['email'] = 'Ese usuario no parece un email válido.';
    }
    return e;
  }
}
