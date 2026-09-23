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

& $guardian -Once:$Once -ConfigPath $ConfigPath
exit $LASTEXITCODE
