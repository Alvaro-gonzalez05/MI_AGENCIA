/// Dólar oficial (venta) para el modo demo, que no tiene base a la cual
/// consultarle. Con la base conectada, el motor usa la serie diaria completa
/// que sincroniza `sincronizar_dolar()` (migración 0020) y esto no se usa.
///
/// Valores reales de argentinadatos.com: el primer día hábil de cada mes,
/// más los días del ejemplo del cliente (checklist tanda 2, punto 2.1), que
/// verifica `test/ganancia_dolar_test.dart`.
abstract final class DolarDemo {
  static final serie = <(DateTime, double)>[
    (DateTime.utc(2024, 1, 1), 828.25),
    (DateTime.utc(2024, 2, 1), 846),
    (DateTime.utc(2024, 3, 1), 861.5),
    (DateTime.utc(2024, 4, 1), 876),
    (DateTime.utc(2024, 5, 1), 896),
    (DateTime.utc(2024, 5, 10), 901.5),
    (DateTime.utc(2024, 6, 1), 914),
    (DateTime.utc(2024, 7, 1), 932.5),
    (DateTime.utc(2024, 8, 1), 951.5),
    (DateTime.utc(2024, 9, 1), 972),
    (DateTime.utc(2024, 10, 1), 990.5),
    (DateTime.utc(2024, 11, 1), 1013),
    (DateTime.utc(2024, 12, 1), 1031),
    (DateTime.utc(2025, 1, 1), 1052.5),
    (DateTime.utc(2025, 1, 15), 1061.5),
    (DateTime.utc(2025, 1, 20), 1066),
    (DateTime.utc(2025, 2, 1), 1073.5),
    (DateTime.utc(2025, 3, 1), 1084.25),
    (DateTime.utc(2025, 4, 1), 1094.25),
    (DateTime.utc(2025, 5, 1), 1190),
    (DateTime.utc(2025, 6, 1), 1195),
    (DateTime.utc(2025, 7, 1), 1235),
    (DateTime.utc(2025, 8, 1), 1375),
    (DateTime.utc(2025, 9, 1), 1385),
    (DateTime.utc(2025, 10, 1), 1450),
    (DateTime.utc(2025, 11, 1), 1475),
    (DateTime.utc(2025, 12, 1), 1475),
    (DateTime.utc(2026, 1, 1), 1480),
    (DateTime.utc(2026, 2, 1), 1465),
    (DateTime.utc(2026, 3, 1), 1420),
    (DateTime.utc(2026, 4, 1), 1415),
    (DateTime.utc(2026, 5, 1), 1415),
    (DateTime.utc(2026, 6, 1), 1445),
    (DateTime.utc(2026, 7, 1), 1510),
    (DateTime.utc(2026, 8, 1), 1510),
    (DateTime.utc(2026, 9, 1), 1535),
  ];

  /// Cotización vigente en una fecha: la última anterior o igual. Antes del
  /// primer dato devuelve el primero (no extrapola), igual que el SQL deja
  /// el costo nominal cuando no hay cotización.
  static double en(DateTime fecha) {
    final f = DateTime.utc(fecha.year, fecha.month, fecha.day);
    var valor = serie.first.$2;
    for (final (dia, v) in serie) {
      if (dia.isAfter(f)) break;
      valor = v;
    }
    return valor;
  }
}
