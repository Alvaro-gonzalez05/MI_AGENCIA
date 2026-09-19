import 'bcra.dart';
import 'modelos.dart';

/// Una solicitud estable permite reintentar sin duplicar la persona ni el interés.
class AltaInteresado {
  const AltaInteresado({
    required this.solicitud,
    required this.nombre,
    required this.cuit,
    this.telefono,
    this.email,
    this.localidad,
    this.vehiculoId,
    this.presupuesto,
    this.financiacion = false,
    this.notas,
    this.aceptaMarketing = false,
  });

  final String solicitud, nombre, cuit;
  final String? telefono, email, localidad, vehiculoId, notas;
  final double? presupuesto;
  final bool financiacion;

  /// Aceptó recibir novedades por email. Se pregunta en el alta y no se
  /// asume: mandarle mails a quien no lo aceptó es spam. Sin email no vale.
  final bool aceptaMarketing;

  void validar() {
    if (nombre.trim().length < 2) {
      throw Exception('Ingresá el nombre del cliente.');
    }
    if (!cuitValido(cuit)) {
      throw Exception('Revisá los 11 dígitos del CUIT/CUIL.');
    }
    if (presupuesto != null && (!presupuesto!.isFinite || presupuesto! <= 0)) {
      throw Exception('El presupuesto debe ser mayor a cero.');
    }
    if (email != null &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email!)) {
      throw Exception('Revisá el correo electrónico.');
    }
  }

  Map<String, dynamic> get json => {
    'nombre': nombre.trim(),
    'cuit': cuit,
    'telefono': telefono,
    'email': email,
    'localidad': localidad,
    'vehiculo_id': vehiculoId,
    'presupuesto_max': presupuesto,
    'necesita_financiacion': financiacion,
    'notas': notas,
    'acepta_marketing': aceptaMarketing && email != null,
  };

  Interesado comoInteresado(String id, String clienteId) => Interesado(
    id: id,
    clienteId: clienteId,
    nombre: nombre.trim(),
    cuit: cuit,
    telefono: telefono,
    email: email,
    localidad: localidad,
    vehiculoId: vehiculoId,
    presupuestoMax: presupuesto,
    necesitaFinanciacion: financiacion,
    notas: notas,
    aceptaMarketing: aceptaMarketing && email != null,
    estadoOportunidad: 'nuevo',
    fecha: DateTime.now(),
  );
}

class InformeGuardado {
  const InformeGuardado({required this.ruta, required this.fecha});
  final String ruta;
  final DateTime fecha;
}
