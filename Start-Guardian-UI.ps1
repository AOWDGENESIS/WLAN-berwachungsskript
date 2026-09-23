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

& $ui -ConfigPath $ConfigPath
