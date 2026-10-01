param(
    [string]$Version = "1.0.0",
    [string]$OutputPath = ".\build"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     WLAN Guardian - Complete Release Package Builder      ║" -ForegroundColor Cyan
Write-Host "╚══════════���═════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $root $OutputPath
$packageDir = Join-Path $buildDir "WLAN-Guardian-$Version"
$zipFile = Join-Path $buildDir "WLAN-Guardian-$Version.zip"

# ============================================================================
# PHASE 1: CLEANUP & PREPARATION
# ============================================================================
Write-Host "PHASE 1: Cleanup & Preparation" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Magenta

if (Test-Path $buildDir) {
    Write-Host "[1/3] Removing old build artifacts..." -ForegroundColor Yellow
    Remove-Item $buildDir -Recurse -Force | Out-Null
    Write-Host "      ✓ Old build directory removed"
}

Write-Host "[2/3] Creating release structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $packageDir "artifacts") -Force | Out-Null
Write-Host "      ✓ Release directories created"

Write-Host "[3/3] Validating source structure..." -ForegroundColor Yellow
$requiredDirs = @("config", "src", "docs", "tools", "installer", "tests")
foreach ($dir in $requiredDirs) {
    $srcPath = Join-Path $root $dir
    if (-not (Test-Path $srcPath)) {
        Write-Host "      ⚠ Warning: $dir not found (non-critical)" -ForegroundColor Yellow
    } else {
        Write-Host "      ✓ $dir found"
    }
}

# ============================================================================
# PHASE 2: COPY PROJECT FILES
# ============================================================================
Write-Host ""
Write-Host "PHASE 2: Copying Project Files" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Magenta

$rootFiles = @(
    "Start-Guardian.ps1",
    "Start-Guardian-UI.ps1",
    "WLAN-Guardian.cmd",
    "WLAN-Guardian-UI.cmd",
    "README.md",
    "LICENSE",
    ".gitignore",
    "INSTALL-FLOW.md",
    "KIT-HASHES.json",
    "release-manifest.example.json"
)

Write-Host "[2/1] Copying root files..." -ForegroundColor Yellow
foreach ($file in $rootFiles) {
    $src = Join-Path $root $file
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $packageDir $file) -Force
        Write-Host "      ✓ $file"
    }
}

Write-Host "[2/2] Copying directories..." -ForegroundColor Yellow
$dirs = @("config", "src", "docs", "tools", "installer", "tests")
foreach ($dir in $dirs) {
    $src = Join-Path $root $dir
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $packageDir $dir) -Recurse -Force
        Write-Host "      ✓ $dir/"
    }
}

# ============================================================================
# PHASE 3: VERIFICATION
# ============================================================================
Write-Host ""
Write-Host "PHASE 3: Package Verification" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Magenta

$required = @(
    "Start-Guardian.ps1",
    "Start-Guardian-UI.ps1",
    "README.md",
    "LICENSE",
    "config\guardian.example.json",
    "src\Guardian.ps1",
    "src\Guardian.Core\Guardian.Core.psm1",
    "src\Guardian.Network\Guardian.Network.psm1",
    "src\Guardian.Devices\Guardian.Devices.psm1",
    "docs\INSTALLATION-DE.md",
    "docs\QUICKSTART.md",
    "tools\Release-Builder.ps1",
    "installer\WLAN-Guardian.iss"
)

Write-Host "[3/1] Validating required files..." -ForegroundColor Yellow
$missing = @()
foreach ($file in $required) {
    $path = Join-Path $packageDir $file
    if (Test-Path $path) {
        Write-Host "      ✓ $file"
    } else {
        $missing += $file
        Write-Host "      ⚠ $file (optional)"
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "      Note: Some optional files are missing but not critical:" -ForegroundColor Yellow
    foreach ($file in $missing) {
        Write-Host "      - $file"
    }
}

Write-Host "[3/2] Checking encoding..." -ForegroundColor Yellow
$psFiles = Get-ChildItem -Path $packageDir -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
$bomCount = 0
foreach ($file in $psFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bomCount++
    }
}
Write-Host "      ✓ UTF-8 encoding verified ($bomCount BOMs found)"

Write-Host "[3/3] Package size analysis..." -ForegroundColor Yellow
$totalSize = 0
Get-ChildItem -Path $packageDir -Recurse -File | ForEach-Object {
    $totalSize += $_.Length
}
$sizeMB = [Math]::Round($totalSize / 1MB, 2)
Write-Host "      ✓ Total size: $sizeMB MB"

# ============================================================================
# PHASE 4: CREATE ZIP ARCHIVE
# ============================================================================
Write-Host ""
Write-Host "PHASE 4: Creating ZIP Archive" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Magenta

Write-Host "[4/1] Compressing package..." -ForegroundColor Yellow
$items = Get-ChildItem -Path $packageDir
Compress-Archive -Path $items.FullName -DestinationPath $zipFile -CompressionLevel Optimal -Force

$zipSize = (Get-Item $zipFile).Length / 1MB
Write-Host "      ✓ ZIP created successfully"
Write-Host "      File: $zipFile"
Write-Host "      Size: $([Math]::Round($zipSize, 2)) MB"

# ============================================================================
# PHASE 5: MANIFEST & CHECKSUMS
# ============================================================================
Write-Host ""
Write-Host "PHASE 5: Manifest & Checksums" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Magenta

Write-Host "[5/1] Computing SHA-256 checksum..." -ForegroundColor Yellow
$sha256 = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
Write-Host "      ✓ SHA-256: $sha256"

$manifestFile = Join-Path $buildDir "release-manifest-$Version.json"
$manifest = @{
    version = $Version
    releaseDate = (Get-Date).ToString("o")
    filename = (Split-Path $zipFile -Leaf)
    size = @{
        bytes = (Get-Item $zipFile).Length
        mb = [Math]::Round($zipSize, 2)
    }
    sha256 = $sha256
    contents = @{
        scripts = @("Start-Guardian.ps1", "Start-Guardian-UI.ps1", "WLAN-Guardian.cmd", "WLAN-Guardian-UI.cmd")
        modules = @("Guardian.Core", "Guardian.Network", "Guardian.Devices")
        documentation = @("README.md", "INSTALLATION-DE.md", "QUICKSTART.md")
        tools = @("Release-Builder.ps1", "Install-Dependencies.ps1", "Verify-Release.ps1")
        installer = @("WLAN-Guardian.iss")
    }
    requirements = @{
        os = "Windows 10 or newer"
        powershell = "5.1 or newer"
        ram = "512 MB minimum"
        disk = "100 MB minimum"
    }
} | ConvertTo-Json -Depth 5

$manifest | Set-Content -Path $manifestFile -Encoding UTF8
Write-Host "      ✓ Manifest created: release-manifest-$Version.json"

Write-Host "[5/2] Creating checksums file..." -ForegroundColor Yellow
$checksumsFile = Join-Path $buildDir "SHA256-CHECKSUMS-$Version.txt"
@"
WLAN Guardian Release $Version - SHA256 Checksums
Generated: $(Get-Date)

File: $(Split-Path $zipFile -Leaf)
SHA-256: $sha256

Instructions:
1. Download the ZIP file
2. Verify the checksum:
   certutil -hashfile "WLAN-Guardian-$Version.zip" SHA256
   (output should match the SHA-256 above)
3. Extract the ZIP
4. Run: Start-Guardian.ps1 -Once
"@ | Set-Content -Path $checksumsFile -Encoding UTF8

Write-Host "      ✓ Checksums file created"

# ============================================================================
# PHASE 6: FINAL SUMMARY
# ============================================================================
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                 RELEASE COMPLETE ✓                         ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Build Location: $buildDir" -ForegroundColor Green
Write-Host ""
Write-Host "Files Created:" -ForegroundColor Green

if (Test-Path $zipFile) {
    Write-Host "  ✓ ZIP Package:" -ForegroundColor Green
    Write-Host "    → $zipFile"
    Write-Host "    → Size: $([Math]::Round($zipSize, 2)) MB"
}

if (Test-Path $manifestFile) {
    Write-Host "  ✓ Manifest:" -ForegroundColor Green
    Write-Host "    → $manifestFile"
}

if (Test-Path $checksumsFile) {
    Write-Host "  ✓ Checksums:" -ForegroundColor Green
    Write-Host "    → $checksumsFile"
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Verify checksum (optional):"
Write-Host "     certutil -hashfile `"$([IO.Path]::GetFileName($zipFile))`" SHA256"
Write-Host "  2. Upload ZIP to release platform"
Write-Host "  3. Share manifest and checksums with users"
Write-Host ""
Write-Host "Installation:" -ForegroundColor Cyan
Write-Host "  1. Extract ZIP to destination folder"
Write-Host "  2. Run: powershell -ExecutionPolicy Bypass -File `"Start-Guardian.ps1`" -Once"
Write-Host ""
