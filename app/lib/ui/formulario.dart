import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/tema/colores.dart';
import '../core/tema/tema.dart';
import '../dominio/modelos.dart';
import 'componentes.dart';

/// Piezas compartidas por los formularios de carga.
///
/// Estaban repetidas en cada pantalla. El problema no era el codigo de mas:
/// era que al retocar el estilo de un campo quedaban distintos entre
/// formularios, y eso se nota enseguida.

/// Etiqueta + campo + error o ayuda debajo.
class CampoFormulario extends StatelessWidget {
  const CampoFormulario({
    super.key,
    required this.etiqueta,
    required this.hijo,
    this.error,
    this.ayuda,
  });

  final String etiqueta;
  final Widget hijo;
  final String? error;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: p.tinta2,
          ),
        ),
        const SizedBox(height: Esp.sm),
        hijo,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              error!,
              style: TextStyle(fontSize: 11.5, color: p.critico),
            ),
          )
        else if (ayuda != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              ayuda!,
              style: TextStyle(fontSize: 11.5, color: p.tinta3),
            ),
          ),
      ],
    );
  }
}

/// Campo de fecha con el selector nativo.
class SelectorFecha extends StatelessWidget {
  const SelectorFecha({
    super.key,
    required this.valor,
    required this.onCambio,
    this.hayError = false,
    this.desde,
  });

  final DateTime? valor;
  final ValueChanged<DateTime> onCambio;
  final bool hayError;

  /// Fecha minima elegible. Sirve para no dejar cargar, por ejemplo, un gasto
  /// anterior al ingreso de la unidad.
  final DateTime? desde;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return InkWell(
      onTap: () async {
        final hoy = DateTime.now();
        final elegida = await showDatePicker(
          context: context,
          initialDate: valor ?? hoy,
          firstDate: desde ?? DateTime(2000),
          lastDate: hoy,
          locale: const Locale('es', 'AR'),
        );
        if (elegida != null) onCambio(elegida);
      },
      borderRadius: BorderRadius.circular(Curva.md),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: Esp.md),
        decoration: BoxDecoration(
          color: p.superficieHundida,
          borderRadius: BorderRadius.circular(Curva.md),
          border: Border.all(color: hayError ? p.critico : p.borde),
        ),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 17, color: p.tinta3),
            const SizedBox(width: Esp.md),
            Text(
              valor == null ? 'Elegir fecha' : Fmt.fecha(valor),
              style: TextStyle(
                fontFamily: TemaApp.mono,
                fontSize: 14,
                color: valor == null ? p.tinta3 : p.tinta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desplegable para elegir la unidad a la que se imputa una operacion.
class SelectorVehiculo extends StatelessWidget {
  const SelectorVehiculo({
    super.key,
    required this.titulo,
    required this.vehiculos,
    required this.seleccionado,
    required this.onCambio,
    this.ayuda,
    this.error,
  });

  final String titulo;
  final List<VehiculoInventario> vehiculos;
  final String? seleccionado;
  final ValueChanged<String?> onCambio;
  final String? ayuda;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final ordenados = [...vehiculos]
      ..sort((a, b) => a.codigo.compareTo(b.codigo));

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(titulo: titulo),
          const SizedBox(height: Esp.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Esp.md),
            decoration: BoxDecoration(
              color: p.superficieHundida,
              borderRadius: BorderRadius.circular(Curva.md),
              border: Border.all(color: error != null ? p.critico : p.borde),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: seleccionado,
                isExpanded: true,
                hint: Text(
                  'Elegí la unidad',
                  style: TextStyle(fontSize: 14, color: p.tinta3),
                ),
                dropdownColor: p.superficieElevada,
                borderRadius: BorderRadius.circular(Curva.md),
                padding: const EdgeInsets.symmetric(vertical: Esp.sm),
                items: [
                  for (final v in ordenados)
                    DropdownMenuItem(
                      value: v.id,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 46,
                            child: Text(
                              v.codigo,
                              style: TextStyle(
                                fontFamily: TemaApp.mono,
                                fontSize: 12,
                                color: p.tinta3,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              v.titulo,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: p.tinta),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: onCambio,
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: Esp.xs, left: 2),
              child: Text(
                error!,
                style: TextStyle(fontSize: 11.5, color: p.critico),
              ),
            )
          else if (ayuda != null)
            Padding(
              padding: const EdgeInsets.only(top: Esp.xs, left: 2),
              child: Text(
                ayuda!,
                style: TextStyle(fontSize: 11.5, color: p.tinta3),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cartel de error de guardado, arriba de la botonera.
class AvisoError extends StatelessWidget {
  const AvisoError({super.key, required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.all(Esp.md),
      decoration: BoxDecoration(
        color: p.criticoLavado,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.critico.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: p.critico),
          const SizedBox(width: Esp.sm),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 13, color: p.critico, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cancelar + guardar, con el spinner mientras se guarda.
class BotoneraFormulario extends StatelessWidget {
  const BotoneraFormulario({
    super.key,
    required this.guardando,
    required this.etiquetaGuardar,
    required this.onCancelar,
    required this.onGuardar,
  });

  final bool guardando;
  final String etiquetaGuardar;
  final VoidCallback onCancelar;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: guardando ? null : onCancelar,
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: Esp.md),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: guardando ? null : onGuardar,
              child: guardando
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.acentoTinta,
                      ),
                    )
                  : Text(etiquetaGuardar),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un valor del par "antes → después", para mostrar el efecto de una carga.
class ValorAntesDespues extends StatelessWidget {
  const ValorAntesDespues({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.color,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final Color color;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: TextStyle(fontSize: 11.5, color: p.tinta3)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: destacado ? 22 : 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
