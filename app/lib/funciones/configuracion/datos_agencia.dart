import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/colores.dart';
import '../../core/tema/tema.dart';
import '../../datos/repositorio.dart';
import '../../dominio/agencias.dart';
import '../../ui/componentes.dart';
import '../../ui/formulario.dart';

/// Nombre, CUIT y contacto de la agencia.
///
/// Va arriba de todo en Configuración porque es lo primero que hay que cargar
/// en una cuenta nueva: el nombre sale en el encabezado de la app y en el
/// informe crediticio, y hasta que no se cargue queda el que le puso quien
/// creó la cuenta.
///
/// Se guarda aparte de los umbrales del motor, con su propio botón. Son dos
/// cosas distintas: esto es quién sos, aquello es cómo calculás. Con un solo
/// "Guardar", cambiar el teléfono recalcularía el inventario entero.
///
/// El plan, el vencimiento y si la cuenta está activa NO están acá, y no es
/// un olvido: eso es comercial y lo maneja la cuenta de plataforma. Un
/// trigger de la base los revierte aunque alguien los mande igual.
class DatosDeLaAgencia extends ConsumerStatefulWidget {
  const DatosDeLaAgencia({super.key});

  @override
  ConsumerState<DatosDeLaAgencia> createState() => _DatosDeLaAgenciaState();
}

class _DatosDeLaAgenciaState extends ConsumerState<DatosDeLaAgencia> {
  DatosAgencia? _editado;
  Map<String, String> _errores = {};
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    final d = _editado;
    if (d == null) return;

    final errores = d.validar();
    setState(() {
      _errores = errores;
      _error = null;
    });
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await ref.read(repositorioProvider).guardarDatosAgencia(d);
      ref.invalidate(miAgenciaProvider);
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _editado = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos de la agencia guardados')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        // El RLS deja editar la agencia solo al dueño. Traducido, porque
        // "new row violates row-level security policy" no le dice nada a nadie.
        _error = e.toString().contains('row-level security')
            ? 'Solo el dueño de la agencia puede cambiar estos datos.'
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.paleta;
    final asincrono = ref.watch(miAgenciaProvider);

    return Tarjeta(
      padding: const EdgeInsets.all(Esp.xl),
      child: asincrono.when(
        loading: () => const SizedBox(
          height: 88,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'No se pudieron cargar los datos de la agencia.',
          style: TextStyle(fontSize: 13, color: p.tinta3),
        ),
        data: (agencia) {
          if (agencia == null) {
            return Text(
              'Tu usuario todavía no está asociado a ninguna agencia.',
              style: TextStyle(fontSize: 13, color: p.tinta3),
            );
          }

          final d = _editado ?? DatosAgencia.desde(agencia);
          void cambiar(DatosAgencia nuevo) => setState(() => _editado = nuevo);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CabeceraBloque(
                titulo: 'Datos de la agencia',
                descripcion: 'Salen en el encabezado y en los informes',
              ),
              const SizedBox(height: Esp.lg),

              CampoFormulario(
                etiqueta: 'Nombre',
                error: _errores['nombre'],
                hijo: TextFormField(
                  initialValue: d.nombre,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (s) => cambiar(d.copiar(nombre: s)),
                  decoration: const InputDecoration(
                    hintText: 'Automotores del Oeste',
                  ),
                ),
              ),

              const SizedBox(height: Esp.lg),
              LayoutBuilder(
                builder: (context, r) {
                  // Dos columnas solo si de verdad entran: abajo de 520 px, un
                  // campo por fila se lee mejor que dos apretados.
                  final porFila = r.maxWidth >= 520 ? 2 : 1;
                  final ancho = (r.maxWidth - Esp.lg * (porFila - 1)) / porFila;

                  return Wrap(
                    spacing: Esp.lg,
                    runSpacing: Esp.lg,
                    children: [
                      for (final campo in _camposSecundarios(d, cambiar))
                        SizedBox(width: ancho, child: campo),
                    ],
                  );
                },
              ),

              if (_error != null) ...[
                const SizedBox(height: Esp.md),
                AvisoError(mensaje: _error!),
              ],

              if (d.distintoDe(agencia)) ...[
                const SizedBox(height: Esp.lg),
                BotoneraFormulario(
                  guardando: _guardando,
                  etiquetaGuardar: 'Guardar datos',
                  onCancelar: () => setState(() {
                    _editado = null;
                    _errores = {};
                    _error = null;
                  }),
                  onGuardar: _guardar,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _camposSecundarios(
    DatosAgencia d,
    void Function(DatosAgencia) cambiar,
  ) => [
    CampoFormulario(
      etiqueta: 'CUIT',
      ayuda: 'Opcional',
      error: _errores['cuit'],
      hijo: TextFormField(
        initialValue: d.cuit,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontFamily: TemaApp.mono),
        onChanged: (s) => cambiar(d.copiar(cuit: s)),
        decoration: const InputDecoration(hintText: '30-12345678-9'),
      ),
    ),
    CampoFormulario(
      etiqueta: 'Teléfono',
      ayuda: 'Opcional',
      hijo: TextFormField(
        initialValue: d.telefono,
        keyboardType: TextInputType.phone,
        style: const TextStyle(fontFamily: TemaApp.mono),
        onChanged: (s) => cambiar(d.copiar(telefono: s)),
        decoration: const InputDecoration(hintText: '261 555-1234'),
      ),
    ),
    CampoFormulario(
      etiqueta: 'Email de contacto',
      ayuda: 'Opcional',
      error: _errores['emailContacto'],
      hijo: TextFormField(
        initialValue: d.emailContacto,
        keyboardType: TextInputType.emailAddress,
        onChanged: (s) => cambiar(d.copiar(emailContacto: s)),
        decoration: const InputDecoration(hintText: 'contacto@tuagencia.com'),
      ),
    ),
    CampoFormulario(
      etiqueta: 'Localidad',
      ayuda: 'Opcional',
      hijo: TextFormField(
        initialValue: d.localidad,
        textCapitalization: TextCapitalization.words,
        onChanged: (s) => cambiar(d.copiar(localidad: s)),
        decoration: const InputDecoration(hintText: 'Godoy Cruz'),
      ),
    ),
    CampoFormulario(
      etiqueta: 'Provincia',
      ayuda: 'Opcional',
      hijo: TextFormField(
        initialValue: d.provincia,
        textCapitalization: TextCapitalization.words,
        onChanged: (s) => cambiar(d.copiar(provincia: s)),
        decoration: const InputDecoration(hintText: 'Mendoza'),
      ),
    ),
  ];
}
