#define MyAppName "WLAN Guardian"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AOWDGENESIS"
#define MyAppExeName "WLAN-Guardian.cmd"

[Setup]
AppId={{B0D7B00D-4D4A-4C73-9D28-6A9F5EFC0A01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\WLAN Guardian
DefaultGroupName={#MyAppName}
OutputDir=..\build
OutputBaseFilename=WLAN-Guardian-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
UninstallDisplayIcon={app}\WLAN-Guardian.cmd
LicenseFile=..\LICENSE

[Files]
Source: "..\Start-Guardian.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\WLAN-Guardian.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\*.ps1"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\config\guardian.example.json"; DestDir: "{app}\config"; Flags: ignoreversion

[Dirs]
Name: "{app}\artifacts"

[Icons]
Name: "{group}\WLAN Guardian"; Filename: "{app}\WLAN-Guardian.cmd"; WorkingDir: "{app}"
Name: "{group}\WLAN Guardian (einmalig)"; Filename: "{app}\WLAN-Guardian.cmd"; Parameters: "-Once"; WorkingDir: "{app}"
Name: "{commondesktop}\WLAN Guardian"; Filename: "{app}\WLAN-Guardian.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Desktop-Verknüpfung erstellen"; GroupDescription: "Zusätzliche Verknüpfungen:"

[Run]
Filename: "{app}\WLAN-Guardian.cmd"; Description: "WLAN Guardian starten"; Flags: postinstall nowait skipifsilent
