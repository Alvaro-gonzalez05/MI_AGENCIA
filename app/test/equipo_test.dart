import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mi_agencia/core/sesion.dart';
import 'package:mi_agencia/core/tema/tema.dart';
import 'package:mi_agencia/datos/repositorio.dart';
import 'package:mi_agencia/dominio/agencias.dart';
import 'package:mi_agencia/dominio/equipo.dart';
import 'package:mi_agencia/funciones/equipo/ficha_miembro.dart';
import 'package:mi_agencia/funciones/equipo/pizarra_equipo.dart';

/// La pizarra de usuarios.
///
/// Dos cosas se prueban acá: que el dueño pueda armar su equipo, y que el
/// que no manda no vea los botones que no le corresponden. Lo segundo no
/// reemplaza al RLS —la base es la que dice que no— pero evita ofrecerle a
/// alguien un botón que le va a dar error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('es_AR'));

  Usuario quien(RolMembresia rol) => Usuario(
    id: 'u1',
    email: 'quien@agencia.test',
    nombre: 'Quien Mira',
    esDesarrollador: false,
    agenciaId: 'a1',
    rol: rol.valorBd,
  );

  Future<void> abrir(
    WidgetTester t,
    Widget pantalla,
    RolMembresia rol, {
    Size tamano = const Size(1280, 1000),
  }) async {
    t.view.physicalSize = tamano;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          repositorioProvider.overrideWithValue(RepositorioDemo()),
          usuarioProvider.overrideWithValue(quien(rol)),
        ],
        child: MaterialApp(
          theme: TemaApp.claro(),
          home: Scaffold(body: pantalla),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  group('El alta de un empleado', () {
    test('necesita nombre y un usuario que sea un email', () {
      expect(
        const AltaMiembro().validar().keys,
        containsAll(['nombre', 'email']),
      );
      expect(
        const AltaMiembro(
          nombre: 'Nico Fredes',
          email: 'nico',
        ).validar()['email'],
        isNotNull,
      );
      expect(
        const AltaMiembro(
          nombre: 'Nico Fredes',
          email: 'nico@delvalle.com',
        ).validar(),
        isEmpty,
      );
    });

    test('sugiere el usuario a partir del nombre y la agencia', () {
      expect(
        AltaMiembro.sugerirEmail('Nico Fredes', 'del-valle'),
        'nico@del-valle.com',
      );
      // Sin acentos ni eñes: el email tiene que poder dictarse y tipearse.
      expect(
        AltaMiembro.sugerirEmail('Íñigo Montoya', 'automotores'),
        'inigo@automotores.com',
      );
      expect(AltaMiembro.sugerirEmail('', 'automotores'), '');
    });
  });

  group('Los roles', () {
    test('dicen quién maneja el equipo', () {
      expect(RolMembresia.owner.puedeAdministrar, isTrue);
      expect(RolMembresia.admin.puedeAdministrar, isTrue);
      expect(RolMembresia.vendedor.puedeAdministrar, isFalse);
      expect(RolMembresia.soloLectura.puedeAdministrar, isFalse);
    });
  });

  group('Los iconos de zona', () {
    test('uno que no existe no rompe la pizarra', () {
      // Pasa si alguna vez se cambia la biblioteca de iconos y queda un
      // nombre viejo guardado.
      expect(IconosZona.de('pajarito'), Icons.folder_outlined);
      expect(IconosZona.de('car'), Icons.directions_car_outlined);
    });
  });

  group('La pizarra', () {
    testWidgets('muestra las zonas, la gente y quién ve la plata', (t) async {
      await abrir(t, const PantallaEquipo(), RolMembresia.owner);

      expect(find.text('Administración'), findsOneWidget);
      expect(find.text('Ventas'), findsOneWidget);
      expect(find.text('Carlos Valle'), findsOneWidget);
      expect(find.text('Nico Fredes'), findsOneWidget);
      expect(find.textContaining('ven la plata'), findsOneWidget);
    });

    testWidgets('el dueño puede crear zonas y gente', (t) async {
      await abrir(t, const PantallaEquipo(), RolMembresia.owner);
      expect(find.text('Nueva zona'), findsOneWidget);
      expect(find.text('Nuevo empleado'), findsOneWidget);
    });

    testWidgets('el vendedor la ve pero no la toca', (t) async {
      await abrir(t, const PantallaEquipo(), RolMembresia.vendedor);
      expect(find.text('Carlos Valle'), findsOneWidget);
      expect(find.text('Nueva zona'), findsNothing);
      expect(find.text('Nuevo empleado'), findsNothing);
    });

    testWidgets('en un celular se apila en vez de arrastrarse', (t) async {
      await abrir(
        t,
        const PantallaEquipo(),
        RolMembresia.owner,
        tamano: const Size(390, 1400),
      );
      expect(find.text('Administración'), findsOneWidget);
      expect(find.text('Lucía Sosa'), findsOneWidget);
    });
  });

  group('La ficha de una persona', () {
    const nico = Miembro(
      membresiaId: 'm3',
      usuarioId: 'u3',
      nombre: 'Nico Fredes',
      email: 'nico@agenciademo.com',
      rol: RolMembresia.vendedor,
      activa: true,
      zonaNombre: 'Ventas',
    );

    testWidgets('dice con qué usuario entra y qué ve', (t) async {
      await abrir(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => HojaMiembro.abrir(context, nico),
            child: const Text('abrir'),
          ),
        ),
        RolMembresia.owner,
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();

      expect(find.text('nico@agenciademo.com'), findsOneWidget);
      expect(
        find.text('No ve el precio de compra ni la ganancia'),
        findsOneWidget,
      );
      expect(find.text('Generar clave nueva'), findsOneWidget);
      expect(find.text('Sacarle el acceso'), findsOneWidget);
    });

    testWidgets('a uno mismo no se le ofrecen esos botones', (t) async {
      const yo = Miembro(
        membresiaId: 'm1',
        usuarioId: 'u1',
        nombre: 'Quien Mira',
        email: 'quien@agencia.test',
        rol: RolMembresia.owner,
        activa: true,
      );
      await abrir(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => HojaMiembro.abrir(context, yo),
            child: const Text('abrir'),
          ),
        ),
        RolMembresia.owner,
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();

      expect(find.text('Sacarle el acceso'), findsNothing);
      expect(find.textContaining('Esta es tu cuenta'), findsOneWidget);
    });
  });
}
