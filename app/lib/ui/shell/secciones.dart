import 'package:flutter/material.dart';

/// Una entrada de navegacion.
class Seccion {
  const Seccion({
    required this.id,
    required this.etiqueta,
    required this.ruta,
    required this.icono,
    required this.grupo,
    required this.titulo,
    required this.subtitulo,
    this.soloDesarrollador = false,
    this.enBarraInferior = false,
  });

  final String id;
  final String etiqueta;
  final String ruta;
  final IconData icono;
  final String grupo;

  /// Encabezado de la pantalla. Se separa de [etiqueta] porque en el menu
  /// conviene una palabra y arriba conviene una frase.
  final String titulo;
  final String subtitulo;

  /// Visible solo para la cuenta de plataforma (nosotros).
  final bool soloDesarrollador;

  /// En movil no entran diez destinos abajo: solo estos cinco, el resto va
  /// en la hoja de "Más".
  final bool enBarraInferior;
}

abstract final class Secciones {
  static const panel = Seccion(
    id: 'panel',
    etiqueta: 'Panel',
    ruta: '/panel',
    icono: Icons.dashboard_outlined,
    grupo: 'Gestión',
    titulo: 'Panel',
    subtitulo: 'Estado del negocio de un vistazo',
    enBarraInferior: true,
  );

  static const inventario = Seccion(
    id: 'inventario',
    etiqueta: 'Inventario',
    ruta: '/inventario',
    icono: Icons.inventory_2_outlined,
    grupo: 'Gestión',
    titulo: 'Inventario',
    subtitulo: 'Todas las unidades con sus costos y márgenes',
    enBarraInferior: true,
  );

  static const interesados = Seccion(
    id: 'interesados',
    etiqueta: 'Interesados',
    ruta: '/interesados',
    icono: Icons.people_outline,
    grupo: 'Gestión',
    titulo: 'Interesados',
    subtitulo: 'Embudo de venta con semáforo crediticio del BCRA',
    enBarraInferior: true,
  );

  static const vehiculos = Seccion(
    id: 'vehiculos',
    etiqueta: 'Vehículos',
    ruta: '/vehiculos',
    icono: Icons.directions_car_outlined,
    grupo: 'Carga de datos',
    titulo: 'Vehículos',
    subtitulo: 'Alta y edición de unidades',
    enBarraInferior: true,
  );

  static const gastos = Seccion(
    id: 'gastos',
    etiqueta: 'Gastos',
    ruta: '/gastos',
    icono: Icons.receipt_long_outlined,
    grupo: 'Carga de datos',
    titulo: 'Gastos',
    subtitulo: 'Todo lo invertido en cada unidad',
  );

  static const precios = Seccion(
    id: 'precios',
    etiqueta: 'Precios',
    ruta: '/precios',
    icono: Icons.sell_outlined,
    grupo: 'Carga de datos',
    titulo: 'Precios',
    subtitulo: 'Historial de cambios de precio',
  );

  static const ventas = Seccion(
    id: 'ventas',
    etiqueta: 'Ventas',
    ruta: '/ventas',
    icono: Icons.check_circle_outline,
    grupo: 'Carga de datos',
    titulo: 'Ventas',
    subtitulo: 'Al cargar una venta, la unidad sale del stock',
  );

  static const campanas = Seccion(
    id: 'campanas',
    etiqueta: 'Campañas',
    ruta: '/campanas',
    icono: Icons.campaign_outlined,
    grupo: 'Crecimiento',
    titulo: 'Campañas',
    subtitulo: 'Email marketing a la base de interesados',
  );

  static const configuracion = Seccion(
    id: 'configuracion',
    etiqueta: 'Configuración',
    ruta: '/configuracion',
    icono: Icons.tune_outlined,
    grupo: 'Sistema',
    titulo: 'Configuración',
    subtitulo: 'Umbrales y parámetros — todo se recalcula solo',
  );

  static const agencias = Seccion(
    id: 'agencias',
    etiqueta: 'Agencias',
    ruta: '/agencias',
    icono: Icons.apartment_outlined,
    grupo: 'Desarrollador',
    titulo: 'Agencias',
    subtitulo: 'Alta y administración de cuentas de clientes',
    soloDesarrollador: true,
  );

  static const todas = <Seccion>[
    panel,
    inventario,
    interesados,
    vehiculos,
    gastos,
    precios,
    ventas,
    campanas,
    configuracion,
    agencias,
  ];

  static List<Seccion> visibles({required bool esDesarrollador}) => todas
      .where((s) => !s.soloDesarrollador || esDesarrollador)
      .toList(growable: false);

  static List<Seccion> get barraInferior =>
      todas.where((s) => s.enBarraInferior).toList(growable: false);

  static Seccion? porRuta(String ruta) {
    for (final s in todas) {
      if (ruta == s.ruta || ruta.startsWith('${s.ruta}/')) return s;
    }
    return null;
  }
}
