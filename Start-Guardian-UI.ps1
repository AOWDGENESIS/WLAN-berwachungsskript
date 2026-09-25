param(
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ui = Join-Path $root "src\Guardian.UI\Guardian.UI.ps1"

if (-not (Test-Path -LiteralPath $ui -PathType Leaf)) {
    throw "Guardian UI not found: $ui"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root "config\guardian.example.json"
} elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $root $ConfigPath
}

& $ui -ConfigPath $ConfigPath
