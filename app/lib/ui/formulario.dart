import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        // La etiqueta va SIEMPRE arriba del campo y en 16 px: el diseño
        // prohíbe las etiquetas flotantes y los campos que solo se explican
        // con el placeholder, que desaparece apenas se empieza a escribir.
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: p.tinta,
          ),
        ),
        const SizedBox(height: Esp.sm),
        hijo,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              error!,
              style: TextStyle(fontSize: 14, color: p.critico),
            ),
          )
        else if (ayuda != null)
          Padding(
            padding: const EdgeInsets.only(top: Esp.xs, left: 2),
            child: Text(
              ayuda!,
              style: TextStyle(fontSize: 14, color: p.tinta2),
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
    this.hasta,
  });

  final DateTime? valor;
  final ValueChanged<DateTime> onCambio;
  final bool hayError;

  /// Fecha minima elegible. Sirve para no dejar cargar, por ejemplo, un gasto
  /// anterior al ingreso de la unidad.
  final DateTime? desde;

  /// Fecha maxima. Por defecto es hoy, porque casi todo lo que se carga en la
  /// app ya paso; la vigencia de una agencia es la excepcion y mira al futuro.
  final DateTime? hasta;

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
          lastDate: hasta ?? hoy,
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
                                fontSize: 13,
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
                style: TextStyle(fontSize: 13, color: p.critico),
              ),
            )
          else if (ayuda != null)
            Padding(
              padding: const EdgeInsets.only(top: Esp.xs, left: 2),
              child: Text(
                ayuda!,
                style: TextStyle(fontSize: 13, color: p.tinta3),
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
              style: TextStyle(fontSize: 14, color: p.critico, height: 1.4),
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
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: guardando
                    ? SizedBox(
                        key: const ValueKey('guardando'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.acentoTinta,
                        ),
                      )
                    : Text(etiquetaGuardar, key: const ValueKey('guardar')),
              ),
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
        Text(etiqueta, style: TextStyle(fontSize: 13, color: p.tinta3)),
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

// ---------------------------------------------------------------------------
// Campos listos para usar
//
// Antes cada formulario se armaba sus propios helpers privados (_texto,
// _numero, _fecha...). Con el diseño nuevo son cuatro pantallas las que
// cargan datos, así que los campos viven acá: mismo alto, misma etiqueta
// arriba, mismo lugar para el error.
// ---------------------------------------------------------------------------

/// Un bloque de campos con su título, como los del alta.
class BloqueFormulario extends StatelessWidget {
  const BloqueFormulario({
    super.key,
    required this.titulo,
    required this.hijos,
    this.descripcion,
  });

  final String titulo;
  final String? descripcion;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Tarjeta(
    padding: const EdgeInsets.all(Esp.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CabeceraBloque(titulo: titulo, descripcion: descripcion ?? ''),
        const SizedBox(height: Esp.lg),
        for (var i = 0; i < hijos.length; i++) ...[
          if (i > 0) const SizedBox(height: Esp.md),
          hijos[i],
        ],
      ],
    ),
  );
}

/// Dos campos al lado del otro en escritorio, uno abajo del otro en teléfono.
class FilaCampos extends StatelessWidget {
  const FilaCampos({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, r) {
      if (r.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: Esp.md),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: Esp.md),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

/// Campo de texto.
class CampoTexto extends StatefulWidget {
  const CampoTexto({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.ayuda,
    this.error,
    this.obligatorio = false,
    this.mayusculas = false,
    this.capitalizar = false,
    this.lineas = 1,
  });

  final String etiqueta, valor;
  final ValueChanged<String> onCambio;
  final String? ayuda, error;
  final bool obligatorio, mayusculas, capitalizar;
  final int lineas;

  @override
  State<CampoTexto> createState() => _CampoTextoState();
}

class _CampoTextoState extends State<CampoTexto> {
  late final _c = TextEditingController(text: widget.valor);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampoTexto anterior) {
    super.didUpdateWidget(anterior);
    // Solo si cambió desde afuera: pisar el texto mientras se escribe mueve
    // el cursor al principio.
    if (widget.valor != _c.text && widget.valor != anterior.valor) {
      _c.text = widget.valor;
    }
  }

  @override
  Widget build(BuildContext context) => CampoFormulario(
    etiqueta: widget.obligatorio ? '${widget.etiqueta} *' : widget.etiqueta,
    ayuda: widget.ayuda,
    error: widget.error,
    hijo: TextFormField(
      controller: _c,
      onChanged: widget.onCambio,
      maxLines: widget.lineas,
      textCapitalization: widget.capitalizar
          ? TextCapitalization.words
          : TextCapitalization.sentences,
      inputFormatters: widget.mayusculas
          ? [_AMayusculas()]
          : const <TextInputFormatter>[],
    ),
  );
}

class _AMayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) => nuevo.copyWith(text: nuevo.text.toUpperCase());
}

/// Campo de números enteros (año, kilómetros, cantidad).
class CampoNumero extends StatefulWidget {
  const CampoNumero({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.ayuda,
    this.error,
    this.sufijo,
    this.obligatorio = false,
  });

  final String etiqueta, valor;
  final ValueChanged<String> onCambio;
  final String? ayuda, error, sufijo;
  final bool obligatorio;

  @override
  State<CampoNumero> createState() => _CampoNumeroState();
}

class _CampoNumeroState extends State<CampoNumero> {
  late final _c = TextEditingController(text: widget.valor);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampoNumero anterior) {
    super.didUpdateWidget(anterior);
    if (widget.valor != _c.text && widget.valor != anterior.valor) {
      _c.text = widget.valor;
    }
  }

  @override
  Widget build(BuildContext context) => CampoFormulario(
    etiqueta: widget.obligatorio ? '${widget.etiqueta} *' : widget.etiqueta,
    ayuda: widget.ayuda,
    error: widget.error,
    hijo: TextFormField(
      controller: _c,
      onChanged: widget.onCambio,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontFamily: TemaApp.mono, fontSize: 16),
      decoration: InputDecoration(suffixText: widget.sufijo),
    ),
  );
}

/// Campo de plata, con el signo adelante y sin centavos.
class CampoMonto extends StatefulWidget {
  const CampoMonto({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.ayuda,
    this.error,
    this.obligatorio = false,
  });

  final String etiqueta;
  final double? valor;
  final ValueChanged<double?> onCambio;
  final String? ayuda, error;
  final bool obligatorio;

  @override
  State<CampoMonto> createState() => _CampoMontoState();
}

class _CampoMontoState extends State<CampoMonto> {
  late final _c = TextEditingController(
    text: widget.valor == null ? '' : widget.valor!.round().toString(),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampoMonto anterior) {
    super.didUpdateWidget(anterior);
    if (widget.valor != anterior.valor) {
      final texto = widget.valor == null
          ? ''
          : widget.valor!.round().toString();
      if (texto != _c.text) _c.text = texto;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return CampoFormulario(
      etiqueta: widget.obligatorio ? '${widget.etiqueta} *' : widget.etiqueta,
      ayuda: widget.ayuda,
      error: widget.error,
      hijo: TextFormField(
        controller: _c,
        onChanged: (t) => widget.onCambio(double.tryParse(t)),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontFamily: TemaApp.mono, fontSize: 18),
        decoration: InputDecoration(
          prefixText: r'$ ',
          prefixStyle: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 18,
            color: p.tinta3,
          ),
        ),
      ),
    );
  }
}

/// Campo de fecha, con el calendario nativo.
class CampoFecha extends StatelessWidget {
  const CampoFecha({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.ayuda,
    this.error,
    this.obligatorio = false,
  });

  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime> onCambio;
  final String? ayuda, error;
  final bool obligatorio;

  @override
  Widget build(BuildContext context) => CampoFormulario(
    etiqueta: obligatorio ? '$etiqueta *' : etiqueta,
    ayuda: ayuda,
    error: error,
    hijo: SelectorFecha(valor: valor, onCambio: onCambio),
  );
}
