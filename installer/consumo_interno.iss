#define AppName "Consumo interno"
#define AppVersion "1.7.2"
#define AppExe "consumo_interno.exe"
[Setup]
AppId={{09C29B13-62D6-4BE3-AE17-2A481CB3A53E}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\ConsumoInterno
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=consumo_interno_instalador_windows
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"
[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent

