param(
    [string]$CacheRoot = "$PSScriptRoot\..\cache"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$cache = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Force -Path $cache | Out-Null

Write-Host "GENESIS Guardian dependency preflight"
Write-Host "Cache: $cache"

$names = @("dotnet","git","winget")
foreach ($name in $names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { Write-Host "MISSING: $name" }
    if ($null -ne $cmd) { Write-Host "FOUND: $name -> $($cmd.Source)" }
}

Write-Host "External installers are resolved from official sources only."
Write-Host "The final bootstrapper will ask for the install path before installation."
