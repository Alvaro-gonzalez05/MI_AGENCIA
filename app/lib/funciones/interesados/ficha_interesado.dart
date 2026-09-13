import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/formato.dart';
import '../../core/sesion.dart';
import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/bcra.dart';
import '../../dominio/modelos.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';
import 'informe_pdf.dart';

/// Ficha de un interesado: quién es, qué quiere y si le podemos financiar.
///
/// El estado vive acá adentro y no en el provider de la lista porque una
/// consulta al BCRA tarda unos segundos: si al volver hubiera que recargar
/// toda la lista, el vendedor vería la pantalla en blanco justo después de
/// apretar el botón. Al salir se invalida la lista y ahí sí se refresca.
class FichaInteresado extends ConsumerStatefulWidget {
  const FichaInteresado({super.key, required this.interesado});

  final Interesado interesado;

  @override
  ConsumerState<FichaInteresado> createState() => _FichaInteresadoState();
}

class _FichaInteresadoState extends ConsumerState<FichaInteresado> {
  late Interesado _i = widget.interesado;
  bool _consultando = false;
  bool _generandoPdf = false;
  String? _error;

  /// Se invalida la lista al salir solo si algo cambió de verdad.
  bool _huboCambios = false;

  Future<void> _consultar({required String cuit, bool forzar = false}) async {
    setState(() {
      _consultando = true;
      _error = null;
    });

    try {
      final repo = ref.read(repositorioProvider);

      // Si el CUIT es nuevo se guarda primero: así queda cargado aunque el
      // BCRA se caiga justo ahora y haya que reintentar mañana.
      if (cuit != _i.cuit) {
        await repo.guardarCuit(clienteId: _i.clienteId, cuit: cuit);
        if (mounted) setState(() => _i = _i.copiar(cuit: cuit));
      }

      final consulta = await repo.consultarBcra(
        clienteId: _i.clienteId,
        cuit: cuit,
        forzar: forzar,
      );

      if (!mounted) return;
      setState(() {
        _i = _i.copiar(consulta: consulta, cuit: cuit);
        _consultando = false;
        _huboCambios = true;
      });

      if (consulta.cacheada) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se muestra la consulta del ${Fmt.fecha(consulta.consultadoEl)}. '
              'El BCRA publica una vez por mes.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consultando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Arma el PDF y se lo pasa al sistema: en Windows abre el visor, en
  /// Android la hoja de compartir. No se guarda en ninguna carpeta nuestra
  /// porque el informe es del cliente, no del sistema.
  Future<void> _informe() async {
    setState(() => _generandoPdf = true);
    final mensajero = ScaffoldMessenger.of(context);
    final usuario = ref.read(usuarioProvider);

    try {
      // El nombre de la agencia sale del provider y no de la sesion: la
      // sesion lo leyo al entrar, y si lo cambiaron en Configuracion despues,
      // el informe saldria con el nombre viejo hasta el proximo login.
      final agencia =
          ref.read(miAgenciaProvider).value?.nombre ?? usuario?.agenciaNombre;

      final bytes = await InformeCrediticio.generar(
        interesado: _i,
        agencia: agencia,
        generadoPor: usuario?.nombre,
      );
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: InformeCrediticio.nombreArchivo(_i),
      );
    } catch (e) {
      mensajero.showSnackBar(
        SnackBar(content: Text('No se pudo generar el informe: $e')),
      );
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;
    final c = _i.consulta;

    return PopScope(
      onPopInvokedWithResult: (_, _) {
        if (_huboCambios) ref.invalidate(interesadosProvider);
      },
      child: Scaffold(
        backgroundColor: p.fondo,
        appBar: AppBar(
          title: Text(_i.nombre),
          actions: [
            if (c != null)
              Padding(
                padding: const EdgeInsets.only(right: Esp.md),
                child: _generandoPdf
                    ? const Padding(
                        padding: EdgeInsets.all(Esp.md),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _informe,
                        icon: const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 17,
                        ),
                        label: Text(esMovil ? 'PDF' : 'Descargar informe'),
                      ),
              ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            esMovil ? Esp.lg : Esp.xxl,
            Esp.lg,
            esMovil ? Esp.lg : Esp.xxl,
            Esp.xxxl,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Aparecer(child: _Veredicto(interesado: _i)),

                    const SizedBox(height: Esp.md),
                    Aparecer(
                      indice: 1,
                      child: _Consulta(
                        interesado: _i,
                        consultando: _consultando,
                        error: _error,
                        onConsultar: _consultar,
                      ),
                    ),

                    if (c != null && c.entidades.isNotEmpty) ...[
                      const SizedBox(height: Esp.md),
                      Aparecer(indice: 2, child: _Entidades(consulta: c)),
                    ],

                    if (c != null && c.cheques.isNotEmpty) ...[
                      const SizedBox(height: Esp.md),
                      Aparecer(indice: 3, child: _Cheques(consulta: c)),
                    ],

                    const SizedBox(height: Esp.md),
                    Aparecer(indice: 4, child: _Contacto(interesado: _i)),

                    const SizedBox(height: Esp.md),
                    Aparecer(indice: 5, child: _Operacion(interesado: _i)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El bloque grande de arriba: color, veredicto y por qué.
class _Veredicto extends StatelessWidget {
  const _Veredicto({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;
    final s = i.semaforo;
    final c = i.consulta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      color: s.lavado(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El punto del semáforo, con su resplandor. Es el dato que la
              // agencia mira primero y desde el otro lado del escritorio.
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: s.color(p),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: s.color(p).withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  switch (s) {
                    SemaforoCrediticio.verde => Icons.check_rounded,
                    SemaforoCrediticio.amarillo => Icons.priority_high_rounded,
                    SemaforoCrediticio.rojo => Icons.close_rounded,
                    SemaforoCrediticio.sinDatos => Icons.question_mark_rounded,
                  },
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: Esp.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.etiqueta,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: s.color(p),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: Esp.xs),
                    Text(
                      c?.recomendacion ??
                          'Todavía no se consultó el BCRA para esta persona.',
                      style: TextStyle(
                        fontSize: 13,
                        color: p.tinta2,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (c != null) ...[
            const SizedBox(height: Esp.lg),
            Divider(color: p.borde, height: 1),
            const SizedBox(height: Esp.md),
            for (final motivo in c.motivos)
              Padding(
                padding: const EdgeInsets.only(bottom: Esp.xs + 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 6, right: Esp.sm),
                      decoration: BoxDecoration(
                        color: s.color(p),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        motivo,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: p.tinta2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: Esp.md),
            LayoutBuilder(
              builder: (context, r) {
                final anchos = r.maxWidth >= 560 ? 5 : 2;
                final ancho = (r.maxWidth - Esp.sm * (anchos - 1)) / anchos;
                return Wrap(
                  spacing: Esp.sm,
                  runSpacing: Esp.sm,
                  children: [
                    for (final (etiqueta, valor, detalle) in [
                      (
                        'Peor situación',
                        c.situacionMaxima == null
                            ? '—'
                            : '${c.situacionMaxima}',
                        c.entidades.isEmpty
                            ? 'sin deudas'
                            : c.entidades.first.descripcionSituacion,
                      ),
                      ('Entidades', '${c.entidades.length}', null),
                      (
                        'Deuda informada',
                        Fmt.pesosCompacto(c.totalDeuda),
                        null,
                      ),
                      (
                        'Atraso máximo',
                        c.diasAtrasoMax == 0 ? '0' : '${c.diasAtrasoMax} d',
                        null,
                      ),
                      (
                        'Cheques impagos',
                        '${c.chequesSinPagar}',
                        c.chequesSinPagar > 0 ? 'sin pagar' : null,
                      ),
                    ])
                      SizedBox(
                        width: ancho,
                        child: _Mini(
                          etiqueta: etiqueta,
                          valor: valor,
                          detalle: detalle,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.etiqueta, required this.valor, this.detalle});

  final String etiqueta, valor;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Esp.md,
        vertical: Esp.sm + 2,
      ),
      decoration: BoxDecoration(
        color: p.superficie,
        borderRadius: BorderRadius.circular(Curva.md),
        border: Border.all(color: p.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: p.tinta3),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: p.tinta,
            ),
          ),
          if (detalle != null)
            Text(
              detalle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: p.tinta3),
            ),
        ],
      ),
    );
  }
}

/// Entrada del CUIT y botón de consulta.
class _Consulta extends StatefulWidget {
  const _Consulta({
    required this.interesado,
    required this.consultando,
    required this.error,
    required this.onConsultar,
  });

  final Interesado interesado;
  final bool consultando;
  final String? error;
  final void Function({required String cuit, bool forzar}) onConsultar;

  @override
  State<_Consulta> createState() => _ConsultaState();
}

class _ConsultaState extends State<_Consulta> {
  late final _ctrl = TextEditingController(
    text: widget.interesado.cuit == null
        ? ''
        : formatearCuit(widget.interesado.cuit!),
  );
  String? _errorCuit;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _lanzar({bool forzar = false}) {
    final limpio = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (limpio.isEmpty) {
      setState(() => _errorCuit = 'Escribí el CUIT o CUIL de la persona.');
      return;
    }
    if (!cuitValido(limpio)) {
      // Se valida acá para no gastar una consulta: el BCRA contesta 404 a un
      // CUIT inexistente, y ese 404 significa "no tiene deudas". Un dígito
      // mal tipeado pintaría de verde a cualquiera.
      setState(
        () => _errorCuit = limpio.length != 11
            ? 'Un CUIT/CUIL tiene 11 dígitos; escribiste ${limpio.length}.'
            : 'Ese número no es un CUIT/CUIL válido. Revisá los dígitos.',
      );
      return;
    }
    setState(() => _errorCuit = null);
    FocusScope.of(context).unfocus();
    widget.onConsultar(cuit: limpio, forzar: forzar);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final c = widget.interesado.consulta;
    final yaConsultado = c != null;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: yaConsultado
                ? 'Consulta al Banco Central'
                : 'Consultar al Banco Central',
            descripcion: yaConsultado
                ? 'Último período publicado: '
                      '${c.periodoLegible.isEmpty ? 'sin dato' : c.periodoLegible}'
                : 'Con el CUIT o CUIL alcanza. La consulta es gratuita.',
          ),
          const SizedBox(height: Esp.lg),

          CampoFormulario(
            etiqueta: 'CUIT / CUIL',
            ayuda: 'Once dígitos. Se puede escribir con o sin guiones.',
            error: _errorCuit,
            hijo: TextFormField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              // Sin esto entran letras que después hay que limpiar, y en
              // Android el teclado numérico igual ofrece símbolos.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: const TextStyle(fontFamily: TemaApp.mono, fontSize: 15),
              decoration: const InputDecoration(hintText: '20-12345678-9'),
              onFieldSubmitted: (_) => _lanzar(),
            ),
          ),

          if (widget.error != null) ...[
            const SizedBox(height: Esp.md),
            AvisoError(mensaje: widget.error!),
          ],

          const SizedBox(height: Esp.lg),
          // En un celular el aviso y el boton no entran en la misma linea: el
          // boton se queda con todo el ancho y al texto le sobra un pixel,
          // donde termina partiendose letra por letra. Abajo de cierto ancho
          // se apilan.
          LayoutBuilder(
            builder: (context, r) {
              final aviso = yaConsultado
                  ? Text(
                      c.vencida
                          ? 'Esta consulta tiene más de 30 días: el BCRA ya '
                                'publicó un período nuevo.'
                          : 'Consultado el ${Fmt.fecha(c.consultadoEl)}. El '
                                'BCRA publica una vez por mes.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.vencida ? p.observar : p.tinta3,
                        height: 1.4,
                      ),
                    )
                  : null;

              final boton = widget.consultando
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: Esp.lg,
                        vertical: Esp.sm,
                      ),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : yaConsultado
                  ? OutlinedButton.icon(
                      onPressed: () => _lanzar(forzar: true),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Volver a consultar'),
                    )
                  : FilledButton.icon(
                      onPressed: _lanzar,
                      icon: const Icon(Icons.search_rounded, size: 17),
                      label: const Text('Consultar BCRA'),
                    );

              if (r.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (aviso != null) ...[
                      aviso,
                      const SizedBox(height: Esp.md),
                    ],
                    Align(alignment: Alignment.centerRight, child: boton),
                  ],
                );
              }

              return Row(
                children: [
                  if (aviso != null) Expanded(child: aviso) else const Spacer(),
                  const SizedBox(width: Esp.md),
                  boton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Quién le prestó y cómo viene pagando, entidad por entidad.
class _Entidades extends StatelessWidget {
  const _Entidades({required this.consulta});

  final ConsultaBcra consulta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Detalle por entidad',
            descripcion:
                '${consulta.entidades.length} '
                '${consulta.entidades.length == 1 ? 'entidad informó' : 'entidades informaron'} '
                'deuda a su nombre',
          ),
          const SizedBox(height: Esp.lg),
          for (var i = 0; i < consulta.entidades.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: Esp.sm),
              Divider(color: p.borde, height: 1),
              const SizedBox(height: Esp.sm),
            ],
            _FilaEntidad(entidad: consulta.entidades[i]),
          ],
        ],
      ),
    );
  }
}

class _FilaEntidad extends StatelessWidget {
  const _FilaEntidad({required this.entidad});

  final EntidadBcra entidad;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final e = entidad;

    // El color de la fila sale de la situación de ESA entidad, no del
    // semáforo general: una sola entidad en rojo entre diez normales tiene
    // que poder distinguirse de un rojo generalizado.
    final color = switch (e.situacion) {
      1 => p.bien,
      2 => p.observar,
      3 => p.atencion,
      _ => p.critico,
    };

    // Etiquetas cortas a proposito: van en la columna angosta del desglose,
    // al lado del monto. El detalle largo esta en el PDF, que tiene una hoja
    // entera para explicarlo.
    final marcas = [
      if (e.refinanciaciones) 'Refinanciada',
      if (e.situacionJuridica) 'Sit. jurídica',
      if (e.procesoJudicial) 'Juicio',
      if (e.enRevision) 'En revisión',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            '${e.situacion}',
            style: TextStyle(
              fontFamily: TemaApp.mono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: Esp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.entidad,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.tinta,
                  height: 1.3,
                ),
              ),
              Text(
                '${e.descripcionSituacion} · ${e.queSignifica}',
                style: TextStyle(fontSize: 11.5, color: p.tinta3, height: 1.35),
              ),
              if (e.diasAtraso > 0)
                Text(
                  '${e.diasAtraso} días de atraso',
                  style: TextStyle(fontSize: 11.5, color: p.atencion),
                ),
              if (marcas.isNotEmpty) ...[
                const SizedBox(height: Esp.xs + 2),
                Wrap(
                  spacing: Esp.xs + 2,
                  runSpacing: Esp.xs,
                  children: [
                    for (final m in marcas)
                      Pastilla(
                        texto: m,
                        color: p.atencion,
                        lavado: p.atencionLavado,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Esp.sm),
        Text(
          Fmt.pesosCompacto(e.monto),
          style: TextStyle(
            fontFamily: TemaApp.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: p.tinta2,
          ),
        ),
      ],
    );
  }
}

class _Cheques extends StatelessWidget {
  const _Cheques({required this.consulta});

  final ConsultaBcra consulta;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final impagos = consulta.cheques.where((q) => !q.pagado).length;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CabeceraBloque(
            titulo: 'Cheques rechazados',
            descripcion: impagos == 0
                ? 'Todos fueron pagados después del rechazo'
                : '$impagos sin pagar de ${consulta.cheques.length}',
          ),
          const SizedBox(height: Esp.lg),
          for (final q in consulta.cheques)
            Padding(
              padding: const EdgeInsets.only(bottom: Esp.sm),
              child: Row(
                children: [
                  IconoEnCirculo(
                    icono: q.pagado
                        ? Icons.task_alt_rounded
                        : Icons.report_gmailerrorred_rounded,
                    tamano: 30,
                    color: q.pagado ? p.bien : p.critico,
                    fondo: q.pagado ? p.bienLavado : p.criticoLavado,
                  ),
                  const SizedBox(width: Esp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cheque ${q.numero}',
                          style: TextStyle(
                            fontFamily: TemaApp.mono,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.tinta,
                          ),
                        ),
                        Text(
                          [
                            if (q.entidad != null) q.entidad!,
                            if (q.fechaRechazo != null)
                              'rechazado el ${Fmt.fecha(q.fechaRechazo)}',
                            if (q.pagado)
                              'pagado el ${Fmt.fecha(q.fechaPago)}'
                            else
                              'SIN PAGAR',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: q.pagado ? p.tinta3 : p.critico,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Esp.sm),
                  Text(
                    Fmt.pesosCompacto(q.monto),
                    style: TextStyle(
                      fontFamily: TemaApp.mono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: p.tinta2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Contacto extends StatelessWidget {
  const _Contacto({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final i = interesado;
    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'Datos de la persona'),
          const SizedBox(height: Esp.md),
          FilaDato(
            etiqueta: 'CUIT / CUIL',
            valor: i.cuit == null ? Fmt.sinDato : formatearCuit(i.cuit!),
            mono: true,
          ),
          FilaDato(etiqueta: 'DNI', valor: i.dni ?? Fmt.sinDato, mono: true),
          FilaDato(
            etiqueta: 'Teléfono',
            valor: i.telefono ?? Fmt.sinDato,
            mono: true,
          ),
          if (i.whatsapp != null)
            FilaDato(etiqueta: 'WhatsApp', valor: i.whatsapp!, mono: true),
          FilaDato(etiqueta: 'Email', valor: i.email ?? Fmt.sinDato),
          FilaDato(
            etiqueta: 'Localidad',
            valor: [
              i.localidad,
              i.provincia,
            ].whereType<String>().join(', ').ifEmpty(Fmt.sinDato),
          ),
          FilaDato(etiqueta: 'Origen', valor: i.origen ?? Fmt.sinDato),
          FilaDato(etiqueta: 'Cargado el', valor: Fmt.fecha(i.fecha)),
          if (i.consulta?.denominacion != null)
            FilaDato(
              etiqueta: 'Nombre en el BCRA',
              valor: i.consulta!.denominacion!,
            ),
        ],
      ),
    );
  }
}

class _Operacion extends StatelessWidget {
  const _Operacion({required this.interesado});

  final Interesado interesado;

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final i = interesado;

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabeceraBloque(titulo: 'La operación'),
          const SizedBox(height: Esp.md),
          FilaDato(
            etiqueta: 'Unidad',
            valor: i.vehiculoTitulo == null
                ? 'Sin unidad definida'
                : '${i.vehiculoCodigo ?? ''} ${i.vehiculoTitulo}'.trim(),
          ),
          FilaDato(
            etiqueta: 'Precio de la unidad',
            valor: Fmt.pesos(i.vehiculoPrecio),
            mono: true,
          ),
          FilaDato(
            etiqueta: 'Presupuesto',
            valor: Fmt.pesos(i.presupuestoMax),
            mono: true,
          ),
          FilaDato(
            etiqueta: 'Pide financiación',
            valor: i.necesitaFinanciacion ? 'Sí' : 'No',
            valorColor:
                i.necesitaFinanciacion && i.semaforo == SemaforoCrediticio.rojo
                ? p.critico
                : null,
          ),
          if (i.entregaUsado)
            FilaDato(
              etiqueta: 'Entrega un usado',
              valor: i.usadoDescripcion ?? 'Sí',
            ),
          if (i.entregaUsado && i.usadoValorEstimado != null)
            FilaDato(
              etiqueta: 'Valor del usado',
              valor: Fmt.pesos(i.usadoValorEstimado),
              mono: true,
            ),
          if (i.interes != null)
            FilaDato(etiqueta: 'Nivel de interés', valor: '${i.interes}/5'),
          if (i.proximaAccion != null)
            FilaDato(etiqueta: 'Próxima acción', valor: i.proximaAccion!),
          if (i.proximaAccionFecha != null)
            FilaDato(
              etiqueta: 'Fecha de esa acción',
              valor: Fmt.fecha(i.proximaAccionFecha),
            ),
          if ((i.notas ?? '').isNotEmpty) ...[
            const SizedBox(height: Esp.md),
            Text(
              i.notas!,
              style: TextStyle(fontSize: 12.5, color: p.tinta2, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
