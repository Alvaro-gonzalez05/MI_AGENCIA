# Respuesta al checklist de revisión — Tanda 1

De: equipo de desarrollo
Para: Juan Cruz
19/09/2026 · sobre el checklist del 18/09/2026

Los siete puntos, uno por uno: qué pasaba, qué se hizo y cómo comprobarlo.

---

## 1.1 · El ajuste por inflación (IPC) no descontaba nada — CRÍTICO

**Resuelto, con una aclaración.**

En la prueba había dos cosas mezcladas.

La primera explica el cero que viste: los autos estaban cargados con **fecha
de ingreso de hoy**. El ajuste se cuenta desde que la unidad entró al stock
—como lo hacía el sistema original y como lo pide el propio checklist ("desde
la fecha en que el auto entró al stock")— y de hoy a hoy la inflación es cero.
Si cargás un auto con fecha de ingreso de hace meses, el número aparece.

> Si lo que se quiere es ajustar desde la **fecha de compra** en vez de la de
> ingreso, se cambia en una línea. Son dos criterios distintos y vale la pena
> definirlo: la fecha de compra es cuándo saliste la plata, la de ingreso es
> desde cuándo la unidad ocupa lugar en el predio.

La segunda es un problema de fondo que iba a aparecer igual: **la serie del
IPC no se actualizaba**. Arrancaba en julio de 2025 (un auto que entró antes
perdía toda la inflación anterior) y terminaba en agosto de 2026, así que
cualquier auto que entrara de ahí en adelante iba a mostrar inflación cero
para siempre.

Ahora la base se conecta sola a la serie oficial del INDEC (IPC nivel general
nacional, publicado gratis en datos.gob.ar) y se sincroniza **todos los días a
las 8**. Ya corrió la primera carga: 117 meses, de diciembre de 2016 a agosto
de 2026. El índice de agosto coincide al milésimo con el del INDEC.

El INDEC publica con mes y medio de atraso, así que **el mes en curso se
estima** con la última variación publicada y queda marcado como estimación;
cuando sale el dato real, se reemplaza solo. Sin eso, un auto que entró en
agosto mostraría inflación cero hasta mediados de octubre.

La otra mitad del pedido ya estaba y sigue: **cada gasto se ajusta desde su
propia fecha**, no desde la fecha de compra del auto.

**Cómo probarlo:** cargá un auto con fecha de ingreso de hace varios meses,
un gasto de esa misma época y otro del mes pasado. "Ganancia real (IPC)" tiene
que quedar por debajo de la nominal, y el gasto viejo ajustarse más que el
reciente. Es exactamente lo que verifica `tests/ipc.mjs`.

---

## 1.2 · Las ventas no se podían editar ni eliminar — IMPORTANTE

**Resuelto.** Cada venta tiene ahora un menú con dos acciones:

- **Corregir datos**: abre el mismo formulario, precargado. La unidad queda
  fija: cambiarle el auto a una venta es anularla y cargar otra.
- **Anular venta**: pide confirmación explicando qué va a pasar. La unidad
  vuelve al inventario como **En stock** y la venta deja de contar en la
  ganancia y en los históricos.

Anular lo pueden hacer el dueño o un administrador. Un vendedor recibe un
aviso claro en vez de un error técnico.

---

## 2.1 · Falta el VALOR DE REVISTA y su comparación — PENDIENTE

**Sigue pendiente, pero ya sabemos de dónde sacarlo.** El cálculo y la
comparación porcentual ya están hechos en la base; lo que falta son los datos.

Lo que se revisó:

| Fuente | Costo | Se puede usar |
|---|---|---|
| **ArgAutos** (la API que veníamos mirando) | Pago | Sí, pero hay que pagarla |
| **Guía Oficial de Precios de ACARA** (la "revista") | Consulta web gratis | **No.** La propia página prohíbe expresamente reproducir su información, total o parcialmente |
| **Tabla de valuación del DNRPA** | Gratis | **Sí** |
| datos.gob.ar | Gratis | No publica precios de autos, solo estadísticas de trámites |

La opción viable es la **tabla de valuación del DNRPA**: es la que usan los
registros para cobrar transferencias y patentamientos. La publica el Estado
todos los meses, en PDF, con dirección predecible
(`dnrpa.gov.ar/valuacion/informacion/01-08-2026.pdf`). Ya la bajamos y la
abrimos para ver si servía: 217 páginas, y el texto sale ordenado —marca,
modelo, versión y precio para cada año, de 0 km hasta 2002—, así que se puede
importar sola una vez por mes, igual que el IPC.

**La advertencia honesta:** el valor del DNRPA es **fiscal**, no de mercado.
Suele estar por debajo de lo que pide la revista de ACARA. Sirve como
referencia oficial y gratuita, y como piso de negociación, pero no es lo mismo
que el valor de revista.

Las opciones, para decidir:

1. **Importar la tabla del DNRPA** (gratis, automático, mensual) y mostrarla
   como "valor de referencia DNRPA" junto al precio publicado.
2. **Cargar el valor de revista a mano** en cada unidad, consultándolo en la
   web de ACARA. Sin costo y con el valor exacto que usa la agencia, pero es
   trabajo manual por auto.
3. **Pagar ArgAutos** y tener el valor de mercado automático.

Se pueden combinar: el DNRPA automático de base, y el campo manual para
pisarlo cuando la agencia quiera el valor de revista exacto. Decidilo vos y lo
implementamos.

---

## 2.2 · Simulador: faltaba el monto a financiar — MEJORA

**Resuelto.** El monto a financiar es editable, con atajos de anticipo (sin
anticipo, 20%, 30%, 50%). Debajo quedan el anticipo del comprador y, cuando lo
hay, el **total con anticipo**: lo que termina pagando por el auto.

El monto se acota al precio publicado, así que el anticipo nunca da negativo.
La tasa y el interés directo no se tocaron.

---

## 2.3 · Otros sistemas de amortización (francés, alemán) — A FUTURO

**Anotado, no hecho**, como pediste.

---

## 3.1 · El semáforo del BCRA no traía los datos reales — CRÍTICO

**Resuelto, y era grave.** Gracias por probarlo contra la web del BCRA: sin
ese dato no lo hubiéramos encontrado.

La causa: la Central de Deudores tiene **tres** consultas y la app usaba dos.
`/Deudas` devuelve **solo el último mes informado**. La persona del reclamo
estuvo en **situación 5 (irrecuperable) de agosto a diciembre de 2024** y en
situación 4 hasta marzo de 2025; desde abril de 2025 figura sin deuda. Como
hoy no debe nada, esa consulta contesta "no se encontraron datos", y la app lo
leía como limpio. La web oficial muestra los **24 meses**, y ahí se ve todo.

Ahora se consultan las tres, incluido el historial, y el semáforo lo tiene en
cuenta:

- **Rojo**: situación 4 o peor en los últimos **12 meses**, aunque hoy esté al día.
- **Amarillo**: situación 3 o peor en los últimos **24 meses**.
- **Verde**: también si hoy no debe nada y en 24 meses nunca pasó de situación 2.

Ese caso ahora sale **amarillo**, con el motivo escrito: *"En los últimos 24
meses estuvo en situación 5 (irrecuperable)"* y *"Hoy no registra deudas: está
al día desde abril 2025"*.

En la ficha aparece una **línea de tiempo de 24 meses**, un cuadradito por mes
pintado según la peor situación de ese mes, y el PDF la lleva igual, más una
tarjeta "Peor en 24 meses". "Sin deudas informadas" ahora significa nada hoy
**y** nada en 24 meses.

Las consultas hechas antes de este cambio se dieron por vencidas: alguna puede
estar diciendo "sin deudas" de alguien que sí tuvo. **Volvé a consultar a esa
persona** y vas a ver el historial.

> Los umbrales de 12 y 24 meses son una decisión de política crediticia, no
> una regla del BCRA. Si querés que situación 5 en 24 meses sea rojo directo,
> o que 12 meses sean 18, se cambia.

---

## 4.1 · El email marketing no tomaba los interesados — IMPORTANTE

**Resuelto.** El alta guardaba **siempre** "no acepta mails", y ninguna
pantalla dejaba cambiarlo: todo interesado cargado desde la app quedaba afuera
de las campañas para siempre. Encima, la pantalla decía "ningún interesado
tiene email cargado", que era falso y parecía un error del sistema.

No se arregla marcando que todos aceptan: mandarle mails a quien no lo aceptó
es spam, quema la reputación del dominio y choca con la ley de datos
personales. Se pregunta:

- El alta tiene el interruptor **"Acepta recibir novedades por email"**, que
  solo se habilita si hay un email cargado.
- La ficha deja cambiarlo para los interesados que ya estaban. Al sacarlo
  queda registrada la fecha de la baja.
- Campañas explica el cero: *"Hay 1 interesado con email, pero no aceptó
  recibir novedades. Se marca en la ficha de cada uno"*.

**Para que tu interesado de prueba entre en una campaña**, abrí su ficha y
activá ese interruptor.

---

## Cómo se verificó

- **183 pruebas automáticas** de la app y **4 suites** contra un Postgres real,
  incluidas las del caso concreto de cada punto del checklist.
- El semáforo con historial se probó contra la **respuesta real del BCRA** del
  CUIL del reclamo, sin guardar esos datos en el repositorio.
- Las correcciones de ventas y el consentimiento se probaron **en la base real,
  con el usuario y con los permisos puestos**, dentro de transacciones que se
  abortan al final: quedó comprobado que funcionan y no se guardó ni una fila
  de prueba.
