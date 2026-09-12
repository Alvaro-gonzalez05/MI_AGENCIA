# Entorno de desarrollo

Estado al 12/09/2026. Todo esto ya está instalado y verificado en la máquina.

| Herramienta | Versión | Dónde |
|---|---|---|
| Flutter | 3.47.4 stable (Dart 3.13.3) | `D:\dev\flutter` |
| JDK | Temurin 17.0.20.1 x64 | `D:\dev\jdk17` |
| Android SDK | build-tools 37, platform android-36.1 | `%LOCALAPPDATA%\Android\Sdk` |
| Android NDK | 28.2.13676358 | dentro del SDK |
| cmdline-tools | 19.0 (13114758) | dentro del SDK |
| Gradle | 9.3.1 (wrapper) | caché en `D:\dev\.gradle` |

Cachés redirigidas a `D:` (`PUB_CACHE`, `GRADLE_USER_HOME`) porque `C:` tiene poco
espacio libre.

## Cómo desarrollar

Siempre a través del lanzador, que configura el entorno:

```powershell
.\scripts\dev.ps1 run -d chrome         # app en el navegador, con hot reload
.\scripts\dev.ps1 run -d windows        # ventana nativa (requiere Visual Studio)
.\scripts\dev.ps1 build apk --debug     # APK
.\scripts\dev.ps1 doctor
```

Si preferís usar `flutter` suelto, cargá el entorno primero en esa terminal:

```powershell
. .\scripts\dev.ps1
```

---

## Los tres problemas que hubo que resolver

Quedan documentados porque ninguno es obvio y los tres vuelven si se cambia de
máquina o se reinstala.

### 1. `Unable to establish loopback connection` en Gradle

**Síntoma:** cualquier build de Android moría a los 4 segundos con ese mensaje.

**Causa real:** al fondo de la traza estaba
`java.net.SocketException: Invalid argument: connect` en
`sun.nio.ch.UnixDomainSockets.connect0`. El JDK abre el pipe interno de
`java.nio.channels.Selector` con un **socket AF_UNIX**, y en esta máquina las
conexiones a sockets AF_UNIX **creados dentro de
`C:\Users\ULTRABYTES\AppData\Local\Temp` fallan**. El `bind` funciona; el
`connect` no. Sobre `D:` funcionan los dos.

Se descartó por medición, no por intuición: Winsock está limpio (solo proveedores
de Microsoft, con AF_UNIX presente en el catálogo), el único antivirus es Windows
Defender, y falla igual fuera de cualquier sandbox. La causa de fondo —
probablemente un filtro de sistema de archivos sobre esa carpeta — sigue sin
identificarse; lo que está identificado es la condición exacta que lo dispara.

**Solución:** `TEMP` y `TMP` apuntando a `D:\dev\tmp`.

**El detalle que hace perder tiempo:** `-Djava.io.tmpdir` **no alcanza**. El JDK
ubica ese socket leyendo la *variable de entorno* `TEMP`, no la propiedad de Java.
Con `-Djava.io.tmpdir=D:\dev\tmp` el `Selector.open()` seguía fallando; con
`$env:TEMP='D:\dev\tmp'` funcionó.

> Esto rompe cualquier programa Java que use NIO en esta máquina, no solo Gradle.

### 2. `sdkmanager.bat` crasheando con 0xC0000409

Las `cmdline-tools` **16.1** (la versión que Google publica como "latest") traen un
`sdkmanager` deprecado que es un shim del nuevo CLI `android`. Cuando el Android
Gradle Plugin lo invoca para instalar componentes, revienta con
`STATUS_STACK_BUFFER_OVERRUN`.

**Solución:** se instalaron las `cmdline-tools` **19.0** (build 13114758), cuyo
`sdkmanager` funciona. La 16.1 quedó guardada como `cmdline-tools\v16-deprecado`
por si se necesita el CLI `android` nuevo.

### 3. Faltaba el NDK

AGP 9.1 con `ndkVersion` declarado exige el NDK aunque la app sea Dart puro.
Se instaló `ndk;28.2.13676358` (2,12 GB).

---

## Pendiente: Visual Studio para el `.exe` de Windows

`flutter build windows` falla con *"Unable to find suitable Visual Studio
toolchain"*. En la máquina hay **Visual Studio Build Tools 2019 16.11** pero sin
la carga de trabajo de C++.

Requiere permisos de administrador, así que hay que correrlo a mano:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

Ocupa unos 7-10 GB **en `C:`**, y ahí está el problema: quedan **11,4 GB libres**.
Conviene liberar espacio antes. Android y web no necesitan nada de esto.

## Ojo con el espacio en C:

Instalar el toolchain bajó `C:` de 18,7 a 11,4 GB libres. El NDK explica 2,12 GB;
el resto son artefactos de build, que viven en `app/build/` — y el proyecto está en
`C:\Users\ULTRABYTES\Desktop\PROYECTOS`. Si el disco aprieta, mover el repo a `D:`
resuelve eso de raíz.
