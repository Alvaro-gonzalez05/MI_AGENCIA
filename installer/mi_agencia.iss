; =====================================================================
;  Mi Agencia — instalador de Windows (Inno Setup 6)
;
;  Lo compila el workflow .github/workflows/release.yml en un runner de
;  GitHub, que ya trae Inno Setup e Visual Studio con C++.
;
;  Para generarlo a mano:
;      ISCC.exe /DMiVersion=0.1.0 installer\mi_agencia.iss
; =====================================================================

#ifndef MiVersion
  #define MiVersion "0.0.0"
#endif

#define MiApp        "Mi Agencia"
#define MiEditor     "Codea"
#define MiEjecutable "mi_agencia.exe"

[Setup]
AppId={{8F3A1C27-4E5B-4A91-9D6E-2B7C8A4F1E93}
AppName={#MiApp}
AppVersion={#MiVersion}
AppVerName={#MiApp} {#MiVersion}
AppPublisher={#MiEditor}
DefaultDirName={autopf}\{#MiApp}
DefaultGroupName={#MiApp}
OutputDir=salida
OutputBaseFilename=MiAgencia-Setup-{#MiVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Instala para el usuario actual y no pide permisos de administrador.
; En una agencia, el que usa la PC casi nunca es administrador de su equipo.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; La app es de 64 bits: en un Windows de 32 bits no tiene sentido ni intentar.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Queda prolijo en Panel de control > Programas.
UninstallDisplayName={#MiApp}
UninstallDisplayIcon={app}\{#MiEjecutable}
DisableProgramGroupPage=yes
DisableDirPage=no
AllowNoIcons=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear un acceso directo en el escritorio"; \
  GroupDescription: "Accesos directos:"

[Files]
; El build de Flutter deja el .exe junto a sus DLL y la carpeta data\.
; Se copia el arbol completo: si falta un archivo, la app no arranca.
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MiApp}";        Filename: "{app}\{#MiEjecutable}"
Name: "{group}\Desinstalar {#MiApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MiApp}";  Filename: "{app}\{#MiEjecutable}"; Tasks: escritorio

[Run]
Filename: "{app}\{#MiEjecutable}"; Description: "Abrir {#MiApp}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Flutter escribe cache y preferencias al costado del ejecutable. Sin esto,
; desinstalar deja la carpeta con basura adentro.
Type: filesandordirs; Name: "{app}"
