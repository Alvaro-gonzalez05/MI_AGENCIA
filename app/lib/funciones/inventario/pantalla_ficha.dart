import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formato.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../dominio/papeles.dart';
import '../../dominio/motor_calculo.dart';
import '../../ui/componentes.dart';
import 'ficha_pdf.dart';
import 'reservar_unidad.dart';

/// Ficha de una unidad: todo lo que se sabe de ella, mas los dos simuladores.
class PantallaFicha extends ConsumerWidget {
  const PantallaFicha({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asincrono = ref.watch(inventarioProvider);

    return asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EstadoVacio(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudo cargar la ficha',
        descripcion: '$e',
      ),
      data: (inv) {
        final v = inv.where((x) => x.id == id).firstOrNull;
        if (v == null) {
          return EstadoVacio(
            icono: Icons.help_outline,
            titulo: 'Unidad no encontrada',
            descripcion: 'El vehículo $id no existe o fue dado de baja.',
            accion: FilledButton(
              onPressed: () => context.go('/inventario'),
              child: const Text('Volver al inventario'),
            ),
          );
        }
        return _Ficha(vehiculo: v, cfg: ref.watch(configProvider));
      },
    );
  }
}

class _Ficha extends StatelessWidget {
  const _Ficha({required this.vehiculo, required this.cfg});

  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho >= Corte.escritorio;
    final margen = ancho < Corte.tablet ? Esp.lg + 4 : Esp.xxl;
    final v = vehiculo;
    const hueco = SizedBox(height: Esp.lg);

    // El orden es el del diseno: primero la unidad y lo que se puede hacer
    // con ella, despues la plata, y al final los datos de archivo.
    final izquierda = <Widget>[
      Aparecer(child: _Cabecera(vehiculo: v)),
      hueco,
      Aparecer(indice: 1, child: _Valuacion(vehiculo: v)),
      hueco,
      Aparecer(indice: 2, child: _Costos(vehiculo: v)),
      hueco,
      Aparecer(
        indice: 3,
        child: _GananciaReal(vehiculo: v, cfg: cfg),
      ),
      hueco,
      Aparecer(indice: 4, child: _GastosUnidad(vehiculo: v)),
    ];

    final derecha = <Widget>[
      Aparecer(
        indice: dosColumnas ? 1 : 5,
        child: _SimuladorPrecio(vehiculo: v, cfg: cfg),
      ),
      hueco,
      Aparecer(
        indice: dosColumnas ? 2 : 6,
        child: _DatosTecnicos(vehiculo: v),
      ),
      hueco,
      Aparecer(
        indice: dosColumnas ? 3 : 7,
        child: _Papeles(vehiculoId: v.id),
      ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(margen, Esp.xs, margen, Esp.xxl),
      children: [
        Row(
          children: [
            BotonCircular(
              icono: Icons.arrow_back_rounded,
              tooltip: 'Volver al inventario',
              onTap: () => context.go('/inventario'),
            ),
            const SizedBox(width: Esp.md),
            Text(
              'Inventario',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.paleta.tinta2,
              ),
            ),
          ],
        ),
        const SizedBox(height: Esp.lg),
        if (dosColumnas)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Column(children: izquierda)),
              const SizedBox(width: Esp.lg),
              Expanded(flex: 2, child: Column(children: derecha)),
            ],
          )
        else
          Column(children: [...izquierda, hueco, ...derecha]),
      ],
    );
  }
}

/// Cabecera negra, como la ficha de un auto en una app de alquiler: el
/// titulo grande, el estado y tres datos clave en mosaicos.
class _Cabecera extends ConsumerWidget {
  const _Cabecera({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final v = vehiculo;
    final angosto = MediaQuery.sizeOf(context).width < Corte.tablet;

    final estado = switch (v.estado) {
      EstadoVehiculo.vendido => ('Vendido', p.neutro, p.neutroLavado),
      EstadoVehiculo.reservado => ('Reservado', p.observar, p.observarLavado),
      EstadoVehiculo.enPreparacion => (
        'En preparación',
        p.tinta2,
        p.superficieHundida,
      ),
      EstadoVehiculo.dadoDeBaja => ('Dado de baja', p.neutro, p.neutroLavado),
      EstadoVehiculo.enStock => ('Disponible para venta', p.bien, p.bienLavado),
    };

    final ficha = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrap y no Row: la patente mas el estado ("Disponible para venta")
        // no entran juntos en una columna angosta.
        Wrap(
          spacing: Esp.md,
          runSpacing: Esp.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (v.patente != null && v.patente!.isNotEmpty) _Placa(v.patente!),
            Pastilla(texto: estado.$1, color: estado.$2, lavado: estado.$3),
          ],
        ),
        const SizedBox(height: Esp.md),
        Text(v.titulo, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: Esp.xs),
        Text(
          [
            'Año ${v.anio}',
            if (v.km != null) Fmt.km(v.km),
            if (v.combustible != null) v.combustible!,
            if (v.transmision != null) v.transmision!,
          ].join('  ·  '),
          style: TextStyle(fontSize: 16, color: p.tinta2),
        ),
        const SizedBox(height: Esp.sm),
        Row(
          children: [
            Icon(Icons.event_rounded, size: 18, color: p.tinta3),
            const SizedBox(width: Esp.sm - 2),
            Flexible(
              child: Text(
                'Ingresó el ${Fmt.fecha(v.fechaIngreso)} · '
                '${Fmt.dias(v.diasEnStock)} en stock',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: v.alerta == AlertaRotacion.normal
                      ? p.tinta3
                      : v.alerta.color(p),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final reserva = ref.watch(reservaDeProvider(v.id)).value;

    final acciones = Wrap(
      spacing: Esp.sm,
      runSpacing: Esp.sm,
      children: [
        if (!v.vendido)
          FilledButton.icon(
            onPressed: () => context.go('/ventas'),
            icon: const Icon(Icons.sell_rounded, size: 22),
            label: const Text('Marcar como vendido'),
          ),
        if (!v.vendido)
          OutlinedButton.icon(
            onPressed: () =>
                HojaReserva.abrir(context, vehiculo: v, reserva: reserva),
            icon: Icon(
              reserva == null
                  ? Icons.bookmark_border_rounded
                  : Icons.bookmark_rounded,
              size: 22,
            ),
            label: Text(reserva == null ? 'Reservar unidad' : 'Ver reserva'),
          ),
        OutlinedButton.icon(
          onPressed: () => FichaPdf.imprimir(context, ref, v),
          icon: const Icon(Icons.print_outlined, size: 22),
          label: const Text('Imprimir ficha'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/gastos'),
          icon: const Icon(Icons.receipt_long_outlined, size: 22),
          label: const Text('Cargar un gasto'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/precios'),
          icon: const Icon(Icons.sell_outlined, size: 22),
          label: const Text('Cambiar precio'),
        ),
      ],
    );

    return Tarjeta(
      padding: EdgeInsets.all(angosto ? Esp.lg : Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reserva != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: reserva.vencida ? p.criticoLavado : p.observarLavado,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: 22,
                    color: reserva.vencida ? p.critico : p.observar,
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      'Reservada por ${reserva.clienteNombre} · '
                      '${reserva.cuandoVence.toLowerCase()}'
                      '${reserva.senia > 0 ? ' · seña ${Fmt.pesos(reserva.senia)}' : ''}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: reserva.vencida ? p.critico : p.tinta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Esp.lg),
          ],
          if (angosto) ...[
            _FotoGrande(vehiculo: v, alto: 180),
            const SizedBox(height: Esp.lg),
            ficha,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FotoGrande(vehiculo: v, alto: 190, ancho: 280),
                const SizedBox(width: Esp.xl),
                Expanded(child: ficha),
              ],
            ),
          const SizedBox(height: Esp.lg),
          Divider(color: p.borde, height: 1.5, thickness: 1.5),
          const SizedBox(height: Esp.lg),
          acciones,
          if (v.observaciones != null && v.observaciones!.isNotEmpty) ...[
            const SizedBox(height: Esp.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Esp.md),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OBSERVACIONES',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: Esp.xs),
                  Text(
                    v.observaciones!,
                    style: TextStyle(fontSize: 15, color: p.tinta, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// La galería de la unidad: la portada grande y las demás abajo.
///
/// Mientras no haya fotos, el hueco dice qué falta y ofrece cargarlas: en
/// una agencia el auto entra antes que las fotos, y la ficha tiene que
/// servir igual.
class _FotoGrande extends ConsumerWidget {
  const _FotoGrande({required this.vehiculo, required this.alto, this.ancho});

  final VehiculoInventario vehiculo;
  final double alto;
  final double? ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final fotos = ref.watch(fotosProvider(vehiculo.id)).value ?? const [];

    if (fotos.isEmpty) {
      return SizedBox(
        width: ancho ?? double.infinity,
        height: alto,
        child: BordePunteado(
          radio: Curva.lg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 32,
                color: vehiculo.alerta.color(p),
              ),
              const SizedBox(height: Esp.sm),
              Text(
                'Sin fotos cargadas',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.tinta2,
                ),
              ),
              const SizedBox(height: Esp.xs),
              TextButton.icon(
                onPressed: () => context.go('/vehiculos'),
                icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                label: const Text('Cargar fotos'),
              ),
            ],
          ),
        ),
      );
    }

    final portada = fotos.firstWhere(
      (f) => f.esPortada,
      orElse: () => fotos.first,
    );

    return SizedBox(
      width: ancho ?? double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _verGrande(context, fotos, portada),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Curva.lg),
              child: Image.network(
                portada.url,
                width: ancho ?? double.infinity,
                height: alto,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: ancho ?? double.infinity,
                  height: alto,
                  color: p.superficieHundida,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: p.tinta3,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
          if (fotos.length > 1) ...[
            const SizedBox(height: Esp.sm),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fotos.length,
                separatorBuilder: (_, _) => const SizedBox(width: Esp.sm - 2),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _verGrande(context, fotos, fotos[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Curva.sm),
                    child: Image.network(
                      fotos[i].url,
                      width: 76,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Container(width: 76, color: p.superficieHundida),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// La foto a pantalla completa, que es como se le muestra al cliente.
  void _verGrande(
    BuildContext context,
    List<FotoVehiculo> fotos,
    FotoVehiculo inicial,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(Esp.lg),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Curva.lg),
                child: Image.network(inicial.url, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}

/// La patente, como la chapa.
class _Placa extends StatelessWidget {
  const _Placa(this.patente);
  final String patente;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.md, vertical: 4),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.sm),
        border: Border.all(color: p.tinta, width: 2),
      ),
      child: Text(
        patente.toUpperCase(),
        style: TextStyle(
          fontFamily: TemaApp.titulo,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: p.tinta,
        ),
      ),
    );
  }
}

/// Valuación comercial: lo que dice la revista contra lo que se pide.
class _Valuacion extends StatelessWidget {
  const _Valuacion({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final revista = v.revistaArs;
    final diferencia = revista == null ? null : v.precioActual - revista;
    final porcentaje = (revista == null || revista <= 0)
        ? null
        : v.precioActual / revista - 1;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Valuación comercial y precio',
            descripcion: 'El valor de referencia contra lo que pedís',
          ),
          const SizedBox(height: Esp.lg),
          LayoutBuilder(
            builder: (context, r) {
              final enFila = r.maxWidth >= 620;
              final tarjetas = [
                _Valor(
                  etiqueta: 'VALOR DE MERCADO',
                  valor: revista == null ? '—' : Fmt.pesos(revista),
                  nota: revista == null
                      ? 'Todavía no hay valor de revista para esta versión'
                      : 'Guía de referencia',
                  destacado: true,
                ),
                _Valor(
                  etiqueta: 'PRECIO DE VENTA AL PÚBLICO',
                  valor: Fmt.pesos(v.precioActual),
                  nota: 'Publicado en el salón',
                ),
                _Valor(
                  etiqueta: 'DIFERENCIAL',
                  valor: diferencia == null
                      ? '—'
                      : '${diferencia >= 0 ? '+ ' : '- '}'
                            '${Fmt.pesos(diferencia.abs())}',
                  nota: porcentaje == null
                      ? 'Se calcula cuando haya valor de revista'
                      : '${Fmt.porcentaje(porcentaje.abs())} '
                            '${porcentaje >= 0 ? 'por encima' : 'por debajo'} de la revista',
                  color: diferencia == null
                      ? null
                      : (diferencia >= 0 ? p.bien : p.critico),
                ),
              ];
              // IntrinsicHeight: sin el, `stretch` no sabe hasta donde
              // estirar (la altura de una fila adentro de una columna es
              // libre) y Flutter tira "hasSize".
              return enFila
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tarjetas.length; i++) ...[
                            if (i > 0) const SizedBox(width: Esp.sm),
                            Expanded(child: tarjetas[i]),
                          ],
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < tarjetas.length; i++) ...[
                          if (i > 0) const SizedBox(height: Esp.sm),
                          tarjetas[i],
                        ],
                      ],
                    );
            },
          ),
          if (revista == null) ...[
            const SizedBox(height: Esp.md),
            _Aviso(
              texto:
                  'El valor de revista se completa con la guía de precios. '
                  'Todavía no está conectada: mientras tanto, el precio lo '
                  'decidís vos con el simulador de acá al lado.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({
    required this.etiqueta,
    required this.valor,
    required this.nota,
    this.destacado = false,
    this.color,
  });

  final String etiqueta, valor, nota;
  final bool destacado;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md + 2),
      decoration: BoxDecoration(
        color: destacado ? p.acento : p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: destacado ? p.acento : p.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: destacado ? p.acentoTinta : p.tinta3,
            ),
          ),
          const SizedBox(height: Esp.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontFamily: TemaApp.titulo,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: destacado ? p.acentoTinta : (color ?? p.tinta),
              ),
            ),
          ),
          const SizedBox(height: Esp.xs),
          Text(
            nota,
            style: TextStyle(
              fontSize: 14,
              color: destacado
                  ? p.acentoTinta.withValues(alpha: 0.8)
                  : p.tinta3,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renglón de aviso, para lo que todavía no está conectado.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.superficieHundida,
        borderRadius: BorderRadius.circular(Curva.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: p.tinta3),
          const SizedBox(width: Esp.sm),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 14, color: p.tinta2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ficha técnica: lo que se carga en el alta.
class _DatosTecnicos extends StatelessWidget {
  const _DatosTecnicos({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final v = vehiculo;
    final datos = <(String, String?)>[
      ('Marca', v.marca),
      ('Modelo', v.modelo),
      ('Versión', v.version),
      ('Año', '${v.anio}'),
      ('Kilómetros', v.km == null ? null : Fmt.km(v.km)),
      ('Combustible', v.combustible),
      ('Transmisión', v.transmision),
      ('Color', v.color),
      ('Patente', v.patente),
      ('Código interno', v.codigo),
      ('Motor', v.nroMotor),
      ('Chasis', v.nroChasis),
    ];

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Datos técnicos',
            descripcion: 'Lo que dice la ficha de la unidad',
          ),
          const SizedBox(height: Esp.md),
          for (final (etiqueta, valor) in datos)
            if (valor != null && valor.isNotEmpty)
              FilaDato(etiqueta: etiqueta, valor: valor),
          if (datos.where((d) => d.$2 == null || d.$2!.isEmpty).isNotEmpty) ...[
            const SizedBox(height: Esp.sm),
            _Aviso(
              texto:
                  'Faltan datos de la ficha técnica. Se completan editando la '
                  'unidad desde Vehículos.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Papeles y documentación: el estado legal de la unidad.
///
/// Es lo que traba una entrega. Si falta algo se ve en rojo, porque el que
/// mira la ficha antes de cerrar una venta necesita enterarse ahí y no el
/// día de la transferencia.
class _Papeles extends ConsumerWidget {
  const _Papeles({required this.vehiculoId});

  final String vehiculoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final asincrono = ref.watch(papelesProvider(vehiculoId));
    final papeles = asincrono.value;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Papeles y documentación',
                  descripcion: papeles == null
                      ? 'Estado legal y libre deuda'
                      : '${papeles.completos} de ${PapelesVehiculo.total} '
                            'puntos resueltos',
                ),
              ),
              if (papeles != null)
                Pastilla(
                  texto: papeles.completo ? 'Completos' : 'Falta cargar',
                  color: papeles.completo ? p.bien : p.observar,
                  lavado: papeles.completo ? p.bienLavado : p.observarLavado,
                ),
            ],
          ),
          const SizedBox(height: Esp.md),
          if (asincrono.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Esp.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (papeles != null) ...[
            _Punto(
              titulo: 'Título del automotor',
              listo: papeles.titulo,
              detalle: papeles.titulo ? 'Presentado' : 'Sin cargar',
            ),
            _Punto(
              titulo: 'Cédula de identificación',
              listo: papeles.cedula,
              detalle: papeles.cedula ? 'Presentada' : 'Sin cargar',
            ),
            _Punto(
              titulo: 'Verificación técnica (VTV)',
              listo: papeles.vtv && !papeles.vtvVencida,
              alerta: papeles.vtvVencida,
              detalle: !papeles.vtv
                  ? 'Sin cargar'
                  : papeles.vtvVence == null
                  ? 'Sin vencimiento anotado'
                  : papeles.vtvVencida
                  ? 'Vencida el ${Fmt.fecha(papeles.vtvVence)}'
                  : 'Vigente hasta ${Fmt.fecha(papeles.vtvVence)}',
            ),
            _Punto(
              titulo: 'Informe de dominio',
              listo: papeles.informeDominio,
              detalle: papeles.informeDominio ? 'Verificado' : 'Sin cargar',
            ),
            _Punto(
              titulo: 'Deuda de patentes',
              listo: papeles.patentesDeuda == 0,
              alerta: (papeles.patentesDeuda ?? 0) > 0,
              detalle: papeles.patentesDeuda == null
                  ? 'Sin revisar'
                  : papeles.patentesDeuda == 0
                  ? 'Libre de deuda'
                  : Fmt.pesos(papeles.patentesDeuda),
            ),
            _Punto(
              titulo: 'Multas e infracciones',
              listo: papeles.multasMonto == 0 && papeles.multasCantidad == 0,
              alerta: papeles.multasCantidad > 0,
              detalle: papeles.multasMonto == null
                  ? 'Sin revisar'
                  : papeles.multasCantidad == 0
                  ? 'Sin multas'
                  : '${papeles.multasCantidad} · '
                        '${Fmt.pesos(papeles.multasMonto)}',
            ),
            if (papeles.pendientes.isNotEmpty) ...[
              const SizedBox(height: Esp.sm),
              _Aviso(
                texto:
                    'Antes de entregar: ${papeles.pendientes.join(', ').toLowerCase()}.',
              ),
            ],
          ],
          const SizedBox(height: Esp.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/vehiculos'),
              icon: const Icon(Icons.edit_outlined, size: 20),
              label: const Text('Actualizar papeles'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un punto de la lista de papeles.
class _Punto extends StatelessWidget {
  const _Punto({
    required this.titulo,
    required this.listo,
    required this.detalle,
    this.alerta = false,
  });

  final String titulo, detalle;
  final bool listo, alerta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final color = alerta
        ? p.critico
        : listo
        ? p.bien
        : p.tinta3;
    return Padding(
      padding: const EdgeInsets.only(bottom: Esp.sm),
      child: Row(
        children: [
          Icon(
            alerta
                ? Icons.error_outline_rounded
                : listo
                ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: Esp.sm),
          Expanded(
            child: Text(titulo, style: TextStyle(fontSize: 15, color: p.tinta)),
          ),
          const SizedBox(width: Esp.sm),
          Flexible(
            child: Text(
              detalle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: alerta ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Los gastos de esta unidad, uno por uno, como en el diseño.
class _GastosUnidad extends ConsumerWidget {
  const _GastosUnidad({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.paleta;
    final v = vehiculo;
    final gastos =
        (ref.watch(gastosProvider).value ?? const [])
            .where((g) => g.vehiculoId == v.id)
            .toList()
          ..sort((a, b) => b.fecha.compareTo(a.fecha));

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CabeceraBloque(
                  titulo: 'Gastos de la unidad',
                  descripcion: gastos.isEmpty
                      ? 'Todavía no se cargó ninguno'
                      : '${gastos.length} ${gastos.length == 1 ? 'comprobante' : 'comprobantes'} imputados',
                ),
              ),
              const SizedBox(width: Esp.sm),
              OutlinedButton.icon(
                onPressed: () => context.go('/gastos'),
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: Esp.md),
          if (gastos.isEmpty)
            const _Aviso(
              texto:
                  'Cada gasto que cargues acá se descuenta de la ganancia y '
                  'se ajusta por el dólar del día en que se hizo.',
            )
          else ...[
            for (final g in gastos)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        Fmt.fecha(g.fecha),
                        style: TextStyle(
                          fontFamily: TemaApp.mono,
                          fontSize: 14,
                          color: p.tinta3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.descripcion?.isNotEmpty == true
                                ? g.descripcion!
                                : g.categoria.etiqueta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: p.tinta,
                            ),
                          ),
                          if (g.proveedor != null && g.proveedor!.isNotEmpty)
                            Text(
                              g.proveedor!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: p.tinta3),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Esp.sm),
                    Text(
                      Fmt.pesos(g.importe),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.tinta,
                      ),
                    ),
                  ],
                ),
              ),
            Divider(color: p.borde, height: Esp.lg),
            FilaDato(
              etiqueta: 'Total de gastos',
              valor: Fmt.pesos(v.gastosAcum),
              destacado: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Costos extends StatelessWidget {
  const _Costos({required this.vehiculo});
  final VehiculoInventario vehiculo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(
            titulo: 'Capital y costos',
            descripcion: 'Todo lo invertido en la unidad',
          ),
          const SizedBox(height: Esp.md),
          FilaDato(
            etiqueta: 'Precio de compra',
            valor: Fmt.pesos(v.precioCompra),
          ),
          FilaDato(
            etiqueta: 'Gastos acumulados (${v.cantidadGastos})',
            valor: Fmt.pesos(v.gastosAcum),
          ),
          _Resaltado(
            child: FilaDato(
              etiqueta: 'Costo total',
              valor: Fmt.pesos(v.costoTotal),
              destacado: true,
            ),
          ),
          FilaDato(
            etiqueta: 'Costo a valor de hoy (USD)',
            valor: Fmt.pesos(v.costoTotalHoy),
            valorColor: p.observar,
          ),
          Divider(color: p.borde, height: Esp.lg),
          FilaDato(
            etiqueta: 'Ganancia estimada',
            valor: Fmt.pesos(v.gananciaEstimada),
            valorColor: v.gananciaEstimada < 0 ? p.critico : p.bien,
            destacado: true,
          ),
          FilaDato(
            etiqueta: 'Capital inmovilizado',
            valor: Fmt.pesos(v.capitalInmovilizado),
          ),
          FilaDato(
            etiqueta: 'Costo por día parado',
            valor: Fmt.pesos(
              v.diasEnStock > 0 ? v.costoTotal / v.diasEnStock : v.costoTotal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fondo hundido para la fila que resume un bloque.
class _Resaltado extends StatelessWidget {
  const _Resaltado({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: Esp.xs),
    padding: const EdgeInsets.symmetric(horizontal: Esp.md),
    decoration: BoxDecoration(
      color: context.paleta.superficieHundida,
      borderRadius: BorderRadius.circular(Curva.sm + 2),
    ),
    child: child,
  );
}

class _GananciaReal extends StatelessWidget {
  const _GananciaReal({required this.vehiculo, required this.cfg});
  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = vehiculo;
    final enRojo = v.gananciaRealIpc < 0;
    final color = enRojo ? p.critico : p.bien;
    final precio = v.vendido ? (v.precioFinal ?? 0) : v.precioActual;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: enRojo
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                tamano: 38,
                color: color,
                fondo: color.withValues(alpha: 0.14),
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Ganancia real (USD)',
                  descripcion: 'Ajustada por el dólar oficial desde la compra',
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MontoDual(
                  pesos: v.gananciaRealIpc,
                  tipoCambio: cfg.tipoCambio,
                  tamano: 24,
                  color: color,
                ),
              ),
              const SizedBox(width: Esp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Margen real (USD)',
                      style: TextStyle(fontSize: 13, color: p.tinta3),
                    ),
                    Text(
                      // Vendida: contra lo que se cobró, no contra el
                      // último precio publicado.
                      Fmt.porcentaje(
                        precio > 0 ? v.gananciaRealIpc / precio : 0,
                      ),
                      style: TextStyle(
                        fontFamily: TemaApp.mono,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg),
          Text(
            enRojo
                ? 'Medida en dólares, esta unidad pierde plata: lo invertido, '
                      'llevado al dólar oficial de cada fecha, vale hoy más que '
                      'su precio.'
                : 'Lo invertido se pasa a dólares al oficial del día de la compra '
                      'y de cada gasto, y se trae al dólar de hoy (o al del día '
                      'de la venta).',
            style: TextStyle(fontSize: 13, color: p.tinta2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Numero grande que anima entre valores al mover un slider.
class _CifraAnimada extends StatelessWidget {
  const _CifraAnimada({
    required this.valor,
    required this.formato,
    required this.estilo,
  });

  final double valor;
  final String Function(double) formato;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: valor),
    duration: Duracion.media,
    curve: Curves.easeOutCubic,
    builder: (_, x, _) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(formato(x), style: estilo),
    ),
  );
}

/// Simulador de precio. Vive en Dart, no en SQL, porque recalcula a cada
/// movimiento del slider y es un "que pasaria si" que no se persiste.
class _SimuladorPrecio extends StatefulWidget {
  const _SimuladorPrecio({required this.vehiculo, required this.cfg});
  final VehiculoInventario vehiculo;
  final ConfigAgencia cfg;

  @override
  State<_SimuladorPrecio> createState() => _SimuladorPrecioState();
}

class _SimuladorPrecioState extends State<_SimuladorPrecio> {
  late double _margen = widget.cfg.margenObjetivo;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final v = widget.vehiculo;

    final exacto = Motor.precioParaMargen(v.costoTotal, _margen);
    final sugerido = Motor.redondearArriba(exacto, widget.cfg.redondeo);
    final diferencia = sugerido - v.precioActual;
    final ajuste = v.precioActual > 0 ? sugerido / v.precioActual - 1 : 0.0;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconoEnCirculo(
                icono: Icons.tune_rounded,
                tamano: 38,
                color: p.acentoTinta,
                fondo: p.acento,
              ),
              const SizedBox(width: Esp.md),
              const Expanded(
                child: CabeceraBloque(
                  titulo: 'Simulador de precio',
                  descripcion: 'Elegí el margen y te da el precio',
                ),
              ),
            ],
          ),
          const SizedBox(height: Esp.lg + 2),

          // Resultado en una pildora amarilla: es lo que se viene a buscar.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Esp.lg + 2),
            decoration: BoxDecoration(
              color: p.acento,
              borderRadius: BorderRadius.circular(Curva.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Precio a publicar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p.acentoTinta.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                _CifraAnimada(
                  valor: sugerido,
                  formato: Fmt.pesos,
                  estilo: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: p.acentoTinta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Esp.lg),
          Row(
            children: [
              Text(
                'Margen deseado',
                style: TextStyle(fontSize: 14, color: p.tinta2),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Esp.md,
                  vertical: 4,
                ),
                decoration: ShapeDecoration(
                  color: p.negro,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  Fmt.porcentaje(_margen, decimales: 0),
                  style: TextStyle(
                    fontFamily: TemaApp.mono,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.acento,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _margen,
            min: 0,
            max: 0.60,
            divisions: 60,
            onChanged: (x) => setState(() => _margen = x),
          ),
          FilaDato(etiqueta: 'Precio exacto', valor: Fmt.pesos(exacto)),
          FilaDato(
            etiqueta: 'Diferencia vs. actual',
            valor: '${diferencia >= 0 ? '+' : ''}${Fmt.pesos(diferencia)}',
            valorColor: diferencia > 0 ? p.bien : p.critico,
          ),
          FilaDato(
            etiqueta: 'Ajuste necesario',
            valor: Fmt.porcentajeConSigno(ajuste),
            valorColor: ajuste.abs() < 0.02 ? p.tinta2 : p.observar,
          ),
          const SizedBox(height: Esp.sm),
          AnimatedSwitcher(
            duration: Duracion.media,
            child: Container(
              key: ValueKey(
                ajuste.abs() < 0.02
                    ? 0
                    : ajuste > 0
                    ? 1
                    : -1,
              ),
              width: double.infinity,
              padding: const EdgeInsets.all(Esp.md + 2),
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 17,
                    color: p.tinta2,
                  ),
                  const SizedBox(width: Esp.sm),
                  Expanded(
                    child: Text(
                      ajuste.abs() < 0.02
                          ? 'El precio actual ya está alineado con ese margen.'
                          : ajuste > 0
                          ? 'Habría que subir el precio '
                                '${Fmt.porcentaje(ajuste)} para alcanzar ese '
                                'margen.'
                          : 'Se puede bajar el precio '
                                '${Fmt.porcentaje(ajuste.abs())} y todavía '
                                'alcanzar ese margen.',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.tinta2,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
