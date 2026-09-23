param([string]$ReleaseRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $root
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) { $ReleaseRoot = Join-Path $projectRoot "build\WLAN-Guardian-1.0.0" }
$release = [IO.Path]::GetFullPath($ReleaseRoot)
if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "Release root not found: $release" }

$required = @("Start-Guardian.ps1", "WLAN-Guardian.cmd", "README.md", "LICENSE", "src\Guardian.ps1", "config\guardian.example.json")
foreach ($relative in $required) {
    $path = Join-Path $release $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required release file missing: $relative" }
}

$config = Get-Content (Join-Path $release "config\guardian.example.json") -Raw | ConvertFrom-Json
if ([int]$config.version -lt 1) { throw "Unsupported configuration version" }
if ([int]$config.intervalSeconds -lt 1) { throw "intervalSeconds must be positive" }

$ps = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($null -eq $ps) { throw "Windows PowerShell is required" }

Get-ChildItem -LiteralPath $release -Recurse -File | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "UTF8 BOM found: $($_.FullName)"
    }
}
Write-Host "Release validation: PASS"
