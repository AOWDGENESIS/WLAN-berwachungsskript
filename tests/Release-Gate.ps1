$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$checks = @(
    (Join-Path $root "Start-Guardian.ps1"),
    (Join-Path $root "WLAN-Guardian.cmd"),
    (Join-Path $root "src\Guardian.ps1"),
    (Join-Path $root "src\Guardian-Devices.ps1"),
    (Join-Path $root "src\Guardian.UI\Guardian.UI.ps1"),
    (Join-Path $root "config\guardian.example.json"),
    (Join-Path $root "installer\WLAN-Guardian.iss")
)
foreach ($path in $checks) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing: $path" }
    Write-Host "FILE: PASS $path"
}

$config = Get-Content (Join-Path $root "config\guardian.example.json") -Raw | ConvertFrom-Json
if ([int]$config.intervalSeconds -lt 1) { throw "Invalid intervalSeconds" }
if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) { throw "Invalid logDirectory" }

$scripts = Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1,*.psm1
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "PowerShell syntax error in $($script.FullName)" }
}

$smokeRoot = Join-Path ([IO.Path]::GetTempPath()) ("wlan-guardian-gate-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
try {
    $smokeConfig = Join-Path $smokeRoot "guardian.json"
    $smokeJson = @{
        version = 1
        intervalSeconds = 1
        testHost = "127.0.0.1"
        dnsName = "localhost"
        logDirectory = (Join-Path $smokeRoot "logs")
    } | ConvertTo-Json
    [IO.File]::WriteAllText($smokeConfig, $smokeJson, [Text.UTF8Encoding]::new($false))
    & (Join-Path $root "src\Guardian.ps1") -Once -ConfigPath $smokeConfig | Out-Null
    if (-not (Test-Path (Join-Path $smokeRoot "logs\guardian-events.jsonl"))) {
        throw "Smoke test did not write an event log"
    }
} finally {
    if (Test-Path $smokeRoot) { Remove-Item $smokeRoot -Recurse -Force }
}
Write-Host "Configuration: PASS"
Write-Host "Smoke test: PASS"
Write-Host "Release gate: PASS"
