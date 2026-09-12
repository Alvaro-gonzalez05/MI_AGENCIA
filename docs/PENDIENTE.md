# Qué falta

Estado al 12/09/2026. Ordenado por lo que desbloquea más cosas.

Lo que **ya está terminado y verificado** está en [README.md](../README.md);
esto es sólo lo que falta.

---

## Lo primero que tenés que hacer: cargar 2 secretos en GitHub

El código ya está en <https://github.com/Alvaro-gonzalez05/MI_AGENCIA>, y los
workflows compilan los instaladores solos. Pero para que la app salga apuntando
a tu base y no en modo demo, faltan dos valores.

**Settings → Secrets and variables → Actions → New repository secret**, dos veces:

| Nombre | Valor |
|---|---|
| `SUPABASE_URL` | `https://zthpwqcoirrpvslambhz.supabase.co` |
| `SUPABASE_ANON_KEY` | la publishable key (`sb_publishable_...`) |

Las dos son públicas por diseño (viajan dentro de la app), pero van como
secretos igual: así cambiar de proyecto no obliga a tocar código.

Si no los cargás, el build igual funciona: sale en modo demo contra los datos
de ejemplo.

## Publicar una versión

```bash
git tag v0.1.0
git push origin v0.1.0
```

Eso dispara el workflow, que compila y publica en Releases:

- `MiAgencia-Setup-0.1.0.exe` — instalador de Windows
- `MiAgencia-Windows-portable.zip` — para PCs sin permisos de instalación
- `MiAgencia-Android-arm64.apk` y `-arm32.apk`

Tarda unos 10-15 minutos. Se sigue desde la pestaña **Actions**.

## Windows: resuelto en la nube, pendiente en tu máquina

`flutter build windows` **no corre en tu PC** y no lo voy a poder arreglar yo:
faltan el Modo Desarrollador y Visual Studio con la carga de C++, y las dos
cosas piden permisos de administrador.

**Para la entrega ya no importa**: el runner de GitHub trae todo eso y compila
el instalador solo. Los `.exe` salen de ahí.

Sólo lo necesitás si querés correr la app de escritorio **localmente** mientras
desarrollás:

```powershell
start ms-settings:developers
```

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

> ⚠️ Visual Studio ocupa 7-10 GB **en `C:`**, y quedan **13,3 GB libres**.
> Liberá espacio antes: quedarse sin disco a mitad de esa instalación deja un
> problema peor.

Android y web funcionan sin nada de esto.

---

## Lo que falta programar

### Pantallas (la navegación ya existe, cada una explica en pantalla qué va a hacer)

| Pantalla | Qué falta |
|---|---|
| ~~**Vehículos**~~ | **Hecho.** Falta el autocompletado contra `ref_catalogo` (necesita la API key de ArgAutos) y las fotos a Storage. |
| ~~**Gastos**~~ | **Hecho.** Falta adjuntar el comprobante como foto o PDF. |
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
