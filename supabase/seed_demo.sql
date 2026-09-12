-- =====================================================================
-- MI AGENCIA — agencia de ejemplo
--
-- GENERADO por tests/generar_seed_demo.mjs. No editar a mano.
--
-- Carga una agencia con los datos reales del sistema original del cliente
-- (13 vehiculos, 36 gastos, 11 cambios de precio, 2 ventas,
-- 3 interesados) para poder recorrer la app con contenido.
--
-- Es idempotente y REVERSIBLE: borrar la agencia se lleva todo por cascada.
--   delete from public.agencias where slug = 'demo';
-- =====================================================================

do $seed$
declare
  v_agencia uuid;
  v_usuario uuid;
  v_id      uuid;
begin
  -- Se engancha al primer desarrollador que exista, sin hardcodear un email.
  select id into v_usuario from public.perfiles
   where es_desarrollador order by created_at limit 1;

  if v_usuario is null then
    raise exception 'No hay ningun usuario con es_desarrollador = true. Crealo primero.';
  end if;

  delete from public.agencias where slug = 'demo';

  insert into public.agencias (nombre, slug, localidad, provincia, plan, creada_por)
  values ('Agencia Demo', 'demo', 'Godoy Cruz', 'Mendoza', 'basico', v_usuario)
  returning id into v_agencia;

  insert into public.membresias (agencia_id, usuario_id, rol)
  values (v_agencia, v_usuario, 'owner');

  insert into public.vehiculos (agencia_id, codigo, marca, modelo, anio, version, km,
    fecha_compra, fecha_ingreso, precio_compra, precio_objetivo, estado, observaciones, created_by)
  select v_agencia, d.codigo, d.marca, d.modelo, d.anio, d.version, d.km,
         d.fecha_compra::date, d.fecha_ingreso::date, d.precio_compra, d.precio_objetivo,
         d.estado::estado_vehiculo, d.obs, v_usuario
  from (values
    ('V001', 'Toyota', 'Corolla', 2021, 'XEI 1.8 CVT', 62000, '2026-05-28', '2026-05-30', 19800000, 22500000, 'en_stock', 'Único dueño, service oficial'),
    ('V002', 'Volkswagen', 'Amarok', 2020, 'V6 Highline', 98000, '2026-03-10', '2026-03-12', 34500000, 39900000, 'en_stock', 'Requiere cubiertas nuevas'),
    ('V003', 'Ford', 'Ranger', 2022, 'XLT 3.2 4x4', 71000, '2026-07-14', '2026-07-16', 41000000, 46500000, 'en_stock', 'Ingresó por parte de pago'),
    ('V004', 'Chevrolet', 'Cruze', 2019, 'LTZ 1.4T', 88000, '2026-02-05', '2026-02-08', 15200000, 18500000, 'en_stock', 'Detalle de chapa en puerta trasera'),
    ('V005', 'Fiat', 'Cronos', 2023, 'Drive 1.3 GSE', 34000, '2026-08-01', '2026-08-03', 16900000, 19200000, 'en_stock', 'Muy bajo kilometraje'),
    ('V006', 'Peugeot', '208', 2022, 'Allure 1.6', 41000, '2026-06-18', '2026-06-20', 17400000, 20000000, 'en_stock', null),
    ('V007', 'Renault', 'Duster', 2021, 'Iconic 1.3T', 66000, '2026-04-22', '2026-04-25', 21000000, 24500000, 'en_preparacion', 'En taller por chapa y pintura'),
    ('V008', 'Honda', 'HR-V', 2020, 'EXL CVT', 79000, '2026-01-15', '2026-01-18', 24800000, 29000000, 'en_stock', 'Difícil rotación, revisar precio'),
    ('V009', 'Toyota', 'Hilux', 2019, 'SRV 4x4 AT', 132000, '2026-05-05', '2026-05-07', 32000000, 37500000, 'reservado', 'Seña recibida'),
    ('V010', 'Nissan', 'Kicks', 2021, 'Advance CVT', 58000, '2026-07-28', '2026-07-30', 20500000, 23500000, 'en_stock', null),
    ('V011', 'Volkswagen', 'Gol Trend', 2018, 'Trendline 1.6', 105000, '2026-02-20', '2026-02-22', 9800000, 12500000, 'en_stock', 'Unidad de entrada, alta demanda'),
    ('V012', 'Chevrolet', 'Tracker', 2022, 'Premier 1.2T', 45000, '2026-06-02', '2026-06-04', 26500000, 30500000, 'en_stock', null),
    ('V013', 'Ford', 'EcoSport', 2019, 'SE 1.5', 92000, '2026-03-01', '2026-03-04', 13500000, 16500000, 'en_stock', 'Vendida a cliente recurrente')
  ) as d(codigo, marca, modelo, anio, version, km, fecha_compra, fecha_ingreso,
         precio_compra, precio_objetivo, estado, obs);

  insert into public.gastos (agencia_id, vehiculo_id, fecha, categoria, descripcion, importe, created_by)
  select v_agencia, v.id, d.fecha::date, d.categoria::categoria_gasto, d.descripcion, d.importe, v_usuario
  from (values
    ('V001', '2026-06-02', 'service', 'Service completo 60.000 km', 320000),
    ('V001', '2026-06-05', 'lavado_detallado', 'Detallado interior y pulido', 85000),
    ('V001', '2026-06-10', 'transferencia', 'Gastos de transferencia', 210000),
    ('V002', '2026-03-20', 'cubiertas', '4 cubiertas 255/60 R18', 1450000),
    ('V002', '2026-04-02', 'service', 'Service mayor V6', 480000),
    ('V002', '2026-05-15', 'reparaciones', 'Reparación tren delantero', 620000),
    ('V002', '2026-06-20', 'almacenamiento', 'Cochera 3 meses', 180000),
    ('V003', '2026-07-20', 'lavado_detallado', 'Lavado y detallado', 70000),
    ('V003', '2026-07-25', 'gestoria', 'Gestoría documentación', 150000),
    ('V004', '2026-02-15', 'chapa_y_pintura', 'Chapa y pintura puerta trasera', 540000),
    ('V004', '2026-03-10', 'service', 'Service de mantenimiento', 240000),
    ('V004', '2026-05-05', 'almacenamiento', 'Cochera 3 meses', 180000),
    ('V004', '2026-07-01', 'reparaciones', 'Cambio de embrague', 710000),
    ('V005', '2026-08-05', 'lavado_detallado', 'Lavado de entrega', 45000),
    ('V006', '2026-06-25', 'service', 'Service 40.000 km', 260000),
    ('V006', '2026-07-08', 'cubiertas', '2 cubiertas delanteras', 380000),
    ('V007', '2026-05-02', 'chapa_y_pintura', 'Reparación lateral completo', 980000),
    ('V007', '2026-05-20', 'service', 'Service + correa', 410000),
    ('V007', '2026-06-15', 'reparaciones', 'Suspensión trasera', 350000),
    ('V008', '2026-01-25', 'service', 'Service CVT', 390000),
    ('V008', '2026-02-18', 'cubiertas', '4 cubiertas 215/55 R17', 1120000),
    ('V008', '2026-04-10', 'almacenamiento', 'Cochera 3 meses', 180000),
    ('V008', '2026-06-05', 'reparaciones', 'Aire acondicionado', 290000),
    ('V008', '2026-07-12', 'almacenamiento', 'Cochera 2 meses', 120000),
    ('V009', '2026-05-15', 'service', 'Service 130.000 km', 520000),
    ('V009', '2026-05-28', 'patentamiento', 'Trámite patentamiento', 340000),
    ('V010', '2026-08-02', 'lavado_detallado', 'Detallado completo', 90000),
    ('V010', '2026-08-08', 'transferencia', 'Gastos de transferencia', 230000),
    ('V011', '2026-03-01', 'reparaciones', 'Motor de arranque', 180000),
    ('V011', '2026-03-15', 'chapa_y_pintura', 'Retoque de pintura general', 420000),
    ('V011', '2026-06-01', 'almacenamiento', 'Cochera 4 meses', 240000),
    ('V012', '2026-06-10', 'service', 'Service completo', 300000),
    ('V012', '2026-06-18', 'lavado_detallado', 'Detallado de entrega', 80000),
    ('V013', '2026-03-12', 'reparaciones', 'Caja de dirección', 450000),
    ('V013', '2026-03-25', 'service', 'Service general', 230000),
    ('V013', '2026-04-05', 'transferencia', 'Gastos de transferencia', 190000)
  ) as d(codigo, fecha, categoria, descripcion, importe)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo;

  -- El precio anterior de cada cambio lo completa un trigger.
  insert into public.cambios_precio (agencia_id, vehiculo_id, fecha, precio_nuevo, motivo, created_by)
  select v_agencia, v.id, d.fecha::date, d.precio, d.motivo, v_usuario
  from (values
    ('V001', '2026-08-10', 22100000, 'Ajuste por baja de consultas'),
    ('V002', '2026-06-05', 38500000, 'Reducción para acelerar rotación'),
    ('V004', '2026-05-10', 17800000, 'Ajuste de mercado'),
    ('V004', '2026-07-15', 17200000, 'Sigue sin venderse'),
    ('V007', '2026-06-20', 25200000, 'Suba por reparaciones realizadas'),
    ('V008', '2026-04-05', 27500000, 'Baja rotación'),
    ('V008', '2026-06-20', 26200000, 'Segunda baja de precio'),
    ('V009', '2026-07-01', 36800000, 'Negociación con cliente'),
    ('V011', '2026-05-01', 12900000, 'Alta demanda del segmento'),
    ('V012', '2026-07-05', 29800000, 'Cierre de operación'),
    ('V013', '2026-05-10', 15900000, 'Ajuste para cerrar venta')
  ) as d(codigo, fecha, precio, motivo)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo
  order by d.fecha;

  -- Al insertar la venta, un trigger saca la unidad del stock.
  insert into public.ventas (agencia_id, vehiculo_id, fecha_venta, precio_final, gastos_finales, observaciones, created_by)
  select v_agencia, v.id, d.fecha::date, d.precio_final, d.gastos_finales, d.obs, v_usuario
  from (values
    ('V012', '2026-07-18', 29500000, 120000, 'Financiación propia 12 cuotas'),
    ('V013', '2026-05-22', 15700000, 90000, 'Cliente recurrente')
  ) as d(codigo, fecha, precio_final, gastos_finales, obs)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo;

  -- Interesados: en el sistema original eran una tabla plana. Aca se separan en
  -- la PERSONA (clientes) y su INTERES en una unidad (oportunidades), que es lo
  -- que despues habilita el semaforo del BCRA y el email marketing.
  with datos as (
    select * from (values
      ('V003', 'L.', 'Benítez', '11-4455-2200', 'Preguntó por financiación a 12 cuotas'),
    ('V008', 'R.', 'Ibarra', '11-6677-8899', 'Va a volver con su pareja a ver la unidad'),
    ('V012', 'C.', 'Domínguez', '11-2233-4455', 'Pidió que le avisen si baja el precio')
    ) as d(codigo, nombre, apellido, telefono, notas)
  ),
  nuevos as (
    insert into public.clientes (agencia_id, nombre, apellido, telefono, origen, created_by)
    select v_agencia, d.nombre, d.apellido, d.telefono, 'showroom', v_usuario from datos d
    returning id, telefono)
  insert into public.oportunidades (agencia_id, cliente_id, vehiculo_id, estado, interes, notas, created_by)
  select v_agencia, n.id, v.id, 'contactado', 3, d.notas, v_usuario
  from nuevos n
  join datos d on d.telefono = n.telefono
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo;


  raise notice 'Agencia demo creada: %', v_agencia;
end $seed$;
