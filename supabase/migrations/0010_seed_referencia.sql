-- =====================================================================
-- MI AGENCIA — 0010: carga inicial de datos publicos
--
-- La serie IPC viene tal cual del HTML del cliente, que la tomo de los
-- informes tecnicos del INDEC. Se mantiene la fuente y la URL de cada mes
-- para poder auditar de donde salio cada numero.
--
-- El ultimo mes esta marcado como proyeccion: el INDEC publica agosto a
-- mediados de septiembre. La Edge Function `sync-indices` lo reemplaza por
-- el dato real cuando sale.
-- =====================================================================

insert into public.ipc_serie (mes, variacion, fuente, url, es_proyeccion) values
  ('2025-07-01', null,  'Mes base de la serie (indice 100).', null, false),
  ('2025-08-01', 0.019, 'INDEC, Informe tecnico IPC — nivel general, total nacional.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-09-01', 0.021, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-10-01', 0.023, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-11-01', 0.025, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2025-12-01', 0.028, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-01-01', 0.029, 'INDEC, Informe tecnico IPC enero 2026 — nivel general 2,9% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_02_261443D4406C.pdf', false),
  ('2026-02-01', 0.029, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-03-01', 0.034, 'INDEC, Informe tecnico IPC marzo 2026 — nivel general 3,4% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_04_26853171E136.pdf', false),
  ('2026-04-01', 0.026, 'INDEC, Informe tecnico IPC abril 2026 — nivel general 2,6% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_05_2680B692D2F5.pdf', false),
  ('2026-05-01', 0.021, 'INDEC, Informe tecnico IPC mayo 2026 — nivel general 2,1% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_06_26C132AEE4E9.pdf', false),
  ('2026-06-01', 0.019, 'INDEC, Informe tecnico IPC.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-07-01', 0.021, 'INDEC, Informe tecnico IPC julio 2026 — nivel general 2,1% mensual.', 'https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf', false),
  ('2026-08-01', 0.021, 'PROYECCION: se repite la variacion de julio hasta que el INDEC publique agosto.', null, true)
on conflict (mes) do nothing;

select public.recalcular_ipc();

-- Cotizaciones iniciales, tomadas de la config del HTML (21/08/2026).
-- A partir de aca las actualiza la Edge Function `sync-indices` contra la
-- API de estadisticas cambiarias del BCRA.
insert into public.cotizaciones (fecha, tipo, compra, venta, fuente) values
  ('2026-08-21', 'oficial',   1495, 1515, 'Config del sistema original del cliente'),
  ('2026-08-21', 'mayorista', 1489, 1499, 'Config del sistema original del cliente'),
  ('2026-08-21', 'blue',      1530, 1550, 'Config del sistema original del cliente')
on conflict (fecha, tipo) do nothing;
