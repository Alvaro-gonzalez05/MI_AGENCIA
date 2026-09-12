# =====================================================================
#  Mi Agencia — entorno de desarrollo
#
#  Uso:
#      .\scripts\dev.ps1 run -d chrome      # levanta la app en el navegador
#      .\scripts\dev.ps1 build apk --release
#      .\scripts\dev.ps1 test
#      .\scripts\dev.ps1 analyze
#
#  O para dejar la terminal actual configurada y despues usar flutter suelto:
#      . .\scripts\dev.ps1
#
#  Existe porque esta maquina necesita tres ajustes que Flutter no hace solo,
#  y porque las credenciales de Supabase se inyectan aca en vez de vivir
#  hardcodeadas en el codigo. Ver docs/ENTORNO.md para el detalle de por que.
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

# ---------------------------------------------------------------------
# Credenciales de Supabase desde .env (que no se commitea).
#
# Si el archivo no existe, la app arranca en MODO DEMO contra los datos de
# ejemplo. Eso es a proposito: el proyecto tiene que poder clonarse y correr
# sin credenciales.
# ---------------------------------------------------------------------
$raiz    = Split-Path $PSScriptRoot -Parent
$archivo = Join-Path $raiz '.env'
$defines = @()

if (Test-Path $archivo) {
  foreach ($linea in Get-Content $archivo) {
    $t = $linea.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $clave = $t.Substring(0, $i).Trim()
    $valor = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
    if ($valor) { $defines += "--dart-define=$clave=$valor" }
  }
}

if ($args.Count -eq 0) {
  Write-Host 'Entorno configurado en esta terminal.' -ForegroundColor Green
  Write-Host "  JAVA_HOME        = $env:JAVA_HOME"
  Write-Host "  TEMP             = $env:TEMP"
  Write-Host "  GRADLE_USER_HOME = $env:GRADLE_USER_HOME"
  if ($defines.Count -gt 0) {
    Write-Host "  Supabase         = configurado ($($defines.Count) variables)"
  } else {
    Write-Host '  Supabase         = sin configurar (modo demo)' -ForegroundColor Yellow
  }
  return
}

# Las --dart-define solo aplican a los comandos que compilan la app.
# `test`, `analyze` y `pub` las rechazan.
$comando   = $args[0]
$compilan  = @('run', 'build', 'drive')
$argumentos = @($args)

if ($compilan -contains $comando -and $defines.Count -gt 0) {
  $argumentos += $defines
  Write-Host "Supabase: conectado a la base real ($($defines.Count) variables)" -ForegroundColor Cyan
} elseif ($compilan -contains $comando) {
  Write-Host 'Supabase: sin .env — la app arranca en modo demo' -ForegroundColor Yellow
}

Push-Location (Join-Path $PSScriptRoot '..\app')
try { & flutter @argumentos } finally { Pop-Location }
