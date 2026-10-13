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
    this.soloPlata = false,
    this.soloAdministra = false,
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

  /// Visible solo para quien ve la plata (dueño y administrador). Una
  /// sección entera de márgenes y ganancias no se le muestra al vendedor.
  final bool soloPlata;

  /// Visible solo para quien maneja el equipo (dueño y administrador).
  final bool soloAdministra;

  /// Los cinco lugares del diseño: Inicio, Inventario, Cargar, Clientes y
  /// Más. Todo lo demás se llega desde Cargar (las altas) o desde Más (las
  /// herramientas): el que usa la app tiene cinco destinos, no once.
  final bool enBarraInferior;
}

abstract final class Secciones {
  static const panel = Seccion(
    id: 'panel',
    etiqueta: 'Inicio',
    ruta: '/panel',
    icono: Icons.home_outlined,
    grupo: 'Gestión',
    titulo: 'Inicio',
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

  /// La ruta sigue siendo /interesados: la cambian los enlaces guardados y
  /// los deep links de las campañas. Lo que cambió es el nombre visible, que
  /// es como la agencia los llama de verdad.
  static const interesados = Seccion(
    id: 'interesados',
    etiqueta: 'Clientes',
    ruta: '/interesados',
    icono: Icons.people_outline,
    grupo: 'Gestión',
    titulo: 'Clientes',
    subtitulo: 'Interesados y compradores, con semáforo crediticio del BCRA',
    enBarraInferior: true,
  );

  /// "Cargar" es una sección de verdad, como en el diseño: una pantalla que
  /// pregunta qué querés cargar y lleva a cada alta. Antes era una hoja que
  /// subía desde el "+", y eso dejaba cuatro secciones sueltas en el menú.
  static const cargarDatos = Seccion(
    id: 'cargar',
    etiqueta: 'Cargar',
    ruta: '/cargar',
    icono: Icons.add_circle_outline_rounded,
    grupo: 'Gestión',
    titulo: '¿Qué querés cargar?',
    subtitulo: 'Elegí una opción para continuar',
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

  static const estadisticas = Seccion(
    id: 'estadisticas',
    etiqueta: 'Estadísticas',
    ruta: '/estadisticas',
    icono: Icons.insights_outlined,
    grupo: 'Gestión',
    titulo: 'Estadísticas',
    subtitulo: 'Cómo vienen las ventas, los tiempos y las ganancias',
    soloPlata: true,
  );

  static const simulador = Seccion(
    id: 'simulador',
    etiqueta: 'Simulador',
    ruta: '/simulador',
    icono: Icons.calculate_outlined,
    grupo: 'Gestión',
    titulo: 'Simulador de financiamiento',
    subtitulo: 'Calculá la cuota para mostrarle al cliente',
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

  static const equipo = Seccion(
    id: 'equipo',
    etiqueta: 'Equipo',
    ruta: '/equipo',
    icono: Icons.groups_outlined,
    grupo: 'Sistema',
    titulo: 'Usuarios y permisos',
    subtitulo: 'Quién usa el sistema y qué ve cada uno',
    soloAdministra: true,
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
    cargarDatos,
    interesados,
    vehiculos,
    gastos,
    precios,
    ventas,
    campanas,
    estadisticas,
    simulador,
    configuracion,
    equipo,
    agencias,
  ];

  static List<Seccion> visibles({
    required bool esDesarrollador,
    bool vePlata = true,
    bool administra = true,
  }) => todas
      .where((s) => !s.soloDesarrollador || esDesarrollador)
      .where((s) => !s.soloPlata || vePlata)
      .where((s) => !s.soloAdministra || administra)
      .toList(growable: false);

  static List<Seccion> get barraInferior =>
      todas.where((s) => s.enBarraInferior).toList(growable: false);

  /// Lo que se carga a mano, en el orden en que sucede en la agencia: entra
  /// la unidad, se le hacen gastos, se le pone precio, se vende. Es lo que
  /// ofrece la sección "Cargar".
  static const cargar = <Seccion>[vehiculos, gastos, precios, ventas];

  /// Las herramientas de "Más" que le corresponden a quien está mirando.
  static List<Seccion> herramientasPara({
    required bool vePlata,
    bool administra = true,
  }) => herramientas
      .where((s) => !s.soloPlata || vePlata)
      .where((s) => !s.soloAdministra || administra)
      .toList(growable: false);

  /// Las herramientas que viven en "Más".
  static const herramientas = <Seccion>[
    estadisticas,
    simulador,
    campanas,
    equipo,
    configuracion,
  ];

  static Seccion? porRuta(String ruta) {
    for (final s in todas) {
      if (ruta == s.ruta || ruta.startsWith('${s.ruta}/')) return s;
    }
    return null;
  }
}
