<#
.SYNOPSIS
    Verifiziert eine Guardian Hash-Chain.

.DESCRIPTION
    Liest ein JSONL-Eventlog Zeile fuer Zeile, berechnet die Kette neu und
    vergleicht sie mit der State-Datei. Beide im Projekt verwendeten Formate
    werden erkannt:

      src/Guardian.ps1            -> guardian-chain.json      {hash, previous}
      src/Guardian.Evidence/...   -> <log>.state.json         {CurrentHash, PreviousHash}

    Der Kettenalgorithmus ist SHA256(previous + jsonZeile), genau wie in
    src/Guardian.ps1 und src/Guardian.Evidence/Guardian.Evidence.psm1.

.PARAMETER LogPath
    Pfad zur JSONL-Datei.

.PARAMETER StatePath
    Pfad zur State-Datei. Default: bei Evidence-Konvention <LogPath>.state.json,
    sonst guardian-chain.json im selben Verzeichnis.

.PARAMETER SelfTest
    Erzeugt eine synthetische Kette, verifiziert sie, bricht sie danach
    bewusst und verlangt, dass der Bruch erkannt wird. Benoetigt kein WLAN,
    kein Windows-Netzwerk-Cmdlet und laeuft damit auch unter Linux/CI.

.EXAMPLE
    ./tests/Verify-Chain.ps1 -SelfTest

.EXAMPLE
    ./tests/Verify-Chain.ps1 -LogPath .\artifacts\guardian-events.jsonl
#>
[CmdletBinding()]
param(
    [string]$LogPath = '',
    [string]$StatePath = '',
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Read-GuardianState {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "FAIL: State file not found: $Path"
    }

    $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    if ($null -ne ($state.PSObject.Properties['CurrentHash'])) {
        return [string]$state.CurrentHash
    }
    if ($null -ne ($state.PSObject.Properties['hash'])) {
        return [string]$state.hash
    }
    throw "FAIL: State file has neither CurrentHash nor hash: $Path"
}

function Test-GuardianChain {
    <#
        Gibt die Anzahl der verifizierten Zeilen zurueck und wirft bei jedem
        Bruch. Erwarteter Kettenstart ist der leere String.
    #>
    param(
        [Parameter(Mandatory)][string]$Log,
        [Parameter(Mandatory)][string]$State
    )

    if (-not (Test-Path -LiteralPath $Log -PathType Leaf)) {
        throw "FAIL: Event log not found: $Log"
    }

    $lines = @(Get-Content -LiteralPath $Log | Where-Object { $_.Trim().Length -gt 0 })
    if ($lines.Count -eq 0) {
        throw "FAIL: Event log is empty: $Log"
    }

    $previous = ''
    $index = 0
    foreach ($line in $lines) {
        $index++
        $expected = Get-Sha256Text ($previous + $line)
        $previous = $expected
    }

    $recorded = Read-GuardianState -Path $State
    if ($recorded -ne $previous) {
        throw "FAIL: Chain broken at line $index. recomputed=$previous recorded=$recorded"
    }

    Write-Host "CHAIN: PASS lines=$index head=$previous"
    return $index
}

function Invoke-SelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("guardian-chain-selftest-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $log = Join-Path $temp 'guardian-events.jsonl'
        $state = Join-Path $temp 'guardian-chain.json'

        # Kette aufbauen, exakt wie src/Guardian.ps1 das tut.
        $previous = ''
        foreach ($i in 1..3) {
            $json = [pscustomobject]@{ timestamp = "2026-09-24T00:00:0$i.0000000Z"; status = 'ONLINE'; seq = $i } |
                ConvertTo-Json -Compress -Depth 8
            Add-Content -LiteralPath $log -Value $json -Encoding utf8
            $previous = Get-Sha256Text ($previous + $json)
        }
        [pscustomobject]@{ hash = $previous; previous = '' } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $state -Encoding utf8

        $count = Test-GuardianChain -Log $log -State $state
        if ($count -ne 3) { throw "FAIL: selftest expected 3 lines, verified $count" }

        # Bewusster Bruch: eine Zeile manipulieren. Das MUSS auffallen.
        $lines = @(Get-Content -LiteralPath $log)
        $lines[1] = $lines[1] -replace '"ONLINE"', '"TAMPERED"'
        Set-Content -LiteralPath $log -Value $lines -Encoding utf8

        $detected = $false
        try {
            Test-GuardianChain -Log $log -State $state | Out-Null
        }
        catch {
            $detected = $true
            Write-Host "TAMPER: PASS detected ($($_.Exception.Message.Split('.')[0]))"
        }
        if (-not $detected) { throw 'FAIL: tampered chain was not detected' }

        Write-Host 'Self test: PASS'
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    throw 'FAIL: -LogPath is required unless -SelfTest is used.'
}

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $evidenceState = "$LogPath.state.json"
    if (Test-Path -LiteralPath $evidenceState -PathType Leaf) {
        $StatePath = $evidenceState
    }
    else {
        $StatePath = Join-Path (Split-Path -Parent $LogPath) 'guardian-chain.json'
    }
}

Test-GuardianChain -Log $LogPath -State $StatePath | Out-Null
exit 0
