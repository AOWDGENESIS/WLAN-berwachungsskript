param(
    [string]$Version = "1.0.0",
    [string]$OutputRoot = "$PSScriptRoot\..\build",
    [switch]$SkipInstaller,
    [switch]$RequireInstaller,
    [string]$InnoSetupPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$output = [IO.Path]::GetFullPath($OutputRoot)
$package = Join-Path $output "WLAN-Guardian-$Version"

if (Test-Path $output) { Remove-Item $output -Recurse -Force }
New-Item -ItemType Directory -Path $package -Force | Out-Null

$files = @("Start-Guardian.ps1", "WLAN-Guardian.cmd", "README.md", "LICENSE")
foreach ($file in $files) { Copy-Item (Join-Path $root $file) $package -Force }
foreach ($dir in @("src", "config")) {
    Copy-Item (Join-Path $root $dir) (Join-Path $package $dir) -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $package "artifacts") -Force | Out-Null

$zip = Join-Path $output "WLAN-Guardian-$Version.zip"
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip -CompressionLevel Optimal

if (-not $SkipInstaller) {
    $iscc = $null
    if (-not [string]::IsNullOrWhiteSpace($InnoSetupPath)) {
        if (-not (Test-Path -LiteralPath $InnoSetupPath -PathType Leaf)) {
            throw "ISCC.exe nicht gefunden: $InnoSetupPath"
        }
        $iscc = Get-Item -LiteralPath $InnoSetupPath
    } else {
        $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($null -eq $iscc) {
            $knownPaths = @(
                (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
                (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
            if ($knownPaths.Count -gt 0) {
                $iscc = Get-Item -LiteralPath $knownPaths[0]
            }
        }
    }
    if ($null -eq $iscc) {
        if ($RequireInstaller) {
            throw "ISCC.exe nicht gefunden. Installiere Inno Setup 6 oder verwende -SkipInstaller."
        }
        Write-Warning "ISCC.exe nicht gefunden. ZIP wurde erstellt; installiere Inno Setup 6 für die EXE."
    } else {
        $isccCommand = if ($iscc.PSObject.Properties.Name -contains "FullName") {
            $iscc.FullName
        } else {
            $iscc.Source
        }
        & $isccCommand "/DMyAppVersion=$Version" (Join-Path $root "installer\WLAN-Guardian.iss")
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup fehlgeschlagen: $LASTEXITCODE" }
        $setup = Join-Path $output "WLAN-Guardian-Setup-$Version.exe"
        if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
            throw "Installer-EXE wurde nicht erzeugt: $setup"
        }
    }
}

& (Join-Path $root "tools\Verify-Release.ps1") -ReleaseRoot $package
Write-Host "Release erstellt: $output"
