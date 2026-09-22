param(
    [switch]$Once,
    [string]$ConfigPath = ".\config\guardian.example.json"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$guardian = Join-Path $root "src\Guardian.ps1"

if (-not (Test-Path $guardian -PathType Leaf)) {
    throw "Guardian core not found: $guardian"
}

& $guardian -Once:$Once -ConfigPath $ConfigPath
