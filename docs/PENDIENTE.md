# Qué falta

Estado al 13/09/2026. Ordenado por lo que desbloquea más cosas.

Lo que **ya está terminado y verificado** está en [README.md](../README.md);
esto es sólo lo que falta.

---

## Lo primero que tenés que hacer: cargar 3 secretos en GitHub

El código ya está en <https://github.com/Alvaro-gonzalez05/MI_AGENCIA>, y los
workflows compilan los instaladores solos. Pero para que la app salga apuntando
a tu base y no en modo demo, faltan dos valores.

**Settings → Secrets and variables → Actions → New repository secret**, tres veces:

| Nombre | Valor |
|---|---|
| `SUPABASE_URL` | `https://zthpwqcoirrpvslambhz.supabase.co` |
| `SUPABASE_ANON_KEY` | la publishable key (`sb_publishable_...`) |
| `SUPABASE_SERVICE_ROLE_KEY` | la secret key (`sb_secret_...`) o la `service_role` legacy. Supabase → Project Settings → API Keys |

Las dos primeras son públicas por diseño (viajan dentro de la app), pero van
como secretos igual: así cambiar de proyecto no obliga a tocar código.

La tercera **no es pública**: da acceso total al proyecto. Solo la usa el
workflow para subir los instaladores a Storage; nunca entra en la app.

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

### Actualizaciones automáticas (desde la 0.3.0)

Al terminar, el workflow sube los instaladores al bucket público
`instaladores` de Supabase Storage y reescribe `instaladores/ultima.json`. Las
apps instaladas lo consultan al abrir y cada 6 horas; si hay una versión más
nueva muestran un aviso con el botón **Actualizar**:

- **Windows**: baja el instalador, lo corre en silencio, la app se cierra y
  se vuelve a abrir actualizada.
- **Android**: abre la descarga del APK; el usuario confirma la instalación.

Para que una versión sea **obligatoria** (la app no deja seguir hasta
actualizar), publicala con un tag anotado que diga `[obligatoria]`. El resto
del mensaje aparece como notas en el aviso:

```bash
git tag -a v0.4.0 -m "[obligatoria] Cambios en la base de datos"
git push origin v0.4.0
```

Sin el secreto `SUPABASE_SERVICE_ROLE_KEY` la versión igual se publica en
GitHub, pero las apps instaladas no se enteran.

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
| ~~**Precios**~~ | **Hecho.** Falta el gráfico de evolución del precio contra el costo. |
| ~~**Ventas**~~ | **Hecho.** |
| ~~**Campañas**~~ | **Hecho.** Falta desplegar la Edge Function y cargar la API key de Resend. |
| ~~**Configuración**~~ | **Hecho.** Falta la gestión de usuarios de la agencia. |
| ~~**Agencias**~~ | **Hecho.** |
| ~~**Interesados**~~ | **Hecho, incluido el semáforo del BCRA y el informe en PDF.** |

**Las 10 secciones tienen pantalla real.** Ya no queda ninguna de relleno.

### Interesados y semáforo crediticio — terminado

La lista filtra por color y muestra en qué punto está cada persona (sin CUIT,
con CUIT sin consultar, consultada, consulta vencida). Al tocarla se abre la
ficha, que es donde pasa todo:

- Se escribe el CUIT o CUIL y el botón **Consultar BCRA** lo valida (dígito
  verificador incluido) antes de gastar la consulta.
- El semáforo sale grande, con la recomendación escrita y la lista de motivos
  por los que dio ese color.
- Abajo, el desglose entidad por entidad (situación 1 a 6, deuda, días de
  atraso, refinanciaciones, juicio) y los cheques rechazados, separando los
  pagados de los que siguen impagos.
- **Descargar informe** arma un PDF con todo lo que la agencia sabe de la
  persona más el detalle del BCRA. En Windows abre el visor; en Android, la
  hoja de compartir, que es como se manda por WhatsApp.

La consulta se cachea 30 días porque el BCRA publica una vez por mes; el botón
**Volver a consultar** saltea el caché cuando la persona regularizó.

Un detalle que importa: el BCRA contesta 404 tanto para "no existe" como para
"no tiene deudas informadas". El sistema los distingue — consultado y sin
deudas es **verde**, nunca consultado es **sin datos** — y el informe aclara
que alguien sin historial crediticio no es lo mismo que alguien que cumple.

### Repositorio contra Supabase — hecho

`lib/datos/repositorio_supabase.dart` ya lee de `v_inventario`,
`agencia_config`, `oportunidades` y `v_clientes_semaforo`. No hizo falta tocar
ninguna pantalla: hablan con la interfaz, no con Supabase.

La **escritura** ya está para vehículos, gastos, precios y ventas. Falta la de
campañas, configuración y agencias.

### Edge Functions

| Función | Qué hace | Estado |
|---|---|---|
| `bcra-consulta` | Consulta la Central de Deudores por CUIT y llena `bcra_consultas` | **Desplegada y andando.** Probada contra CUIT reales |
| `sync-catalogo` | Espeja el catálogo de ArgAutos, mensual | Verificada. **Falta la API key** (pedila gratis en argautos.com) |
| `sync-indices` | Actualiza IPC del INDEC y cotización del dólar | Por integrar |
| `enviar-campana` | Envío de emails por Resend | **Escrita.** Falta desplegarla y cargar `RESEND_API_KEY` |

El BCRA no manda cabeceras CORS y ArgAutos limita por IP: las dos **tienen** que
consumirse desde Edge Functions, nunca desde la app.

### Detalles chicos

- **El tema no se recuerda** al cerrar la app. Falta `shared_preferences`.
- **`flutter pub get` en tu máquina avisa de symlinks** desde que entró
  `printing` (el paquete del PDF): sin Modo Desarrollador, Windows no deja
  crear los symlinks que Flutter usa para los plugins nativos. Las
  dependencias se instalan igual y `analyze`/`test` andan; sólo afecta a
  `flutter build windows` local, que ya no corría por otros motivos. En el
  runner de GitHub no pasa.
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
.\scripts\dev.ps1 test        # 121 tests
cd tests; npm test            # esquema + semáforo + paridad del motor
```

El último es el importante. Aplica las 13 migraciones a un Postgres real y:

- compara **247 valores** calculados contra el JavaScript original del cliente;
- corre el **semáforo crediticio** contra la base y contra el código de la app,
  con los mismos casos (`tests/casos_semaforo.json`), para que las dos
  implementaciones no se separen sin que nadie se entere;
- verifica que `supabase/migraciones_completas.sql` esté al día con las
  migraciones sueltas.

Si tocás una fórmula del SQL y se rompe la paridad, ahí saltás.
