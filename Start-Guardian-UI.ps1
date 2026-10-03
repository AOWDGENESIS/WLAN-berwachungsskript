#!/usr/bin/env powershell
<#
.SYNOPSIS
    Guardian UI Entry Point
.DESCRIPTION
    Launches the WLAN Guardian graphical user interface.
.EXAMPLE
    .\Start-Guardian-UI.ps1
#>

param(
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root "config\guardian.example.json"
} elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path (Get-Location).Path $ConfigPath
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration not found: $ConfigPath"
    exit 1
}

# Load Core Module
$coreModule = Join-Path $root "src\Guardian.Core\Guardian.Core.psm1"
if (Test-Path $coreModule) {
    Import-Module $coreModule -Force
}

# UI starten.
# Guardian.UI.ps1 ist KEIN Modul, sondern ein eigenstaendiges Skript: Es hat
# einen param()-Block und baut das WinForms-Fenster direkt auf. Ein
# Import-Module auf "Guardian.UI.psm1" fand die Datei nie, der Test-Path-Zweig
# griff, und der Start fiel still auf die Konsole zurueck - die GUI erschien
# nie. Ausserdem wurde Show-GuardianUI aufgerufen, das nirgends definiert ist.
# Gefunden beim Zusammenfuehren mit main (Commit 2489631 "Guardian UI start
# script") gegen Commit 1945 B "src/Guardian.UI/Guardian.UI.ps1".
$uiScript = Join-Path $root "src\Guardian.UI\Guardian.UI.ps1"
if (Test-Path $uiScript) {
    & $uiScript -ConfigPath $ConfigPath
} else {
    Write-Host "Guardian UI script not found. Launching console version..." -ForegroundColor Yellow
    & (Join-Path $root "Start-Guardian.ps1") -ConfigPath $ConfigPath
}
