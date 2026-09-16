import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/bcra.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import 'ficha_interesado.dart';
import 'alta_interesado.dart';

/// Filtro de la lista. `null` en [SemaforoCrediticio] significa "todos".
final _filtroProvider = NotifierProvider<_Filtro, SemaforoCrediticio?>(
  _Filtro.new,
);

class _Filtro extends Notifier<SemaforoCrediticio?> {
  @override
  SemaforoCrediticio? build() => null;

  void poner(SemaforoCrediticio? s) => state = s;
}

class PantallaInteresados extends ConsumerWidget {
  const PantallaInteresados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(interesadosProvider);
    final filtro = ref.watch(_filtroProvider);
    final p = context.paleta;
    final margen = MediaQuery.sizeOf(context).width < Corte.tablet
        ? Esp.lg + 4
        : Esp.xxl;

    void nuevo() => Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FormularioInteresado(),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: asincrono.value?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: nuevo,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo interesado'),
            )
          : null,
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No se pudieron cargar los interesados',
          descripcion: '$e',
        ),
        data: (todos) {
          if (todos.isEmpty) {
            return EstadoVacio(
              icono: Icons.people_outline,
              titulo: 'Sin interesados cargados',
              descripcion:
                  'Cuando cargues un interesado vas a poder consultarle la '
                  'situación en el BCRA y guardar su informe.',
              accion: FilledButton.icon(
                onPressed: nuevo,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Nuevo interesado'),
              ),
            );
          }

          final lista = filtro == null
              ? todos
              : todos.where((i) => i.semaforo == filtro).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(interesadosProvider),
            child: ListView(
              padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, 112),
              children: [
                const Aparecer(child: _ExplicacionSemaforo()),
                const SizedBox(height: Esp.lg),
                Aparecer(indice: 1, child: _Filtros(interesados: todos)),
                const SizedBox(height: Esp.md),

                if (lista.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Esp.xxl),
                    child: Center(
                      child: Text(
                        'Ningún interesado está en "${filtro!.etiqueta}".',
                        style: TextStyle(fontSize: 13, color: p.tinta3),
                      ),
                    ),
                  ),

                for (var i = 0; i < lista.length; i++) ...[
                  Aparecer(
                    indice: i + 2,
                    child: _TarjetaInteresado(interesado: lista[i]),
                  ),
                  const SizedBox(height: Esp.sm + 2),
                ],

                if (lista.isNotEmpty) ...[
                  const SizedBox(height: Esp.md),
                  Center(
                    child: Text(
                      '${lista.length} interesado${lista.length == 1 ? '' : 's'}'
                      '${filtro == null ? '' : ' de ${todos.length}'}',
                      style: TextStyle(fontSize: 12, color: p.tinta3),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Filtros por color, con el conteo de cada uno.
///
/// El número al lado del filtro es la respuesta a la pregunta que la agencia
/// se hace de verdad: "¿a cuántos de los que tengo anotados les puedo
/// financiar?". Sin el conteo habría que tocar cada filtro para saberlo.
class _Filtros extends ConsumerWidget {
  const _Filtros({required this.interesados});

  final List<Interesado> interesados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final actual = ref.watch(_filtroProvider);

    int contar(SemaforoCrediticio s) =>
        interesados.where((i) => i.semaforo == s).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChipSeleccion(
            etiqueta: 'Todos (${interesados.length})',
            activo: actual == null,
            onTap: () => ref.read(_filtroProvider.notifier).poner(null),
          ),
          for (final s in SemaforoCrediticio.values) ...[
            const SizedBox(width: Esp.sm),
            ChipSeleccion(
              etiqueta: '${s.etiqueta} (${contar(s)})',
              activo: actual == s,
              color: s == SemaforoCrediticio.sinDatos ? null : s.color(p),
              onTap: () => ref
                  .read(_filtroProvider.notifier)
                  .poner(actual == s ? null : s),
            ),
          ],
        ],
      ),
    );
  }
}

/// Explica qué significa cada color. No es decorativo: el semáforo decide si
/// se le financia una compra a alguien, así que el criterio tiene que estar
/// a la vista y no escondido en la cabeza del que lo programó.
class _ExplicacionSemaforo extends StatelessWidget {
  const _ExplicacionSemaforo();

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      destacada: true,
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.account_balance_rounded,
                tamano: 38,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Semáforo crediticio',
                  descripcion: 'Central de Deudores del BCRA',
                  sobreNegro: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),
          LayoutBuilder(
            builder: (context, restricciones) {
              final porFila = restricciones.maxWidth >= 700 ? 3 : 1;
              final ancho =
                  (restricciones.maxWidth - Esp.sm * (porFila - 1)) / porFila;
              return Wrap(
                spacing: Esp.sm,
                runSpacing: Esp.sm,
                children: [
                  for (final (color, titulo, detalle) in [
                    (
                      p.bien,
                      'Situación normal',
                      'Situación 1, sin alertas informadas',
                    ),
                    (
                      p.observar,
                      'Con reparos',
                      'Situación 2 o 3, cheques pagados o mora',
                    ),
                    (
                      p.critico,
                      'Riesgo alto',
                      'Situación 4 a 6, cheques impagos o juicio',
                    ),
                  ])
                    SizedBox(
                      width: ancho,
                      child: _Criterio(
                        color: color,
                        titulo: titulo,
                        detalle: detalle,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Criterio extends StatelessWidget {
  const _Criterio({
    required this.color,
    required this.titulo,
    required this.detalle,
  });

  final Color color;
  final String titulo, detalle;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.negroElevado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.negroBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: Esp.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.sobreNegro,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 11.5, color: p.sobreNegro2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaInteresado extends StatelessWidget {
  const _TarjetaInteresado({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;
    final c = i.consulta;
    final iniciales = i.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .take(2)
        .map((x) => x[0].toUpperCase())
        .join();

    return Tarjeta(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => FichaInteresado(interesado: i))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i.semaforo.lavado(p),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i.semaforo.color(p).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  iniciales.isEmpty ? '?' : iniciales,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: i.semaforo.color(p),
                  ),
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.tinta,
                      ),
                    ),
                    Text(
                      [
                        if (i.telefono != null) i.telefono!,
                        if (i.cuit != null) formatearCuit(i.cuit!),
                      ].join('  ·  ').ifEmpty('Sin datos de contacto'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 12,
                        color: p.tinta3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Pastilla(
              texto: i.semaforo.etiqueta,
              color: i.semaforo.color(p),
              lavado: i.semaforo.lavado(p),
            ),
          ),

          if (i.vehiculoTitulo != null) ...[
            const SizedBox(height: Esp.md),
            Container(
              padding: const EdgeInsets.fromLTRB(
                Esp.sm,
                Esp.sm,
                Esp.md,
                Esp.sm,
              ),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                children: [
                  IconoEnCirculo(
                    icono: Icons.directions_car_filled_rounded,
                    tamano: 30,
                    color: p.tinta,
                    fondo: p.superficie,
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      '${i.vehiculoCodigo} · ${i.vehiculoTitulo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: p.tinta2,
                      ),
                    ),
                  ),
                  if (i.fecha != null)
                    Text(
                      Fmt.fecha(i.fecha),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 11.5,
                        color: p.tinta3,
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (i.notas != null && i.notas!.isNotEmpty) ...[
            const SizedBox(height: Esp.sm + 2),
            Text(
              i.notas!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ],

          const SizedBox(height: Esp.md),
          Divider(color: p.borde, height: 1),
          const SizedBox(height: Esp.sm + 2),
          Row(
            children: [
              Expanded(child: _Estado(interesado: i)),
              const SizedBox(width: Esp.sm),
              Text(
                c == null ? 'Consultar' : 'Ver ficha',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.acentoTexto,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: p.acentoTexto),
            ],
          ),
        ],
      ),
    );
  }
}

/// La línea que resume en qué punto está la evaluación de esta persona.
class _Estado extends StatelessWidget {
  const _Estado({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;
    final c = i.consulta;

    final (IconData icono, String texto, Color color) = switch (c) {
      null when !i.tieneCuit => (
        Icons.badge_outlined,
        'Falta el CUIT para poder consultar el BCRA',
        p.tinta3,
      ),
      null => (
        Icons.search_rounded,
        'Tiene CUIT cargado, todavía sin consultar',
        p.observar,
      ),
      _ when c.vencida => (
        Icons.update_rounded,
        'Consulta del ${Fmt.fecha(c.consultadoEl)}, conviene actualizarla',
        p.observar,
      ),
      _ when c.sinDeudasInformadas => (
        Icons.verified_outlined,
        'Sin deudas informadas al ${Fmt.fecha(c.consultadoEl)}',
        p.bien,
      ),
      _ => (
        Icons.account_balance_outlined,
        '${c.entidades.length} '
            '${c.entidades.length == 1 ? 'entidad' : 'entidades'}'
            ' · situación ${c.situacionMaxima} · '
            '${Fmt.pesosCompacto(c.totalDeuda)}',
        p.tinta3,
      ),
    };

    return Row(
      children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: Esp.sm),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: color),
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
