$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$failed = $false

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($null -eq $dotnet) {
    Write-Error "dotnet is missing"
    $failed = $true
}
if ($null -ne $dotnet) {
    Write-Host "dotnet: PASS"
}

if ($failed) {
    exit 1
}

Write-Host "Release gate: PASS"