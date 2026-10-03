<#
.SYNOPSIS
    Modulare Ueberwachungsschleife - NOCH NICHT VERDRAHTET.

.DESCRIPTION
    Dieser Pfad ist erreichbar nur ueber src/Guardian.Tray/Guardian.Tray.ps1,
    und das ruft niemand auf. Er ist ausserdem nie erfolgreich gelaufen: Bis
    Commit 4829fc4 war $root um eine Ebene zu flach, damit schlugen alle vier
    Import-Module fehl, bevor irgendetwas anderes lief.

    Die MVP-Implementierung ist src/Guardian.ps1, aufgerufen ueber
    Start-Guardian.ps1. Einzelheiten und die Voraussetzungen fuer einen
    spaeteren Wechsel stehen in docs/ARCHITEKTUR-ENTSCHEIDUNG.md.

    Beide Pfade haengen an dieselbe guardian-events.jsonl, fuehren aber je eine
    eigene State-Datei. Die Ein-Instanz-Sperre im Kern verhindert, dass beide
    gleichzeitig laufen.
#>
param([string]$ConfigPath = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Der Pfad war falsch: Split-Path -Parent lieferte "src\Guardian.Tray", und der
# Join-Path darunter ergab "src\Guardian.Tray\src\Guardian.Service\...". Diese
# Datei existiert nicht, der Start des Dienstes musste also immer fehlschlagen.
# Zwei Ebenen hoch, genau wie Guardian.Service.ps1 es selbst macht.
# Drei Ebenen, nicht zwei. Diese Datei liegt in src\<Modul>\, also:
#   Datei -> src\<Modul> -> src -> Projektwurzel.
# Mit nur zwei Split-Path war $root gleich "src", und jeder Join-Path darunter
# ergab src\src\... oder src\artifacts\... - Import-Module, Config und Log
# griffen damit alle daneben.
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$service = Join-Path $root 'src\Guardian.Service\Guardian.Service.ps1'

if (-not (Test-Path -LiteralPath $service -PathType Leaf)) {
    throw "Guardian.Service nicht gefunden: $service"
}

# Derselbe Interpreter wie WLAN-Guardian.cmd: pwsh, wenn vorhanden, sonst
# Windows PowerShell. Bisher war powershell.exe hart kodiert, die Konsole lief
# damit unter 5.1 und die UI unter einem anderen Interpreter als der Dienst.
$ps = 'powershell.exe'
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { $ps = 'pwsh.exe' }

$args = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $service)
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $args += @('-ConfigPath', $ConfigPath) }

& $ps @args
exit 0
