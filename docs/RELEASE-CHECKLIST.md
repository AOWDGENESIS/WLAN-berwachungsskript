Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ReleaseChecklist {
    return @(
        @{ Task = "Verify all src/ modules are present"; Category = "Files" }
        @{ Task = "Check config/guardian.example.json validity"; Category = "Config" }
        @{ Task = "Verify no UTF-8 BOM in any .ps1 file"; Category = "Encoding" }
        @{ Task = "Ensure no plaintext secrets in any file"; Category = "Security" }
        @{ Task = "Run Release-Gate validation"; Category = "Validation" }
        @{ Task = "Build and compress ZIP package"; Category = "Package" }
        @{ Task = "Build Windows Installer (if ISCC.exe available)"; Category = "Installer" }
    )
}

Write-Host "WLAN Guardian Release Checklist" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$checklist = Get-ReleaseChecklist
$groups = $checklist | Group-Object -Property Category

foreach ($group in $groups) {
    Write-Host $group.Name -ForegroundColor Yellow
    foreach ($item in $group.Group) {
        Write-Host "  ☐ $($item.Task)"
    }
    Write-Host ""
}

Write-Host "Run Release-Builder.ps1 to complete all steps automatically." -ForegroundColor Green
