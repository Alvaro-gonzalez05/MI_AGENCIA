# El motor de cálculo

Las fórmulas que definen cuánta plata gana la agencia viven en **una sola
definición**, la vista `v_inventario` (migración `0008`). Es el port del
`computeInventory()` del HTML original, que a su vez replicaba la hoja
"Inventario" del Excel del cliente.

## Por qué en SQL y no en Dart

Si las fórmulas viven en la app, hay que reimplementarlas por plataforma, y
cualquier divergencia entre Windows y Android se paga en pesos. En la base hay
una sola versión; la app lee y muestra.

La excepción son los **simuladores interactivos** (precio sugerido según margen
deseado, cuotas de financiación). Esos sí van en Dart: son "qué pasaría si" que
se recalculan a cada tecla y no se persisten.

## Verificación

`tests/paridad_motor.mjs` levanta un Postgres real (PGlite, Postgres compilado a
WASM — no necesita Docker), aplica las 10 migraciones, carga **los datos reales
del cliente** extraídos del HTML original y compara 21 campos calculados de los
13 vehículos contra la salida del JavaScript original ejecutado en Node.

```bash
cd tests && npm install && npm test
```

Resultado actual: **273 valores comparados, coincidencia total.**

El JS original no se reescribió a mano: `tests/motor_original.mjs` son los
tramos de `rotacion_1.html` recortados textualmente. Si la comparación pasa, es
contra el código de verdad del cliente, no contra una interpretación mía.

## Diferencias deliberadas respecto del original

Tres, y las tres son correcciones:

**1. Índice IPC para fechas anteriores al inicio de la serie.**
El original, al no encontrar el mes exacto, devolvía el índice de *hoy*
(`ipcIndiceEnMes` → `indiceHoy()`). Eso hace que un auto comprado antes del
inicio de la serie se trate como si se hubiera comprado hoy: ajuste por
inflación cero, justo en el caso donde más importa. El SQL toma el índice más
antiguo disponible. Con los datos actuales no cambia ningún número (todos los
vehículos caen dentro de la serie), pero evita un error silencioso cuando se
carguen unidades viejas.

**2. Días en stock.**
El original hacía `Math.round((hoy - ingreso) / 86400000)`, con `hoy` incluyendo
la hora. Después del mediodía redondeaba para arriba, así que una unidad podía
mostrar 105 días a la mañana y 106 a la tarde. El SQL resta fechas calendario:
`current_date - fecha_ingreso`. Estable durante todo el día.

**3. Un vehículo no se puede vender dos veces.**
El original lo detectaba *después*, en `integrityChecks()`, listando
"Vehículos vendidos más de una vez". Ahora es un `unique` sobre
`ventas.vehiculo_id`: la base lo rechaza en el momento. Toda esa sección de
chequeos de integridad desaparece porque las condiciones que buscaba ya no
pueden ocurrir (IDs duplicados, gastos que apuntan a vehículos inexistentes,
etc. son claves primarias y foráneas).

## Lo que muestran los datos del cliente

Corriendo el motor sobre su planilla real, al 12/09/2026:

| | |
|---|---|
| Unidades en stock | 11 |
| Capital inmovilizado | $264.680.000 |
| Margen promedio actual | **8,4%** contra un objetivo de 30% |
| Unidades bajo el margen mínimo | **6 de 11** |
| Unidades en rojo (+90 días) | **7** |
| Días promedio en stock | 130,7 |
| Ganancia realizada nominal | $3.740.000 |
| Ganancia realizada ajustada por IPC | **$1.484.283** (USD 980) |

Las dos últimas filas son el argumento de venta del sistema: en pesos parece que
ganaron $3,7 millones, pero descontada la inflación del período ganaron menos de
la mitad. Un ERP que no ajusta por IPC en Argentina le miente al dueño.
