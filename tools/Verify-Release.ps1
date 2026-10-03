param([string]$ReleaseRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $root
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path $projectRoot "build\WLAN-Guardian-1.0.0" }
$release = [IO.Path]::GetFullPath($ReleaseRoot)
if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "Release root not found: $release" }

# Vereinigung zweier Prueflisten, die sich im Ziel-Repository auseinander-
# entwickelt hatten: die verschachtelte Fassung (Commit 71767c5) verlangte
# WLAN-Guardian.cmd und src\Guardian.ps1, die spaeter per Web-Upload
# hochgeladene flache Kopie (Commit 07a3286, neuer) verlangte stattdessen
# WLAN-Guardian-UI.cmd und die Modulpfade. Keine der beiden war vollstaendig.
# Build-Release.ps1 legt beide Launcher, beide Einstiegsskripte und den
# kompletten src-Ordner ab, also kann die Vereinigung verlangt werden.
$required = @(
    "Start-Guardian.ps1",
    "Start-Guardian-UI.ps1",
    "WLAN-Guardian.cmd",
    "WLAN-Guardian-UI.cmd",
    "README.md",
    "LICENSE",
    "src\Guardian.ps1",
    "src\Guardian.Core\Guardian.Core.psm1",
    "src\Guardian.UI\Guardian.UI.ps1",
    "config\guardian.example.json"
)
foreach ($relative in $required) {
    $path = Join-Path $release $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required release file missing: $relative" }
}

$config = Get-Content (Join-Path $release "config\guardian.example.json") -Raw | ConvertFrom-Json
if ([int]$config.version -lt 1) { throw "Unsupported configuration version" }
if ([int]$config.intervalSeconds -lt 1) { throw "intervalSeconds must be positive" }

# Vorher: Get-Command powershell.exe, sonst "Windows PowerShell is required".
# Das war doppelt falsch. Erstens ist $ps danach nie benutzt worden - die
# Pruefung sagte nichts ueber das Release aus. Zweitens lehnte sie ein System
# ab, auf dem nur pwsh laeuft, obwohl der Kern unter beiden Versionen laeuft.
$interpreter = $null
foreach ($kandidat in @('pwsh.exe', 'powershell.exe')) {
    if (Get-Command $kandidat -ErrorAction SilentlyContinue) { $interpreter = $kandidat; break }
}
if ($null -eq $interpreter) { throw "Kein PowerShell-Interpreter gefunden (pwsh.exe oder powershell.exe)" }
Write-Host "Interpreter: $interpreter"

Get-ChildItem -LiteralPath $release -Recurse -File | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF8 BOM found: $($_.FullName)"
    }
}
Write-Host "Release validation: PASS"
