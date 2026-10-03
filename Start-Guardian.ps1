param(
    [switch]$Once,
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$guardian = Join-Path $root "src\Guardian.ps1"
if (-not (Test-Path -LiteralPath $guardian -PathType Leaf)) {
    throw "Guardian core not found: $guardian"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root "config\guardian.example.json"
} elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path (Get-Location).Path $ConfigPath
}

# src/Guardian.ps1 ruft selbst kein exit auf. $LASTEXITCODE ist hier deshalb der
# Restwert aus der aufrufenden Sitzung und sagt ueber diesen Lauf nichts aus -
# dieselbe Fehlerklasse, die in Test-All.ps1 ein gruenes Gate rot gemeldet hat.
# WLAN-Guardian.cmd wertet %ERRORLEVEL% aus und zeigt bei allem ungleich 0 ein
# pause-Fenster, ein Restwert haette also einen falschen Fehlerdialog erzeugt.
# Ein Abbruch von src/Guardian.ps1 beendet das Skript ohnehin mit Code 1, weil
# $ErrorActionPreference auf Stop steht.
& $guardian -Once:$Once -ConfigPath $ConfigPath
exit 0
