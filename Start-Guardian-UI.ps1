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

# Load UI Module
$uiModule = Join-Path $root "src\Guardian.UI\Guardian.UI.psm1"
if (Test-Path $uiModule) {
    Import-Module $uiModule -Force
    
    # Initialize and show UI
    $config = Read-GuardianConfig -Path $ConfigPath
    Show-GuardianUI -Config $config
} else {
    Write-Host "Guardian UI module not found. Launching console version..." -ForegroundColor Yellow
    & (Join-Path $root "Start-Guardian.ps1") -ConfigPath $ConfigPath
}
