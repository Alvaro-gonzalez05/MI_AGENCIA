import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';

class PantallaInteresados extends ConsumerWidget {
  const PantallaInteresados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(interesadosProvider);
    final p = context.paleta;

    return asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudieron cargar los interesados',
        descripcion: '$e',
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const EstadoVacio(
            icono: Icons.people_outline,
            titulo: 'Sin interesados cargados',
            descripcion:
                'Cuando cargues un interesado vas a poder consultarle la '
                'situación en el BCRA y ver si conviene financiarle la compra.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(Esp.xl),
          children: [
            _ExplicacionSemaforo(),
            const SizedBox(height: Esp.lg),
            for (final i in lista) ...[
              _TarjetaInteresado(interesado: i),
              const SizedBox(height: Esp.sm),
            ],
            const SizedBox(height: Esp.lg),
            Center(
              child: Text(
                '${lista.length} interesado${lista.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: p.tinta3),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Explica qué significa cada color. No es decorativo: el semáforo decide si
/// se le financia una compra a alguien, así que el criterio tiene que estar
/// a la vista y no escondido en la cabeza del que lo programó.
class _ExplicacionSemaforo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined, size: 15, color: p.tinta3),
              const SizedBox(width: Esp.sm),
              const EtiquetaSeccion('Semáforo crediticio — BCRA'),
            ],
          ),
          const SizedBox(height: Esp.md),
          Wrap(
            spacing: Esp.xl,
            runSpacing: Esp.sm,
            children: [
              _Criterio(
                color: p.bien,
                titulo: 'Apto',
                detalle: 'Situación 1 o 2, sin cheques rechazados',
              ),
              _Criterio(
                color: p.observar,
                titulo: 'Con reparos',
                detalle: 'Situación 3, o más de 30 días de atraso',
              ),
              _Criterio(
                color: p.critico,
                titulo: 'Riesgo alto',
                detalle: 'Situación 4 a 6, cheques impagos o juicio',
              ),
            ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Esp.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.tinta,
              ),
            ),
            Text(detalle, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
          ],
        ),
      ],
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
    final sinConsultar = i.semaforo == SemaforoCrediticio.sinDatos;

    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: i.semaforo.lavado(p),
                  borderRadius: BorderRadius.circular(Curva.md),
                  border: Border.all(
                    color: i.semaforo.color(p).withValues(alpha: 0.35),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: i.semaforo.color(p),
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.nombre,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: p.tinta,
                      ),
                    ),
                    if (i.telefono != null)
                      Text(
                        i.telefono!,
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 12,
                          color: p.tinta3,
                        ),
                      ),
                  ],
                ),
              ),
              Pastilla(
                texto: i.semaforo.etiqueta,
                color: i.semaforo.color(p),
                lavado: i.semaforo.lavado(p),
              ),
            ],
          ),
          if (i.vehiculoTitulo != null) ...[
            const SizedBox(height: Esp.md),
            Row(
              children: [
                Icon(Icons.directions_car_outlined, size: 14, color: p.tinta3),
                const SizedBox(width: Esp.sm - 2),
                Text(
                  '${i.vehiculoCodigo} · ${i.vehiculoTitulo}',
                  style: TextStyle(fontSize: 12.5, color: p.tinta2),
                ),
                const Spacer(),
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
          ],
          if (i.notas != null && i.notas!.isNotEmpty) ...[
            const SizedBox(height: Esp.sm),
            Text(
              i.notas!,
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ],
          if (sinConsultar) ...[
            const SizedBox(height: Esp.md),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sin CUIT cargado no se puede consultar el BCRA.',
                    style: TextStyle(fontSize: 12, color: p.tinta3),
                  ),
                ),
                OutlinedButton.icon(
                  // PENDIENTE: abre el formulario de CUIT y llama a la Edge
                  // Function de BCRA. La UI ya está; falta el backend.
                  onPressed: null,
                  icon: const Icon(Icons.search, size: 15),
                  label: const Text('Consultar BCRA'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
