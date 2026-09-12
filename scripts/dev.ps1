# =====================================================================
#  Mi Agencia — entorno de desarrollo
#
#  Uso:
#      .\scripts\dev.ps1 run -d chrome      # levanta la app en el navegador
#      .\scripts\dev.ps1 build apk --debug  # compila el APK
#      .\scripts\dev.ps1 doctor
#
#  O para dejar la terminal actual configurada y despues usar flutter suelto:
#      . .\scripts\dev.ps1
#
#  Existe porque esta maquina necesita tres ajustes que Flutter no hace solo.
#  Ver docs/ENTORNO.md para el detalle de por que.
# =====================================================================

# 1. Toolchain en D:, porque C: tiene poco espacio libre.
$env:JAVA_HOME        = 'D:\dev\jdk17'
$env:PUB_CACHE        = 'D:\dev\.pub-cache'
$env:GRADLE_USER_HOME = 'D:\dev\.gradle'

# 2. TEMP fuera de C:\Users\...\AppData\Local\Temp.
#    En esa carpeta las conexiones a sockets AF_UNIX fallan con
#    "Invalid argument: connect", y el JDK usa justamente un socket AF_UNIX
#    para el pipe interno de java.nio.channels.Selector. Resultado: Gradle
#    muere con "Unable to establish loopback connection" antes de compilar
#    una sola linea. El JDK lee la VARIABLE DE ENTORNO TEMP para ubicar ese
#    socket, no la propiedad -Djava.io.tmpdir: por eso se setea aca.
if (-not (Test-Path 'D:\dev\tmp')) { New-Item -ItemType Directory -Path 'D:\dev\tmp' | Out-Null }
$env:TEMP = 'D:\dev\tmp'
$env:TMP  = 'D:\dev\tmp'

# 3. PATH con el JDK y Flutter primero.
foreach ($p in 'D:\dev\flutter\bin', 'D:\dev\jdk17\bin') {
  if ($env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path" }
}

if ($args.Count -eq 0) {
  Write-Host 'Entorno configurado en esta terminal. Ya podes usar `flutter` directamente.' -ForegroundColor Green
  Write-Host "  JAVA_HOME        = $env:JAVA_HOME"
  Write-Host "  TEMP             = $env:TEMP"
  Write-Host "  GRADLE_USER_HOME = $env:GRADLE_USER_HOME"
} else {
  Push-Location (Join-Path $PSScriptRoot '..\app')
  try { & flutter @args } finally { Pop-Location }
}
