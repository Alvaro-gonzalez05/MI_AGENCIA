# Qué falta

Estado al 12/09/2026. Ordenado por lo que desbloquea más cosas.

Lo que **ya está terminado y verificado** está en [README.md](../README.md);
esto es sólo lo que falta.

---

## Bloqueante 1 — Crear la base en Supabase

Sin esto la app funciona, pero contra datos de ejemplo en memoria.

1. Logueate en Supabase con `alvarogonzalez7070@gmail.com`. **Yo intenté
   entrar y la sesión del navegador no estaba iniciada**; no puedo loguearme
   por vos ni resolver el captcha.
2. Creá el proyecto: nombre `mi-agencia`, región **South America (São Paulo)**.
3. Abrí el SQL Editor y pegá entero
   [`supabase/migraciones_completas.sql`](../supabase/migraciones_completas.sql).
   Son las 10 migraciones en orden, ya verificadas contra un Postgres real.
   Es idempotente: si lo corrés dos veces no rompe nada.
4. Copiá de *Project Settings → API* la **Project URL** y la **publishable key**
   (esa sí es pública, va en el cliente sin problema).

### Para que yo pueda trabajar contra la base

Generá un token en <https://supabase.com/dashboard/account/tokens> y guardalo
en una variable de entorno. **No lo pegues en el chat.**

```powershell
[Environment]::SetEnvironmentVariable('SUPABASE_TOKEN_MI_AGENCIA', 'TU_TOKEN', 'User')
```

El `.mcp.json` de la raíz ya está armado para leerlo de ahí. Abrí Claude con
la carpeta `mi-agencia` como directorio de trabajo y aprobá el servidor.

### Después, la app contra la base real

```powershell
.\scripts\dev.ps1 run -d chrome `
  --dart-define=SUPABASE_URL=https://xxx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx
```

Con esas dos variables el modo demo se apaga solo.

### Crear la cuenta de desarrollador

El flag de desarrollador no se puede activar desde la app (lo impide un
trigger, a propósito). Registrate normalmente y después, una sola vez desde el
SQL Editor:

```sql
update public.perfiles set es_desarrollador = true
 where email = 'alvarogonzalez7070@gmail.com';
```

---

## Bloqueante 2 — Windows (necesita administrador)

`flutter build windows` todavía falla. Faltan dos cosas y las dos piden
permisos de administrador, por eso no las pude hacer yo:

**Modo Desarrollador** (Flutter lo exige para los symlinks de plugins):

```powershell
start ms-settings:developers
```

**Visual Studio con C++** (~7-10 GB en `C:`):

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

> ⚠️ **Liberá espacio antes.** Quedan **11,4 GB libres en `C:`**. Si te quedás
> sin disco a mitad de la instalación de Visual Studio, el arreglo es peor que
> el problema.

Después:

```powershell
.\scripts\dev.ps1 build windows --release
```

Android y web **no necesitan nada de esto** y ya funcionan.

---

## Lo que falta programar

### Pantallas (la navegación ya existe, cada una explica en pantalla qué va a hacer)

| Pantalla | Qué falta |
|---|---|
| **Vehículos** | Formulario de alta/edición. Autocompletado contra `ref_catalogo`. Subida de fotos a Storage. |
| **Gastos** | Alta por unidad con las 10 categorías. Adjuntar comprobante. |
| **Precios** | Alta de cambio de precio. Gráfico de evolución vs. costo. |
| **Ventas** | Registro de venta. Al guardarla la unidad sale del stock (ya lo hace un trigger). |
| **Campañas** | Editor, segmentación y envío. |
| **Configuración** | Formulario sobre `agencia_config` + gestión de usuarios. |
| **Agencias** | Panel de desarrollador: alta de agencias e invitaciones. |

### Repositorio contra Supabase

`lib/datos/repositorio.dart` tiene la interfaz y la implementación demo.
`RepositorioSupabase` está declarada pero sin implementar: cada método es un
select sobre las vistas que ya existen (`v_inventario`, `v_dashboard`,
`v_clientes_semaforo`). Al conectarlo **no hay que tocar ninguna pantalla**.

### Edge Functions (ninguna escrita todavía)

| Función | Qué hace | Estado de la API |
|---|---|---|
| `bcra-consulta` | Consulta la Central de Deudores por CUIT y llena `bcra_consultas` | Verificada en vivo: devuelve situación 1-6, montos, días de atraso y banderas de juicio |
| `sync-catalogo` | Espeja el catálogo de ArgAutos, mensual | Verificada. **Falta la API key** (pedila gratis en argautos.com) |
| `sync-indices` | Actualiza IPC del INDEC y cotización del dólar | Por integrar |
| `enviar-campana` | Envío de emails | Falta elegir proveedor (Resend o Brevo) |

El BCRA no manda cabeceras CORS y ArgAutos limita por IP: las dos **tienen** que
consumirse desde Edge Functions, nunca desde la app.

### Detalles chicos

- **El tema no se recuerda** al cerrar la app. Falta `shared_preferences`.
- **Sin gráficos todavía**: el panel muestra una barra apilada de antigüedad,
  pero falta la evolución mensual. `Motor.evolucion()` ya calcula los datos.
- **Sin ícono ni splash** propios: está el de la plantilla de Flutter.
- **Sin firma de release** para Android: el APK sale firmado con la clave de
  debug. Para subir a Play Store hay que generar un keystore.

---

## Decisiones que te tocan a vos

1. **Proveedor de email**: Resend (3.000/mes gratis, más simple) o Brevo
   (300/día gratis, con editor visual). Cambia cómo se escribe `enviar-campana`.
2. **API key de ArgAutos**: sin ella el catálogo no se puede espejar.
3. **Plan de Supabase**: el free tier pausa proyectos inactivos y tiene 500 MB
   de base. Para un cliente real conviene Pro (USD 25/mes) — decidilo con él y
   metelo en el presupuesto.
4. **Nombre e identidad visual**: hoy es "Mi Agencia" con un ícono genérico de
   auto. Si el cliente tiene marca, se aplica sobre los tokens de color.

---

## Cómo verificar que no rompiste nada

```powershell
.\scripts\dev.ps1 analyze     # 0 problemas
.\scripts\dev.ps1 test        # 14 tests
cd tests; npm test            # migraciones + paridad del motor con el original
```

El último es el importante: aplica las 10 migraciones a un Postgres real y
compara 273 valores calculados contra el JavaScript original del cliente. Si
tocás una fórmula del SQL y se rompe la paridad, ahí saltás.
