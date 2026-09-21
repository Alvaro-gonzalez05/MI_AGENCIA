# Respuesta al checklist de revisión — Tanda 2

De: equipo de desarrollo
Para: Juan Cruz
21/09/2026 · sobre el checklist del 21/09/2026

---

## 2.1 · La ganancia real se ajusta por dólar, desde la fecha de compra — CRÍTICO

**Resuelto, con tu ejemplo del Corolla como prueba automática.**

Ahora se calcula exactamente como lo pediste:

1. El precio de compra se pasa a dólares al **oficial (venta) del día de la
   compra**.
2. Cada gasto se pasa a dólares al oficial **del día de ese gasto**.
3. La suma en dólares se trae a pesos al dólar **de hoy** (o, si la unidad ya
   se vendió, al del **día de la venta**).
4. Ganancia real = precio − ese costo. Margen real = ganancia real ÷ precio.

La **fecha de ingreso** sigue mandando para los días en stock y las alertas de
rotación: eso no cambió.

Tu ejemplo da exactamente lo que calculaste:

| | |
|---|---|
| Compra $8.500.000 el 10/05/2024 (dólar $901,5) | USD 9.428,73 |
| Gastos $600.000 el 20/01/2025 (dólar $1.066) | USD 562,85 |
| Costo a valor de hoy (USD) × $1.535 | **$15.337.078** |
| Venta $14.500.000 el 18/09/2026 | |
| **Ganancia real (USD)** | **−$837.078** |
| **Margen real (USD)** | **−5,8 %** |

**Tres decisiones que tomamos y conviene que sepas:**

- **Unidad vendida → dólar del día de la venta y precio de venta real.** Si
  no, la ganancia de un auto vendido hace un año seguiría moviéndose con el
  dólar de hoy. Tu ejemplo usa $1.535, que es justamente el del 18/09.
- **Gastos de cierre** (los que se cargan al vender): son del día de la venta,
  así que a dólar de ese día valen lo mismo y entran en pesos.
- **Fin de semana o feriado**: se usa el último día hábil anterior.

**La cotización se actualiza sola, una vez por día** (18:30, después del
cierre del BNA), desde argentinadatos.com, que publica la serie oficial desde
2011. Ya está cargada completa: más de 5.700 días. La misma sincronización
mantiene al día el oficial, blue, MEP, CCL, mayorista y tarjeta, así que el
tipo de cambio de la configuración también deja de ser un número fijo.

Las etiquetas quedaron **"Ganancia real (USD)"**, **"Margen real (USD)"** y
**"Costo a valor de hoy (USD)"**. El IPC se sigue sincronizando como dato
informativo, pero ya no entra en ninguna ganancia.

> **Para tener en cuenta al cargar:** la fecha de compra ahora pesa mucho.
> Un auto cargado con una fecha de compra vieja y un precio de hoy va a
> mostrar una pérdida enorme, porque el sistema entiende que esos pesos
> valían muchos más dólares en esa fecha. Si un número se ve raro, lo primero
> es revisar la fecha y el precio de compra.

---

## 2.2 · Simulador: sacar el anticipo — IMPORTANTE

**Resuelto.** Queda solo el **monto a financiar**, que arranca en el precio
publicado y se escribe a mano. Se fueron los atajos de anticipo, la línea
"Anticipo del comprador" y el "Total con anticipo". Cuotas y tasa, igual que
antes.

---

## 2.3 · Campañas: "Requested function was not found" — IMPORTANTE

**Resuelto del lado del sistema; falta un paso tuyo.**

El error era literal: la función que manda los mails nunca se había subido al
servidor. Ya está subida. Además:

- Si falta configurar el envío, la app ahora lo dice en castellano ("El envío
  de mails todavía no está configurado…") y la campaña queda como borrador.
- Si Resend rechaza todo el envío, la campaña **vuelve a borrador** para
  reintentarla. Antes quedaba "enviada" con cero mails y no había forma de
  reenviarla.
- `{{agencia}}` en el texto del mail ponía el nombre de la campaña; ahora pone
  el de la agencia.
- Las respuestas de los clientes llegan al **email de contacto de la agencia**.

**Lo que falta** es crear la cuenta de Resend, verificar el dominio y cargar
dos datos en Supabase. Está todo paso a paso en
[EMAIL_MARKETING.md](EMAIL_MARKETING.md).

---

## 2.4 · Informe crediticio: detalle por entidad y por mes — IMPORTANTE

**Resuelto.** El PDF ahora tiene, para **cada** banco, financiera o tarjeta,
una tabla con sus meses de los últimos 24:

| Mes | Sit. | Significado | Monto adeudado | Gestión judicial | En revisión |
|---|---|---|---|---|---|

Las entidades van de la peor situación a la mejor. La sección de cheques
rechazados aparece siempre: con la tabla si hay, o con "El BCRA no informa
cheques rechazados a su nombre" si no hay.

Las consultas que ya estaban guardadas **también** tienen el detalle: se
rearmó a partir de la respuesta del BCRA que ya estaba archivada, sin volver
a consultar.

Los datos de fuentes pagas (ARCA, ANSES, bienes, score) quedan fuera, como
indicaste.

> **Aviso legal, para consultar con un abogado:** guardar información
> crediticia de terceros es tratamiento de datos personales. La Ley 25.326
> exige inscribir esa base de datos en el Registro de la Agencia de Acceso a
> la Información Pública (AAIP). Es un trámite, no un impedimento, pero
> conviene hacerlo antes de usar el sistema con clientes reales.

---

## Cómo se verificó

- **220 pruebas automáticas** de la app y **7 suites** contra un Postgres
  real, entre ellas tu ejemplo del Corolla tanto en la base (`tests/dolar.mjs`)
  como en el motor de la app (`ganancia_dolar_test.dart`).
- La migración del dólar se aplicó en la base real y la serie se cargó y
  comprobó contra tus cuatro cotizaciones de ejemplo (901,5 · 1.061,5 ·
  1.066 · 1.535).
- El PDF se generó y se revisó página por página con un caso de tres
  entidades y 24 meses (datos inventados: no hay personas reales en el
  repositorio).
