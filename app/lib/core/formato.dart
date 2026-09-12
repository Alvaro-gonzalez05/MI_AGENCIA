import 'package:intl/intl.dart';

/// Formato de numeros y fechas en es-AR.
///
/// Port de fmtARS / fmtUSD / fmtPct / fmtDate del HTML original. Se mantiene
/// el comportamiento: los montos van SIN decimales, porque en una agencia los
/// precios son de millones y los centavos solo agregan ruido a la tabla.
abstract final class Fmt {
  // NumberFormat.currency para es_AR pone el simbolo DETRAS ("3.740.000 $"),
  // que no es como se escribe la plata en Argentina. Se arma a mano con el
  // separador de miles del locale y el simbolo adelante.
  static final _entero = NumberFormat.decimalPattern('es_AR');

  static String _conSimbolo(String simbolo, num n) {
    final negativo = n < 0;
    final cuerpo = _entero.format(n.abs().round());
    return '${negativo ? '-' : ''}$simbolo$cuerpo';
  }
  static final _fecha = DateFormat('dd/MM/yyyy', 'es_AR');
  static final _fechaCorta = DateFormat('dd MMM', 'es_AR');
  static final _mesAnio = DateFormat('MMM yy', 'es_AR');

  /// El guion largo es el marcador de "no hay dato", igual que en el original.
  /// Se usa en vez de "0" o vacio: cero es un valor, ausencia no.
  static const sinDato = '—';

  static String pesos(num? n) => n == null ? sinDato : _conSimbolo(r'$', n);

  static String dolares(num? n) => n == null ? sinDato : _conSimbolo('US\$', n);

  /// Version compacta para tarjetas y ejes de grafico: $264,7 M.
  static String pesosCompacto(num? n) {
    if (n == null) return sinDato;
    final abs = n.abs();
    if (abs >= 1000000000) return '\$${_unDecimal(n / 1000000000)} MM';
    if (abs >= 1000000) return '\$${_unDecimal(n / 1000000)} M';
    if (abs >= 1000) return '\$${_unDecimal(n / 1000)} K';
    return pesos(n);
  }

  static String porcentaje(num? n, {int decimales = 1}) => n == null
      ? sinDato
      : '${(n * 100).toStringAsFixed(decimales).replaceAll('.', ',')}%';

  /// Con signo explicito, para variaciones donde el mas importa tanto como el
  /// menos ("el margen subio 2,1%" vs "bajo 2,1%").
  static String porcentajeConSigno(num? n, {int decimales = 1}) {
    if (n == null) return sinDato;
    final signo = n > 0 ? '+' : '';
    return '$signo${porcentaje(n, decimales: decimales)}';
  }

  static String entero(num? n) => n == null ? sinDato : _entero.format(n);

  static String fecha(DateTime? f) => f == null ? sinDato : _fecha.format(f);

  static String fechaCorta(DateTime? f) =>
      f == null ? sinDato : _fechaCorta.format(f);

  static String mesAnio(DateTime? f) => f == null ? sinDato : _mesAnio.format(f);

  static String dias(int? n) => n == null
      ? sinDato
      : n == 1
          ? '1 día'
          : '$n días';

  /// Kilometraje: 62.000 km.
  static String km(num? n) => n == null ? sinDato : '${_entero.format(n)} km';

  static String _unDecimal(num n) {
    final v = n.toStringAsFixed(1).replaceAll('.', ',');
    return v.endsWith(',0') ? v.substring(0, v.length - 2) : v;
  }
}
