# Qué falta

Estado al 13/09/2026. Ordenado por lo que desbloquea más cosas.

**La base quedó vacía y lista para cargar.** Se borraron los datos de
ejemplo (13 unidades, gastos, precios, ventas e interesados) y quedó la
agencia, tu usuario, los umbrales del motor, la serie IPC y las
cotizaciones. El primer código de unidad vuelve a ser V001.

Lo que **ya está terminado y verificado** está en [README.md](../README.md);
esto es sólo lo que falta.

---

## Los secretos de GitHub: ya están cargados

Verificado sobre el APK publicado de la 0.3.1: trae adentro la URL del
proyecto y la publishable key, así que la app instalada habla con la base
real y no está en modo demo. Los tres secretos son:

| Nombre | Para qué |
|---|---|
| `SUPABASE_URL` | a qué proyecto apunta la app |
| `SUPABASE_ANON_KEY` | la publishable key (`sb_publishable_...`) |
| `SUPABASE_SERVICE_ROLE_KEY` | solo el workflow, para subir los instaladores a Storage |

Las dos primeras son públicas por diseño: viajan dentro de la app y el RLS es
lo que protege los datos, no el secreto de la key. Comprobado: sin sesión, esa
key no puede leer ni una fila de `vehiculos` ni de `v_inventario`.

La tercera **no es pública**: da acceso total al proyecto y nunca entra en la
app.

Si alguna vez faltaran, el build no falla: sale en modo demo contra los datos
de ejemplo.

## Publicar una versión

```bash
git tag v0.5.0
git push origin v0.5.0
```

Eso dispara el workflow, que compila y publica en Releases:

- `MiAgencia-Setup-0.5.0.exe` — instalador de Windows
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

La 0.5.0 inaugura la firma Android estable. Cualquier APK anterior era una
prueba firmada por un runner descartable: hay que desinstalarlo una única vez.
Desde la 0.5.0 las actualizaciones se instalan encima sin perder esa identidad.
La clave se guarda en secretos de GitHub y su respaldo local está fuera del repo,
en `%USERPROFILE%\.mi-agencia`.

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
| ~~**Configuración**~~ | **Hecho**, incluidos los datos de la agencia (nombre, CUIT, contacto). Falta la gestión de usuarios. |
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
- **`v_dashboard` devuelve nulos con la agencia vacía** (los `sum()` sobre cero
  filas). Hoy no molesta porque la app calcula los totales en Dart desde el
  inventario y no lee esa vista; si alguna vez se lee, hay que ponerle
  `coalesce`.
- **`flutter pub get` en tu máquina avisa de symlinks** desde que entró
  `printing` (el paquete del PDF): sin Modo Desarrollador, Windows no deja
  crear los symlinks que Flutter usa para los plugins nativos. Las
  dependencias se instalan igual y `analyze`/`test` andan; sólo afecta a
  `flutter build windows` local, que ya no corría por otros motivos. En el
  runner de GitHub no pasa.
- **Sin gráficos todavía**: el panel muestra una barra apilada de antigüedad,
  pero falta la evolución mensual. `Motor.evolucion()` ya calcula los datos.
- ~~**Sin ícono propio**~~ **Hecho.** La "M" de Mi Agencia en la tipografía de
  la app sobre negro, con el punto del semáforo. Lo dibuja
  `scripts/generar_icono.py` dibuja el auto dentro de la agencia y lo baja a todos los tamaños
  `dart run flutter_launcher_icons`, así que retocarlo es cambiar un número y
  correr dos comandos, no exportar catorce archivos a mano. Incluye el ícono
  adaptativo de Android (el que el launcher recorta en círculo o gota).
- **Sin splash** propio: está el de la plantilla de Flutter.
- ~~**Sin firma de release**~~ **Resuelto desde 0.5.0.** GitHub usa un keystore
  estable; los cuatro valores necesarios viven como secretos del repositorio.
  Para Play Store se puede reutilizar esta identidad o adoptar Play App Signing.
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
.\scripts\dev.ps1 test        # 142 tests
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

---

## Cómo se ve el paso de una sección a otra

Antes la pantalla nueva entraba con un fundido **encima** de la vieja, y durante
un instante se veían las dos encimadas. Eso es lo que se sentía tosco.

La causa, medida y no supuesta: al saltar entre secciones hermanas, go_router
**reemplaza** la ruta, y la pantalla que se va no corre ninguna animación de
salida — se queda en opacidad 1 hasta que desaparece. Como las pantallas de
sección son transparentes (el fondo lo pone el shell), cualquier fundido de
entrada la deja asomando por debajo.

Se probó cruzarlas con un `AnimatedSwitcher` en el shell, para tenerlas bajo un
mismo controlador. No se puede: el hijo de un `ShellRoute` es un `Navigator` con
`GlobalKey`, y dos vivos a la vez revientan.

Así que ahora **entre secciones no hay animación de página**: el cambio es
instantáneo y el movimiento lo pone `Aparecer`, que escalona las tarjetas al
entrar (un poco más rápido que antes, porque ahora es la única animación que se
ve). La ficha de una unidad sí entra de costado, porque es una ruta hija y ahí
sí hay un push de verdad.

Está en `app/lib/core/transiciones.dart`, y lo que se afirma de todo esto está
en `app/test/transiciones_test.dart` — incluido el caso que lo causaba, para
que no vuelva.
