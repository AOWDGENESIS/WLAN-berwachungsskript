param(
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Pfade anpassen für D:\WLAN Guardian
$root = "D:\WLAN Guardian"
$buildRoot = Join-Path $root "build"
$package = Join-Path $buildRoot "WLAN-Guardian-$version"

Write-Host "=== WLAN Guardian Release Builder ===" -ForegroundColor Cyan
Write-Host "Version: $version"
Write-Host "Root: $root"
Write-Host "Build Root: $buildRoot"
Write-Host ""

# 1. Build-Verzeichnis aufräumen
Write-Host "[1/6] Cleaning build directory..." -ForegroundColor Yellow
if (Test-Path $buildRoot) { 
    Remove-Item $buildRoot -Recurse -Force
    Write-Host "✓ Old build directory removed"
}

# 2. Neue Release-Struktur aufbauen
Write-Host "[2/6] Creating release structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $package -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $package "artifacts") -Force | Out-Null
Write-Host "✓ Release directories created"

# 3. Kern-Dateien kopieren
Write-Host "[3/6] Copying core files..." -ForegroundColor Yellow
$requiredFiles = @("Start-Guardian.ps1", "WLAN-Guardian.cmd", "README.md", "LICENSE")
foreach ($file in $requiredFiles) {
    $source = Join-Path $root $file
    if (-not (Test-Path $source)) {
        throw "Missing: $file"
    }
    Copy-Item $source $package -Force
    Write-Host "  ✓ $file"
}

# 4. Verzeichnisse kopieren
Write-Host "[4/6] Copying directories (src, config)..." -ForegroundColor Yellow
Copy-Item (Join-Path $root "src") (Join-Path $package "src") -Recurse -Force
Write-Host "  ✓ src/"
Copy-Item (Join-Path $root "config") (Join-Path $package "config") -Recurse -Force
Write-Host "  ✓ config/"

# 5. Release-Validierung
Write-Host "[5/6] Running release validation..." -ForegroundColor Yellow
$verifyScript = Join-Path $root "tools\Verify-Release.ps1"
if (Test-Path $verifyScript) {
    & $verifyScript -ReleaseRoot $package
    Write-Host "✓ Release validation passed"
} else {
    Write-Host "⚠ Verify script not found, skipping validation"
}

# 6. ZIP erstellen
Write-Host "[6/6] Creating ZIP archive..." -ForegroundColor Yellow
$zip = Join-Path $buildRoot "WLAN-Guardian-$version.zip"
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "✓ ZIP created: $zip"

# 7. Installer (optional)
Write-Host ""
Write-Host "=== Installer Build ===" -ForegroundColor Cyan
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($null -ne $iscc) {
    Write-Host "Building Inno Setup Installer..."
    $issScript = Join-Path $root "installer\WLAN-Guardian.iss"
    & $iscc.Source "/DMyAppVersion=$version" $issScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Installer created successfully"
        $exe = Join-Path $buildRoot "WLAN-Guardian-Setup-$version.exe"
        if (Test-Path $exe) {
            Write-Host "  → $exe"
        }
    } else {
        Write-Host "✗ Installer build failed"
    }
} else {
    Write-Host "⚠ ISCC.exe not found - install Inno Setup 6 to build the installer"
    Write-Host "  ZIP is ready at: $zip"
}

Write-Host ""
Write-Host "=== Release Summary ===" -ForegroundColor Green
Write-Host "Location: $buildRoot"
Write-Host "ZIP: $zip"
Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
