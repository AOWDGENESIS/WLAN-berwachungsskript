param(
    [string]$Version = "1.1.0"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Die Projektwurzel wird aus dem Ort des Skripts gerechnet, nicht fest
# eingetragen. Der vorherige Wert "D:\WLAN Guardian" machte das Werkzeug fuer
# jeden anderen Rechner unbrauchbar. Zwei Split-Path: tools\ -> Projektwurzel.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$buildRoot = Join-Path $root "build"
$package = Join-Path $buildRoot "WLAN-Guardian-$version"

Write-Host "=== WLAN Guardian Release Builder ===" -ForegroundColor Cyan
Write-Host "Version: $version"
Write-Host "Root: $root"
Write-Host "Build Root: $buildRoot"
Write-Host ""

# 1. Build-Verzeichnis aufraeumen
Write-Host "[1/6] Cleaning build directory..." -ForegroundColor Yellow
if (Test-Path $buildRoot) { 
    Remove-Item $buildRoot -Recurse -Force
    Write-Host "[OK] Old build directory removed"
}

# 2. Neue Release-Struktur aufbauen
Write-Host "[2/6] Creating release structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $package -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $package "artifacts") -Force | Out-Null
Write-Host "[OK] Release directories created"

# 3. Kern-Dateien kopieren
Write-Host "[3/6] Copying core files..." -ForegroundColor Yellow
$requiredFiles = @("Start-Guardian.ps1", "WLAN-Guardian.cmd", "README.md", "LICENSE")
foreach ($file in $requiredFiles) {
    $source = Join-Path $root $file
    if (-not (Test-Path $source)) {
        throw "Missing: $file"
    }
    Copy-Item $source $package -Force
    Write-Host "  [OK] $file"
}

# 4. Verzeichnisse kopieren
Write-Host "[4/6] Copying directories (src, config)..." -ForegroundColor Yellow
Copy-Item (Join-Path $root "src") (Join-Path $package "src") -Recurse -Force
Write-Host "  [OK] src/"
Copy-Item (Join-Path $root "config") (Join-Path $package "config") -Recurse -Force
Write-Host "  [OK] config/"

# 5. Release-Validierung
Write-Host "[5/6] Running release validation..." -ForegroundColor Yellow
$verifyScript = Join-Path $root "tools\Verify-Release.ps1"
if (Test-Path $verifyScript) {
    & $verifyScript -ReleaseRoot $package
    Write-Host "[OK] Release validation passed"
} else {
    Write-Host "[ACHTUNG] Verify script not found, skipping validation"
}

# 6. ZIP erstellen
Write-Host "[6/6] Creating ZIP archive..." -ForegroundColor Yellow
$zip = Join-Path $buildRoot "WLAN-Guardian-$version.zip"
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "[OK] ZIP created: $zip"

# 7. Installer (optional)
Write-Host ""
Write-Host "=== Installer Build ===" -ForegroundColor Cyan

# Pfade fuer Inno Setup 7
$isccPaths = @(
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $isccPath = $path
        break
    }
}

if ($null -ne $isccPath) {
    Write-Host "Found ISCC.exe at: $isccPath"
    Write-Host "Building Inno Setup Installer..."
    $issScript = Join-Path $root "installer\WLAN-Guardian.iss"
    if (Test-Path $issScript) {
        & $isccPath "/DMyAppVersion=$version" $issScript
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installer created successfully"
            $exe = Join-Path $buildRoot "WLAN-Guardian-Setup-$version.exe"
            if (Test-Path $exe) {
                $exeSize = (Get-Item $exe).Length / 1MB
                Write-Host "  -> $exe ($([Math]::Round($exeSize, 2)) MB)"
            }
        } else {
            Write-Host "[FEHLER] Installer build failed (exit code: $LASTEXITCODE)"
        }
    } else {
        Write-Host "[FEHLER] Installer script not found: $issScript"
    }
} else {
    Write-Host "[ACHTUNG] ISCC.exe not found"
    Write-Host "  Checked:"
    foreach ($path in $isccPaths) {
        Write-Host "    - $path"
    }
    Write-Host "  Install Inno Setup 6 or 7 to build the installer"
}

Write-Host ""
Write-Host "=== Release Summary ===" -ForegroundColor Green
Write-Host "Location: $buildRoot"
Write-Host "ZIP: $zip"
$zipSize = (Get-Item $zip).Length / 1MB
Write-Host "Size: $([Math]::Round($zipSize, 2)) MB"
Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green
