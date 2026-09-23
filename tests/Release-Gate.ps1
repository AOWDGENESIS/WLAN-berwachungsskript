$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$checks = @(
    (Join-Path $root "Start-Guardian.ps1"),
    (Join-Path $root "WLAN-Guardian.cmd"),
    (Join-Path $root "src\Guardian.ps1"),
    (Join-Path $root "src\Guardian-Devices.ps1"),
    (Join-Path $root "config\guardian.example.json"),
    (Join-Path $root "installer\WLAN-Guardian.iss")
)
foreach ($path in $checks) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
    Write-Host "FILE: PASS $path"
}

$config = Get-Content (Join-Path $root "config\guardian.example.json") -Raw | ConvertFrom-Json
if ([int]$config.intervalSeconds -lt 1) { throw "Invalid intervalSeconds" }
if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) { throw "Invalid logDirectory" }
Write-Host "Configuration: PASS"
Write-Host "Release gate: PASS"
