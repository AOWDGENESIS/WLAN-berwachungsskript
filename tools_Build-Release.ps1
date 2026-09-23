param(
    [string]$Version = "1.0.0",
    [string]$OutputRoot = "$PSScriptRoot\..\build",
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$output = [IO.Path]::GetFullPath($OutputRoot)
$package = Join-Path $output "WLAN-Guardian-$Version"

if (Test-Path $output) {
    Remove-Item $output -Recurse -Force
}
New-Item -ItemType Directory -Path $package -Force | Out-Null

$files = @("Start-Guardian.ps1", "WLAN-Guardian-UI.cmd", "README.md", "LICENSE")
foreach ($file in $files) {
    Copy-Item (Join-Path $root $file) $package -Force
}

foreach ($dir in @("src", "config")) {
    Copy-Item (Join-Path $root $dir) (Join-Path $package $dir) -Recurse -Force
}

New-Item -ItemType Directory -Path (Join-Path $package "artifacts") -Force | Out-Null

$zip = Join-Path $output "WLAN-Guardian-$Version.zip"
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip -CompressionLevel Optimal

if (-not $SkipInstaller) {
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($null -eq $iscc) {
        Write-Warning "ISCC.exe nicht gefunden. ZIP wurde erstellt; installiere Inno Setup 6 für die EXE."
    }
    else {
        & $iscc.Source "/DMyAppVersion=$Version" (Join-Path $root "installer\WLAN-Guardian.iss")
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup fehlgeschlagen: $LASTEXITCODE"
        }
    }
}

& (Join-Path $root "tools\Verify-Release.ps1") -ReleaseRoot $package
Write-Host "Release erstellt: $output"