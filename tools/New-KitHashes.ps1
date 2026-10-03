<#
.SYNOPSIS
    Erzeugt KIT-HASHES.json neu aus dem tatsaechlichen Stand des Repositorys.

.DESCRIPTION
    KIT-HASHES.json ist der Integritaetsnachweis des Kits. Er muss vor jedem
    Release neu erzeugt werden, sonst driftet er vom Baum weg. Genau das war
    am 2026-09-23 passiert: 31 Manifesteintraege gegen 22 Dateien, 4
    Hashkonflikte.

    Ignoriert werden .git, artifacts, build, cache und alles, was .gitignore
    ausschliesst, sowie KIT-HASHES.json selbst.

.PARAMETER Root
    Repository-Root. Default: uebergeordnetes Verzeichnis von tools/.

.EXAMPLE
    ./tools/New-KitHashes.ps1

.EXAMPLE
    ./tools/New-KitHashes.ps1 -Check    # prueft nur, schreibt nichts
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [System.IO.Path]::GetFullPath($Root)

$excludeDirs = @('.git', 'artifacts', 'build', 'cache')
$manifestPath = Join-Path $Root 'KIT-HASHES.json'

$entries = Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object {
        $relative = $_.FullName.Substring($Root.Length).TrimStart([IO.Path]::DirectorySeparatorChar)
        $parts = $relative.Split([IO.Path]::DirectorySeparatorChar)
        # @() ist Pflicht: liefert Where-Object nichts, ist das Ergebnis $null,
        # und unter Set-StrictMode -Version Latest wirft $null.Count.
        @($parts | Where-Object { $excludeDirs -contains $_ }).Count -eq 0
    } |
    ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length).TrimStart([IO.Path]::DirectorySeparatorChar).Replace('\', '/')
        if ($relative -eq 'KIT-HASHES.json') { return $null }
        [pscustomobject]@{
            path   = $relative
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes  = $_.Length
        }
    } |
    Where-Object { $null -ne $_ } |
    Sort-Object path

$manifest = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffzzz')
    files         = @($entries)
}
$json = $manifest | ConvertTo-Json -Depth 6

if ($Check) {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "FAIL: KIT-HASHES.json fehlt" }
    $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $expected = @($entries | ForEach-Object { "$($_.path) $($_.sha256) $($_.bytes)" })
    $actual = @($existing.files | ForEach-Object { "$($_.path) $($_.sha256) $($_.bytes)" })
    $diff = Compare-Object -ReferenceObject $expected -DifferenceObject $actual
    if ($null -ne $diff) {
        $diff | ForEach-Object { Write-Host "DRIFT: $($_.SideIndicator) $($_.InputObject)" }
        throw "FAIL: KIT-HASHES.json driftet vom Baum ($(@($diff).Count) Unterschiede). Bitte ./tools/New-KitHashes.ps1 ausfuehren."
    }
    Write-Host "KIT-HASHES: PASS ($(@($expected).Count) Dateien)"
    exit 0
}

# [Typ]::new() statt der New-Object-Kurzform. Die Kurzform hat am
# 02.10.2026 den ersten echten Lauf unter PowerShell 7.6.6 bei
# System.Threading.Mutex abbrechen lassen; siehe src/Guardian.ps1.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, $utf8NoBom)
Write-Host "KIT-HASHES: geschrieben, $(@($entries).Count) Dateien -> $manifestPath"
