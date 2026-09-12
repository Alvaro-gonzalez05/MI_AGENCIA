# =====================================================================
#  Mi Agencia — instalacion del toolchain Flutter en Windows
#
#  Instala todo en D: porque C: tiene poco espacio libre. Ejecutar en una
#  terminal PowerShell COMO ADMINISTRADOR:
#
#      powershell -ExecutionPolicy Bypass -File scripts\setup-flutter.ps1
#
#  Es idempotente: si algo ya esta instalado, lo saltea.
# =====================================================================

$ErrorActionPreference = 'Stop'
$DevRoot = 'D:\dev'

function Paso($texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }
function Ok($texto)   { Write-Host "  [ok] $texto" -ForegroundColor Green }
function Aviso($texto){ Write-Host "  [!]  $texto" -ForegroundColor Yellow }

Paso 'Verificando espacio en disco'
$d = Get-PSDrive D
$libresGB = [math]::Round($d.Free / 1GB, 1)
Write-Host "  D: tiene $libresGB GB libres"
if ($libresGB -lt 20) { throw "Hacen falta al menos 20 GB libres en D:. Hay $libresGB GB." }

Paso 'Creando carpetas en D:'
foreach ($p in @($DevRoot, "$DevRoot\.pub-cache", "$DevRoot\.gradle")) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}
Ok "$DevRoot listo"

# ---------------------------------------------------------------------
# Cachés fuera de C:. Se setean a nivel usuario para que sobrevivan al
# reinicio y las vean tanto la terminal como el IDE.
# ---------------------------------------------------------------------
Paso 'Redirigiendo cachés pesadas a D:'
[Environment]::SetEnvironmentVariable('PUB_CACHE',        "$DevRoot\.pub-cache", 'User')
[Environment]::SetEnvironmentVariable('GRADLE_USER_HOME', "$DevRoot\.gradle",    'User')
$env:PUB_CACHE        = "$DevRoot\.pub-cache"
$env:GRADLE_USER_HOME = "$DevRoot\.gradle"
Ok 'PUB_CACHE y GRADLE_USER_HOME apuntan a D:'

# ---------------------------------------------------------------------
# JDK 17. El Java que hay instalado es un JRE 1.8 de 32 bits con el
# jvm.cfg corrupto; Android Gradle Plugin necesita JDK 17 de 64 bits.
# ---------------------------------------------------------------------
Paso 'JDK 17'
$jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium', 'C:\Program Files\Microsoft' `
         -Filter 'jdk-17*' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($jdk) {
  Ok "Ya esta: $($jdk.FullName)"
} else {
  Write-Host '  Instalando Microsoft OpenJDK 17 con winget...'
  winget install --id Microsoft.OpenJDK.17 --silent --accept-package-agreements --accept-source-agreements
  $jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Filter 'jdk-17*' -Directory -ErrorAction SilentlyContinue |
           Select-Object -First 1
}
if ($jdk) {
  [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk.FullName, 'User')
  $env:JAVA_HOME = $jdk.FullName
  Ok "JAVA_HOME = $($jdk.FullName)"
} else {
  Aviso 'No se pudo resolver el JDK 17. Instalalo a mano desde https://adoptium.net'
}

# ---------------------------------------------------------------------
# Flutter SDK en D:\dev\flutter
# ---------------------------------------------------------------------
Paso 'Flutter SDK'
$flutterDir = "$DevRoot\flutter"
if (Test-Path "$flutterDir\bin\flutter.bat") {
  Ok 'Flutter ya esta clonado'
  git -C $flutterDir pull --ff-only 2>&1 | Out-Null
} else {
  Write-Host "  Clonando el canal stable en $flutterDir (puede tardar varios minutos)..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git $flutterDir
  Ok 'Flutter clonado'
}

# Agrega Flutter al PATH del usuario, sin duplicar la entrada.
$pathUsuario = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($pathUsuario -notlike "*$flutterDir\bin*") {
  [Environment]::SetEnvironmentVariable('Path', "$pathUsuario;$flutterDir\bin", 'User')
  Ok 'Flutter agregado al PATH'
}
$env:Path = "$env:Path;$flutterDir\bin"

Paso 'Configurando Flutter'
& "$flutterDir\bin\flutter.bat" config --no-analytics --enable-windows-desktop | Out-Null
Ok 'Escritorio de Windows habilitado'

$sdkAndroid = "$env:LOCALAPPDATA\Android\Sdk"
if (Test-Path $sdkAndroid) {
  & "$flutterDir\bin\flutter.bat" config --android-sdk $sdkAndroid | Out-Null
  Ok "Android SDK enlazado: $sdkAndroid"
  Write-Host '  Aceptando licencias de Android...'
  & "$flutterDir\bin\flutter.bat" doctor --android-licenses
} else {
  Aviso 'No aparece el Android SDK. Instala Android Studio si vas a compilar el APK.'
}

Paso 'Diagnostico final'
& "$flutterDir\bin\flutter.bat" doctor -v

Write-Host @'

---------------------------------------------------------------------
LISTO. Cerra y volve a abrir la terminal para que tome el PATH nuevo.

Si `flutter doctor` marca en rojo "Visual Studio", instala:
  Visual Studio 2022 Community + carga "Desarrollo para el escritorio con C++"
  https://visualstudio.microsoft.com/es/downloads/
Solo hace falta para generar el .exe de Windows. Android y web andan sin eso.
---------------------------------------------------------------------
'@ -ForegroundColor Cyan
