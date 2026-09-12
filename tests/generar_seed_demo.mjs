// Genera supabase/seed_demo.sql: una agencia de ejemplo con los datos reales
// del sistema original del cliente, para poder recorrer la app con contenido.
// Es reversible: al final del archivo esta el borrado.
import { DATA_SEED } from './motor_original.mjs';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const SALIDA = fileURLToPath(new URL('../supabase/seed_demo.sql', import.meta.url));
const q = (s) => s === null || s === undefined || s === '' ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
const ESTADO = { 'En stock': 'en_stock', 'En preparación': 'en_preparacion', 'Reservado': 'reservado' };
const CAT = {
  'Service': 'service', 'Reparaciones': 'reparaciones', 'Cubiertas': 'cubiertas',
  'Chapa y pintura': 'chapa_y_pintura', 'Lavado/Detallado': 'lavado_detallado',
  'Transferencia': 'transferencia', 'Patentamiento': 'patentamiento',
  'Gestoría': 'gestoria', 'Almacenamiento': 'almacenamiento', 'Otros': 'otros',
};

const L = [];
L.push(`-- =====================================================================
-- MI AGENCIA — agencia de ejemplo
--
-- GENERADO por tests/generar_seed_demo.mjs. No editar a mano.
--
-- Carga una agencia con los datos reales del sistema original del cliente
-- (${DATA_SEED.vehiculos.length} vehiculos, ${DATA_SEED.gastos.length} gastos, ${DATA_SEED.precios.length} cambios de precio, ${DATA_SEED.ventas.length} ventas,
-- ${DATA_SEED.interesados.length} interesados) para poder recorrer la app con contenido.
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
`);

const SEP = [",", String.fromCharCode(10), "    "].join("");
const filas = (arr, fn) => arr.map(fn).join(SEP);

L.push(`  insert into public.vehiculos (agencia_id, codigo, marca, modelo, anio, version, km,
    fecha_compra, fecha_ingreso, precio_compra, precio_objetivo, estado, observaciones, created_by)
  select v_agencia, d.codigo, d.marca, d.modelo, d.anio, d.version, d.km,
         d.fecha_compra::date, d.fecha_ingreso::date, d.precio_compra, d.precio_objetivo,
         d.estado::estado_vehiculo, d.obs, v_usuario
  from (values
    ${filas(DATA_SEED.vehiculos, v => `(${q(v.id)}, ${q(v.marca)}, ${q(v.modelo)}, ${v.anio}, ${q(v.version)}, ${v.km}, ${q(v.fechaCompra)}, ${q(v.fechaIngreso)}, ${v.precioCompra}, ${v.precioObjetivo}, ${q(ESTADO[v.estado])}, ${q(v.obs)})`)}
  ) as d(codigo, marca, modelo, anio, version, km, fecha_compra, fecha_ingreso,
         precio_compra, precio_objetivo, estado, obs);

  insert into public.gastos (agencia_id, vehiculo_id, fecha, categoria, descripcion, importe, created_by)
  select v_agencia, v.id, d.fecha::date, d.categoria::categoria_gasto, d.descripcion, d.importe, v_usuario
  from (values
    ${filas(DATA_SEED.gastos, g => `(${q(g.idVehiculo)}, ${q(g.fecha)}, ${q(CAT[g.categoria])}, ${q(g.desc)}, ${g.importe})`)}
  ) as d(codigo, fecha, categoria, descripcion, importe)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo;

  -- El precio anterior de cada cambio lo completa un trigger.
  insert into public.cambios_precio (agencia_id, vehiculo_id, fecha, precio_nuevo, motivo, created_by)
  select v_agencia, v.id, d.fecha::date, d.precio, d.motivo, v_usuario
  from (values
    ${filas(DATA_SEED.precios, p => `(${q(p.idVehiculo)}, ${q(p.fecha)}, ${p.nuevoPrecio}, ${q(p.motivo)})`)}
  ) as d(codigo, fecha, precio, motivo)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo
  order by d.fecha;

  -- Al insertar la venta, un trigger saca la unidad del stock.
  insert into public.ventas (agencia_id, vehiculo_id, fecha_venta, precio_final, gastos_finales, observaciones, created_by)
  select v_agencia, v.id, d.fecha::date, d.precio_final, d.gastos_finales, d.obs, v_usuario
  from (values
    ${filas(DATA_SEED.ventas, s => `(${q(s.idVehiculo)}, ${q(s.fechaVenta)}, ${s.precioFinal}, ${s.gastosFinales}, ${q(s.obs)})`)}
  ) as d(codigo, fecha, precio_final, gastos_finales, obs)
  join public.vehiculos v on v.agencia_id = v_agencia and v.codigo = d.codigo;

  -- Interesados: en el sistema original eran una tabla plana. Aca se separan en
  -- la PERSONA (clientes) y su INTERES en una unidad (oportunidades), que es lo
  -- que despues habilita el semaforo del BCRA y el email marketing.
  with datos as (
    select * from (values
      ${filas(DATA_SEED.interesados, i => { const pz = i.nombre.split(' '); return `(${q(i.idVehiculo)}, ${q(pz[0])}, ${q(pz.slice(1).join(' '))}, ${q(i.telefono)}, ${q(i.obs)})`; })}
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
`);

L.push(`
  raise notice 'Agencia demo creada: %', v_agencia;
end $seed$;
`);

fs.writeFileSync(SALIDA, L.join('\n'));
console.log(`Generado: ${SALIDA} (${L.join('\n').split('\n').length} lineas)`);
