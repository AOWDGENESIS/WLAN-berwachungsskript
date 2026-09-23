param([string]$ReleaseRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath($ReleaseRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Release root not found: $root"
}

$required = @(
    "Start-Guardian.ps1",
    "WLAN-Guardian-UI.cmd",
    "README.md",
    "LICENSE",
    "src\Guardian.Core\Guardian.Core.psm1",
    "src\Guardian.UI\Guardian.UI.ps1",
    "config\guardian.example.json"
)

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release file missing: $relative"
    }
}

Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF8 BOM found: $($_.FullName)"
    }
}

Write-Host "Release validation: PASS"