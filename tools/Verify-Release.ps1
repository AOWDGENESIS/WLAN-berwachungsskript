param([Parameter(Mandatory=$true)][string]$ReleaseRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath($ReleaseRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Release root not found: $root" }

$bad = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $b = [IO.File]::ReadAllBytes($_.FullName)
    if ($b.Length -ge 3) {
        if ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $bad.Add("UTF8_BOM: $($_.FullName)") }
    }
}
if ($bad.Count -gt 0) {
    $bad | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "Release validation: PASS"
