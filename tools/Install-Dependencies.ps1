Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Installing WLAN Guardian dependencies..." -ForegroundColor Cyan

# Prüfe auf erforderliche Rollen/Features
$requiredFeatures = @(
    @{ Name = "PowerShell 5.1+"; Check = { $PSVersionTable.PSVersion.Major -ge 5 } }
    @{ Name = "Windows 10 oder neuer"; Check = { [System.Environment]::OSVersion.Version.Major -ge 10 } }
)

foreach ($feature in $requiredFeatures) {
    if (& $feature.Check) {
        Write-Host "✓ $($feature.Name)" -ForegroundColor Green
    } else {
        Write-Host "✗ $($feature.Name) NOT FOUND" -ForegroundColor Red
        throw "$($feature.Name) is required"
    }
}

Write-Host ""
Write-Host "All dependencies satisfied." -ForegroundColor Green
