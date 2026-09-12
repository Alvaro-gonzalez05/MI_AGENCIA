# Qué falta

Estado al 12/09/2026. Ordenado por lo que desbloquea más cosas.

Lo que **ya está terminado y verificado** está en [README.md](../README.md);
esto es sólo lo que falta.

---

## Bloqueante 1 — Crear el primer usuario

La base **ya está creada y conectada**. Proyecto `zthpwqcoirrpvslambhz`, con las
10 migraciones aplicadas y verificadas (25 tablas, 6 vistas, 65 políticas RLS,
ninguna vista sin `security_invoker`).

La app ya apunta ahí: las credenciales están en `.env` (que no se commitea) y
`scripts/dev.ps1` las inyecta solo. Falta una sola cosa para poder entrar.

### Crear el usuario

El registro por email está habilitado pero **exige confirmación por mail**, y el
SMTP que trae Supabase de fábrica tiene un límite muy bajo. Así que el primer
usuario conviene crearlo a mano:

**Dashboard → Authentication → Users → Add user**, y tildá **Auto Confirm User**.

### Convertirlo en cuenta de desarrollador

El flag no se puede activar desde la app: lo impide un trigger, a propósito
(si viviera en los metadatos del usuario, cualquiera con la publishable key
podría intentar escribírselo). Una sola vez, desde el SQL Editor:

```sql
update public.perfiles set es_desarrollador = true
 where email = 'TU_EMAIL';
```

Con eso entrás y ves la sección **Agencias**, que es la de administración de
cuentas cliente.

### Para que yo administre la base por MCP

Esto es **opcional**. Sólo hace falta si querés que yo cree agencias, corra
migraciones nuevas o consulte la base directamente. Para programar la app no lo
necesito.

1. <https://supabase.com/dashboard/account/tokens> → **Generate new token**.
2. Cargalo en una variable de entorno (**no lo pegues en el chat**):

   ```powershell
   [Environment]::SetEnvironmentVariable('SUPABASE_TOKEN_MI_AGENCIA', 'TU_TOKEN', 'User')
   ```

3. Cerrá Claude y volvé a abrirlo **con la carpeta `mi-agencia` como directorio
   de trabajo**. El `.mcp.json` de la raíz lo levanta solo y te va a pedir que
   apruebes el servidor.

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

### Repositorio contra Supabase — hecho

`lib/datos/repositorio_supabase.dart` ya lee de `v_inventario`,
`agencia_config`, `oportunidades` y `v_clientes_semaforo`. No hizo falta tocar
ninguna pantalla: hablan con la interfaz, no con Supabase.

Queda pendiente la **escritura** (altas y ediciones), que llega junto con los
formularios de cada pantalla.

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
- **El APK pesa 51,5 MB** porque incluye las tres arquitecturas en un solo
  archivo. Con `--split-per-abi` salen tres de ~20 MB, y Play Store elige la
  que corresponde. Para repartir el APK a mano conviene el universal.

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
