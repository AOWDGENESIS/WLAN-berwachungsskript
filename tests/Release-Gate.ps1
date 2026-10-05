$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$checks = @(
    (Join-Path $root "Start-Guardian.ps1"),
    (Join-Path $root "WLAN-Guardian.cmd"),
    (Join-Path $root "src\Guardian.ps1"),
    (Join-Path $root "src\Guardian-Devices.ps1"),
    (Join-Path $root "config\guardian.example.json"),
    (Join-Path $root "installer\WLAN-Guardian.iss"),
    (Join-Path $root "tools\Install-Guardian.ps1"),
    (Join-Path $root "src\Guardian.UI\Guardian.UI.ps1"),
    (Join-Path $root "src\Guardian.Tray\Guardian.Tray.ps1")
)
foreach ($path in $checks) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
    Write-Host "FILE: PASS $path"
}

$config = Get-Content (Join-Path $root "config\guardian.example.json") -Raw | ConvertFrom-Json
if ([int]$config.intervalSeconds -lt 1) { throw "Invalid intervalSeconds" }
if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) { throw "Invalid logDirectory" }
Write-Host "Configuration: PASS"

# Laufzeitpruefung. Sie stammt aus der flach hochgeladenen Kopie
# tests_Release-Gate.ps1 (Commit 07a3286) und war in dieser Fassung nie
# enthalten - der Check waere mit der Dublette verschwunden.
# Er ist bewusst kein harter Abbruch: Der Kern laeuft unter Windows PowerShell
# 5.1 ohne dotnet, deshalb gibt es nur eine Warnung.
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $dotnet) {
    Write-Host "dotnet: WARN nicht gefunden, der Kern braucht es nicht" -ForegroundColor Yellow
}
else {
    Write-Host "dotnet: PASS"
}
Write-Host "Release gate: PASS"
