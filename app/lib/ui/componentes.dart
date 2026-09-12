import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/tema/colores.dart';
import '../core/tema/tema.dart';

/// Pastilla de estado. Es el componente mas repetido de la app: aparece en
/// cada fila del inventario, en cada ficha y en cada interesado.
class Pastilla extends StatelessWidget {
  const Pastilla({
    super.key,
    required this.texto,
    required this.color,
    required this.lavado,
    this.conPunto = true,
  });

  final String texto;
  final Color color;
  final Color lavado;
  final bool conPunto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Esp.sm + 2, vertical: 4),
      decoration: BoxDecoration(
        color: lavado,
        borderRadius: BorderRadius.circular(Curva.completo),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (conPunto) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Esp.sm - 2),
          ],
          Text(
            texto,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta base. Todo panel de la app sale de aca, para que el radio, el
/// borde y el relleno sean identicos en todas las pantallas.
class Tarjeta extends StatelessWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Esp.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final contenido = Padding(padding: padding, child: child);

    return Material(
      color: p.superficie,
      borderRadius: BorderRadius.circular(Curva.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Curva.lg),
        hoverColor: p.superficieHover,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Curva.lg),
            border: Border.all(color: p.borde),
          ),
          child: contenido,
        ),
      ),
    );
  }
}

/// Etiqueta de seccion: chica, con tracking, en el color mas tenue.
class EtiquetaSeccion extends StatelessWidget {
  const EtiquetaSeccion(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      );
}

/// Tarjeta de metrica del dashboard: un numero grande y su contexto.
///
/// El numero va en mono y en tamano grande porque es lo unico que el usuario
/// realmente viene a leer; todo lo demas es andamiaje.
class TarjetaMetrica extends StatelessWidget {
  const TarjetaMetrica({
    super.key,
    required this.titulo,
    required this.valor,
    this.detalle,
    this.detalleColor,
    this.icono,
    this.onTap,
  });

  final String titulo;
  final String valor;
  final String? detalle;
  final Color? detalleColor;
  final IconData? icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Tarjeta(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: EtiquetaSeccion(titulo)),
              if (icono != null) Icon(icono, size: 16, color: p.tinta3),
            ],
          ),
          const SizedBox(height: Esp.md),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: p.tinta,
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: Esp.xs),
            Text(
              detalle!,
              maxLines: 2,
              style: TextStyle(fontSize: 12.5, color: detalleColor ?? p.tinta3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor, para fichas y paneles de detalle.
class FilaDato extends StatelessWidget {
  const FilaDato({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.valorColor,
    this.destacado = false,
    this.mono = true,
  });

  final String etiqueta;
  final String valor;
  final Color? valorColor;
  final bool destacado;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Esp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 13, color: p.tinta2),
            ),
          ),
          const SizedBox(width: Esp.md),
          Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: mono ? TemaApp.mono : null,
              fontSize: destacado ? 15 : 13.5,
              fontWeight: destacado ? FontWeight.w600 : FontWeight.w500,
              color: valorColor ?? p.tinta,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de progreso fina, para "X de Y unidades" y ocupacion del predio.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({
    super.key,
    required this.valor,
    this.color,
    this.alto = 6,
  });

  final double valor;
  final Color? color;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Curva.completo),
      child: LinearProgressIndicator(
        value: valor.clamp(0, 1),
        minHeight: alto,
        backgroundColor: p.superficieHundida,
        valueColor: AlwaysStoppedAnimation(color ?? p.acento),
      ),
    );
  }
}

/// Estado vacio. Existe como componente propio porque una app de gestion pasa
/// mucho tiempo sin datos (agencia recien dada de alta, filtro sin resultados)
/// y esas pantallas son las que definen si se siente terminada o a medio hacer.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String? descripcion;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: p.superficieHundida,
                borderRadius: BorderRadius.circular(Curva.lg),
                border: Border.all(color: p.borde),
              ),
              child: Icon(icono, color: p.tinta3, size: 24),
            ),
            const SizedBox(height: Esp.lg),
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            if (descripcion != null) ...[
              const SizedBox(height: Esp.sm),
              Text(
                descripcion!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: p.tinta3, height: 1.5),
              ),
            ],
            if (accion != null) ...[const SizedBox(height: Esp.xl), accion!],
          ],
        ),
      ),
    );
  }
}

/// Cartel de modo demo. Deliberadamente visible: nadie tiene que confundir
/// datos de ejemplo con datos reales de la agencia.
class CintaDemo extends StatelessWidget {
  const CintaDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Esp.lg, vertical: Esp.sm),
      color: p.observarLavado,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined, size: 14, color: p.observar),
          const SizedBox(width: Esp.sm),
          Flexible(
            child: Text(
              'Modo demo — datos de ejemplo, sin conexión a la base',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: p.observar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra un monto en pesos y, debajo, su equivalente en dolares.
class MontoDual extends StatelessWidget {
  const MontoDual({
    super.key,
    required this.pesos,
    required this.tipoCambio,
    this.tamano = 20,
    this.color,
  });

  final double pesos;
  final double tipoCambio;
  final double tamano;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Fmt.pesos(pesos),
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: tamano,
            fontWeight: FontWeight.w600,
            color: color ?? p.tinta,
          ),
        ),
        Text(
          Fmt.dolares(tipoCambio > 0 ? pesos / tipoCambio : 0),
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 12,
            color: p.tinta3,
          ),
        ),
      ],
    );
  }
}
