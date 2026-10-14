import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tema/tema.dart';
import 'datos_agencia.dart';

/// Los datos de la agencia: nombre, CUIT, contacto y dirección.
///
/// Acá vivían también los umbrales del motor —los días del semáforo, los
/// márgenes, la tasa y el redondeo—. Se sacaron a pedido de la agencia: son
/// números que se eligen una vez y no se vuelven a tocar, y tenerlos a mano
/// invitaba a moverlos sin saber que repintaban el inventario entero.
///
/// Siguen existiendo en la base, con los valores con los que arranca cada
/// agencia. Si alguna vez hay que cambiárselos a un cliente, se cambian ahí.
class PantallaConfiguracion extends ConsumerWidget {
  const PantallaConfiguracion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esMovil = MediaQuery.sizeOf(context).width < Corte.tablet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          esMovil ? Esp.lg + 4 : Esp.xxl,
          Esp.xl,
          esMovil ? Esp.lg + 4 : Esp.xxl,
          96,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: const DatosDeLaAgencia(),
            ),
          ),
        ],
      ),
    );
  }
}
