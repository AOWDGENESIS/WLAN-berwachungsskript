<#
.SYNOPSIS
    Ein-Klick-Testlauf fuer WLAN Guardian.

.DESCRIPTION
    Fuehrt alle Gates des Projekts nacheinander aus und meldet am Ende eine
    Tabelle. Jeder einzelne Fehlschlag wird erfasst, der Lauf bricht nicht beim
    ersten Fehler ab. Exit-Code ist die Anzahl der fehlgeschlagenen Pruefungen.

    Pruefungen:
      1. Release-Gate          Pflichtdateien und Konfigurationsgueltigkeit
      2. Hash-Chain Selbsttest Kette aufbauen, pruefen, bewusst brechen
      3. KIT-HASHES            Manifest gegen den Ist-Baum
      4. Kodierung             kein UTF8-BOM, reines ASCII in *.ps1/*.psm1
      5. Werkzeuge             Health Check und Autostart im Berichtsmodus
      6. End-to-End            echten Lauf mit -Once, danach Chain verifizieren

    Schritt 5 ruft die Werkzeuge ohne -Install und ohne -Quiet auf. Beide sind
    im Berichtsmodus ungefaehrlich, aber ein Absturz in ihnen wird hier
    sichtbar - der [ref]-Fehler vom 02.10.2026 sass in genau einem davon.

    Schritt 6 braucht Windows mit Netzwerk-Cmdlets. Auf anderen Systemen wird
    er als UEBERSPRUNGEN gewertet und zaehlt nicht als Fehler.

.PARAMETER SkipEndToEnd
    Schritt 6 auslassen.

.EXAMPLE
    ./Test-All.ps1

.EXAMPLE
    ./Test-All.ps1 -SkipEndToEnd
#>
[CmdletBinding()]
param(
    [switch]$SkipEndToEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Outcome,
        [string]$Detail = ''
    )
    $results.Add([pscustomobject]@{ Pruefung = $Name; Ergebnis = $Outcome; Detail = $Detail })
    Write-Host ("{0,-24} {1,-5} {2}" -f $Name, $Outcome, $Detail)
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    Write-Host ""
    Write-Host "--- $Name ---"
    try {
        & $Body
        Add-Result -Name $Name -Outcome 'PASS'
    }
    catch {
        # Nur die Meldung zu zeigen hat am 02.10.2026 in die Irre gefuehrt. Der
        # erste echte Lauf meldete "Argument: 3 sollte ein
        # System.Management.Automation.PSReference sein" ohne Ortsangabe, und
        # die Ursache wurde daraufhin in TryParse-Aufrufen gesucht. Sie lag in
        # New-Object System.Threading.Mutex(...) in src/Guardian.ps1:358 -
        # aufgedeckt hat das erst der direkte Aufruf von Start-Guardian.ps1,
        # weil der die Position mit ausgibt. Eine Meldung ohne Datei und Zeile
        # ist bei dieser Klasse von Fehler praktisch nicht zuordbar.
        $ort = ''
        if ($null -ne $_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
            $ort = " [$($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)]"
        }
        Add-Result -Name $Name -Outcome 'FAIL' -Detail ($_.Exception.Message + $ort)
    }
}

Write-Host "WLAN Guardian Testlauf"
Write-Host "Root: $root"
Write-Host "PowerShell: $($PSVersionTable.PSVersion) auf $([System.Environment]::OSVersion.Platform)"

Invoke-Step -Name 'Release-Gate' -Body {
    # Release-Gate.ps1 ruft kein exit auf. Ohne Reset bleibt der Exit-Code des
    # Vorgaengers stehen - beim Deploy-Skript war das robocopy mit Code 3,
    # was dort ein Erfolg ist. Das Gate war gruen und wurde rot gemeldet.
    $global:LASTEXITCODE = 0
    & (Join-Path $root 'tests/Release-Gate.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Release-Gate Exit-Code $LASTEXITCODE" }
}

Invoke-Step -Name 'Hash-Chain Selbsttest' -Body {
    $global:LASTEXITCODE = 0
    & (Join-Path $root 'tests/Verify-Chain.ps1') -SelfTest
    if ($LASTEXITCODE -ne 0) { throw "Verify-Chain Exit-Code $LASTEXITCODE" }
}

Invoke-Step -Name 'KIT-HASHES' -Body {
    $global:LASTEXITCODE = 0
    & (Join-Path $root 'tools/New-KitHashes.ps1') -Check
    if ($LASTEXITCODE -ne 0) { throw "New-KitHashes Exit-Code $LASTEXITCODE" }
}

Invoke-Step -Name 'Kodierung' -Body {
    $bad = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1, *.psm1 | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bad.Add("BOM: $($_.Name)")
        }
        foreach ($b in $bytes) {
            if ($b -gt 126) { $bad.Add("NICHT-ASCII: $($_.Name)"); break }
        }
    }
    if ($bad.Count -gt 0) { throw ($bad -join '; ') }
    Write-Host 'Kein BOM, reines ASCII.'
}

Invoke-Step -Name 'Werkzeuge' -Body {
    # Die Werkzeuge kamen in diesem Testlauf bisher nicht vor. Beide sind im
    # Berichtsmodus ungefaehrlich, aber ein Absturz in ihnen waere sonst erst
    # beim manuellen Aufruf aufgefallen.
    #
    # Beide Werkzeuge sind im Berichtsmodus ungefaehrlich: die
    # Gesundheitspruefung liest nur und schreibt eine GUID-Probe in das
    # Logverzeichnis, der Autostart richtet ohne -Install nichts ein und
    # meldet nur den Zustand des geplanten Tasks.
    #
    # Erlaubt sind die Exit-Codes, die die Skripte selbst setzen: 0, 1 und 2.
    # Ein unbehandelter Fehler - genau die Klasse, um die es hier geht - landet
    # im catch von Invoke-Step und wird als FAIL gewertet.
    foreach ($werkzeug in @('tools/Get-GuardianHealth.ps1', 'tools/Set-GuardianAutostart.ps1')) {
        $pfad = Join-Path $root $werkzeug
        if (-not (Test-Path -LiteralPath $pfad -PathType Leaf)) { throw "$werkzeug fehlt" }
        $global:LASTEXITCODE = 0
        # Die Ausgabe wird aufgefangen statt durchgereicht, damit die Tabelle am
        # Ende lesbar bleibt. @(...) deshalb, weil .Count auf $null unter
        # Set-StrictMode -Version Latest wirft.
        $ausgabe = & $pfad
        if ($LASTEXITCODE -notin 0, 1, 2) {
            throw "$werkzeug lief nicht durch, Exit-Code $LASTEXITCODE"
        }
        Write-Host "$werkzeug lief durch, Exit-Code $LASTEXITCODE, $(@($ausgabe).Count) Zeilen"
    }
}

if ($SkipEndToEnd) {
    Add-Result -Name 'End-to-End' -Outcome 'SKIP' -Detail '-SkipEndToEnd'
}
else {
    Invoke-Step -Name 'End-to-End' -Body {
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
            throw 'SKIPMARK Get-NetAdapter nicht verfuegbar'
        }

        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("guardian-e2e-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            $base = Get-Content -LiteralPath (Join-Path $root 'config/guardian.example.json') -Raw | ConvertFrom-Json
            $base.logDirectory = $temp
            $base.intervalSeconds = 1
            $configPath = Join-Path $temp 'guardian.test.json'
            $base | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding utf8

            $global:LASTEXITCODE = 0
            & (Join-Path $root 'Start-Guardian.ps1') -Once -ConfigPath $configPath
            if ($LASTEXITCODE -ne 0) { throw "Start-Guardian Exit-Code $LASTEXITCODE" }

            $log = Join-Path $temp 'guardian-events.jsonl'
            if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { throw "Eventlog wurde nicht erzeugt: $log" }
            $lineCount = @(Get-Content -LiteralPath $log | Where-Object { $_.Trim().Length -gt 0 }).Count
            if ($lineCount -lt 1) { throw 'Eventlog ist leer' }

            $global:LASTEXITCODE = 0
            & (Join-Path $root 'tests/Verify-Chain.ps1') -LogPath $log
            if ($LASTEXITCODE -ne 0) { throw "Chain-Verifikation Exit-Code $LASTEXITCODE" }

            Write-Host "Echter Lauf erzeugt $lineCount Event(s), Kette intakt."
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $e2e = $results | Where-Object { $_.Pruefung -eq 'End-to-End' } | Select-Object -Last 1
    if ($null -ne $e2e -and $e2e.Detail -like 'SKIPMARK*') {
        $e2e.Ergebnis = 'SKIP'
        $e2e.Detail = 'Netzwerk-Cmdlets nicht verfuegbar (kein Windows)'
    }
}

# Log-Rotation (C6). Bisher war sie nur statisch geprueft und nie gelaufen. Sie
# wird hier ueber echte -Once-Laeufe ausgeloest statt nachgebaut: Ein Lauf
# schreibt rund 380 Bytes, mit maxLogBytes = 200 rotiert das Log also schon
# beim zweiten Lauf. maxLogFiles = 2 macht zusaetzlich die Obergrenze pruefbar.
if ($SkipEndToEnd) {
    Add-Result -Name 'Rotation' -Outcome 'SKIP' -Detail '-SkipEndToEnd'
}
else {
    Invoke-Step -Name 'Rotation' -Body {
        if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
            throw 'SKIPMARK Get-NetAdapter nicht verfuegbar'
        }

        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("guardian-rot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        try {
            $base = Get-Content -LiteralPath (Join-Path $root 'config/guardian.example.json') -Raw | ConvertFrom-Json
            $base.logDirectory = $temp
            $base.intervalSeconds = 1
            $base.maxLogBytes = 200
            $base.maxLogFiles = 2
            $configPath = Join-Path $temp 'guardian.test.json'
            $base | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding utf8

            $log = Join-Path $temp 'guardian-events.jsonl'
            $laeufe = 6
            $dreiGesehen = $false
            for ($lauf = 1; $lauf -le $laeufe; $lauf++) {
                $global:LASTEXITCODE = 0
                & (Join-Path $root 'Start-Guardian.ps1') -Once -ConfigPath $configPath
                if ($LASTEXITCODE -ne 0) { throw "Start-Guardian Exit-Code $LASTEXITCODE in Lauf $lauf" }
                # Nach jedem Lauf ansehen, nicht erst am Ende: Ein Segment, das
                # kurz existiert und dann geloescht wird, waere sonst unsichtbar.
                if (Test-Path -LiteralPath "$log.3") { $dreiGesehen = $true }
            }

            if (-not (Test-Path -LiteralPath "$log.1" -PathType Leaf)) {
                throw 'Nach sechs Laeufen ist kein Segment .1 entstanden, die Rotation greift nicht'
            }
            if (-not (Test-Path -LiteralPath "$log.2" -PathType Leaf)) {
                throw 'Segment .2 fehlt, die Verschiebekette laeuft nicht durch'
            }
            if ($dreiGesehen) {
                throw 'Segment .3 ist entstanden, obwohl maxLogFiles auf 2 steht'
            }

            $state = Join-Path $temp 'guardian-events.jsonl.1.state.json'
            if (-not (Test-Path -LiteralPath $state -PathType Leaf)) {
                throw 'Segment .1 hat keine State-Datei, seine Kette waere nicht mehr pruefbar'
            }
            $kopf = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
            if ([string]$kopf.PreviousHash -ne '') {
                throw "State-Datei des Segments nennt einen PreviousHash: $($kopf.PreviousHash)"
            }
            if ([string]$kopf.CurrentHash -notmatch '^[0-9a-f]{64}$') {
                throw "CurrentHash des Segments ist keine SHA-256: $($kopf.CurrentHash)"
            }

            # Jedes Segment muss fuer sich eine geschlossene Kette haben, sonst
            # ist der Nachweis nach der Rotation nichts wert.
            $global:LASTEXITCODE = 0
            & (Join-Path $root 'tests/Verify-Chain.ps1') -LogPath $log
            if ($LASTEXITCODE -ne 0) { throw "Kette im aktuellen Log bricht, Exit-Code $LASTEXITCODE" }
            $global:LASTEXITCODE = 0
            & (Join-Path $root 'tests/Verify-Chain.ps1') -LogPath "$log.1"
            if ($LASTEXITCODE -ne 0) { throw "Kette im Segment .1 bricht, Exit-Code $LASTEXITCODE" }

            $teile = @(Get-ChildItem -LiteralPath $temp -Filter 'guardian-events.jsonl*' |
                Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Length)" })
            Write-Host "$laeufe Laeufe, Segmente: $($teile -join ', ')"
            Write-Host 'Obergrenze maxLogFiles=2 gehalten, beide Ketten intakt.'
        }
        finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $rot = $results | Where-Object { $_.Pruefung -eq 'Rotation' } | Select-Object -Last 1
    if ($null -ne $rot -and $rot.Detail -like 'SKIPMARK*') {
        $rot.Ergebnis = 'SKIP'
        $rot.Detail = 'Netzwerk-Cmdlets nicht verfuegbar (kein Windows)'
    }
}

Write-Host ''
Write-Host '============================================='
$results | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($results | Where-Object { $_.Ergebnis -eq 'FAIL' })
$skipped = @($results | Where-Object { $_.Ergebnis -eq 'SKIP' })
$passed = @($results | Where-Object { $_.Ergebnis -eq 'PASS' })

Write-Host ("PASS {0}   FAIL {1}   SKIP {2}" -f $passed.Count, $failed.Count, $skipped.Count)

if ($failed.Count -gt 0) {
    Write-Host 'ERGEBNIS: FAIL'
    exit $failed.Count
}
Write-Host 'ERGEBNIS: PASS'
exit 0
