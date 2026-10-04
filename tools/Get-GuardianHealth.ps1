<#
.SYNOPSIS
    Gesundheitspruefung fuer WLAN Guardian (H3).

.DESCRIPTION
    Prueft, ob die Ueberwachung lebt und ihre Daten brauchbar sind. Acht
    Einzelpruefungen, jede mit PASS, WARN oder FAIL:

      Config        laesst sich lesen und erfuellt die Mindestanforderungen
      Logordner     existiert und ist beschreibbar
      Ereignislog   existiert und ist nicht leer
      Aktualitaet   letztes Ereignis liegt innerhalb des erwarteten Fensters
      Kette         Hash-Kette laesst sich lueckenlos nachrechnen
      Groesse       aktives Segment liegt unter maxLogBytes
      Rotation      Segmentnummern sind lueckenlos, State-Dateien vorhanden
      Prozess       die Ein-Instanz-Sperre ist gehalten

    Exit-Codes: 0 alles PASS, 1 mindestens ein WARN, 2 mindestens ein FAIL.
    Damit ist das Skript direkt in einem Scheduled Task oder einem
    Ueberwachungssystem verwendbar.

    Die Pruefung "Aktualitaet" braucht einen laufenden oder kuerzlich
    beendeten Guardian. Nach einem einzelnen Lauf mit -Once ist das letzte
    Ereignis alt, dann ist WARN das erwartete Ergebnis und kein Fehler.

.PARAMETER ConfigPath
    Pfad zur Konfiguration. Default: config\guardian.example.json im Projekt.

.PARAMETER Quiet
    Nur das Ergebnisobjekt ausgeben, keine Einzelzeilen.

.EXAMPLE
    ./tools/Get-GuardianHealth.ps1

.EXAMPLE
    ./tools/Get-GuardianHealth.ps1 -Quiet | ConvertTo-Json
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Zwei Ebenen: diese Datei liegt in tools\, also Datei -> tools -> Projektwurzel.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root 'config\guardian.example.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $root $ConfigPath
}

# $script: ist bewusst gesetzt. Add-Pruefung ist eine Funktion, und ohne
# expliziten Scope haengt es davon ab, ob PowerShell die Variable aus dem
# uebergeordneten Scope sichtbar macht. Mit $script: ist das eindeutig.
$script:ergebnisse = [System.Collections.Generic.List[object]]::new()
function Add-Pruefung {
    param([string]$Name, [ValidateSet('PASS','WARN','FAIL')][string]$Status, [string]$Detail)
    $script:ergebnisse.Add([pscustomobject]@{ Pruefung = $Name; Status = $Status; Detail = $Detail })
    if (-not $Quiet) { Write-Host ("{0,-12} {1,-5} {2}" -f $Name, $Status, $Detail) }
}

function ConvertTo-GuardianInt {
    <#
        Wandelt einen Config-Wert in eine ganze Zahl, mit Rueckfall.

        [int]::TryParse(..., [ref]$var) ist hier bewusst nicht verwendet.
        Aufrufe mit [ref] haengen an der Ueberladungswahl und sind zwischen
        PowerShell 5.1 und 7 nicht verlaesslich. Ein regex-gepruefter Cast ist
        in beiden Versionen eindeutig.

        Korrektur vom 02.10.2026: Diese Stelle war NICHT die Ursache des
        Abbruchs im ersten echten Lauf. Die Meldung "Argument: 3 sollte ein
        System.Management.Automation.PSReference sein" kam von
        New-Object System.Threading.Mutex(...) in src/Guardian.ps1:358.
        Aufgedeckt hat das erst der direkte Aufruf von Start-Guardian.ps1,
        weil der die Zeile mit ausgibt; der Testlauf zeigte nur die Meldung
        ohne Ort, und die Suche ging deshalb zunaechst in die falsche Richtung.
    #>
    param([object]$Value, [int]$Default)

    $text = [string]$Value
    if ($text -notmatch '^\s*[+-]?[0-9]+\s*$') { return $Default }
    return [int]$text
}

# --- 1 Config -------------------------------------------------------------
$config = $null
$intervalSeconds = 0
$maxLogBytes = 5242880
$logDirectory = ''
try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "nicht gefunden: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    foreach ($pflicht in @('intervalSeconds', 'logDirectory')) {
        if ($null -eq $config.PSObject.Properties[$pflicht]) { throw "Schluessel fehlt: $pflicht" }
    }
    $intervalSeconds = ConvertTo-GuardianInt $config.intervalSeconds 0
    if ($intervalSeconds -lt 1) { throw "intervalSeconds muss groesser null sein: $($config.intervalSeconds)" }
    $logDirectory = [string]$config.logDirectory
    if ([string]::IsNullOrWhiteSpace($logDirectory)) { throw 'logDirectory ist leer' }
    if ($null -ne $config.PSObject.Properties['maxLogBytes'] -and $config.maxLogBytes) {
        $p = ConvertTo-GuardianInt $config.maxLogBytes 0
        if ($p -gt 0) { $maxLogBytes = $p }
    }
    Add-Pruefung 'Config' 'PASS' "$ConfigPath, intervalSeconds=$intervalSeconds"
}
catch {
    Add-Pruefung 'Config' 'FAIL' $_.Exception.Message
    # Ohne Config ist nichts Weiteres pruefbar.
    $zusammenfassung = [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        Ergebnis = 'FAIL'
        Pruefungen = $script:ergebnisse
    }
    if ($Quiet) { $zusammenfassung }
    exit 2
}

if (-not [System.IO.Path]::IsPathRooted($logDirectory)) {
    $logDirectory = Join-Path $root $logDirectory
}
$logFile = Join-Path $logDirectory 'guardian-events.jsonl'
$stateFile = Join-Path $logDirectory 'guardian-chain.json'

# --- 2 Logordner ----------------------------------------------------------
if (Test-Path -LiteralPath $logDirectory -PathType Container) {
    $probe = Join-Path $logDirectory ('.health-probe-' + [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -LiteralPath $probe -Value 'probe' -Encoding utf8
        Remove-Item -LiteralPath $probe -Force
        Add-Pruefung 'Logordner' 'PASS' "$logDirectory beschreibbar"
    }
    catch {
        Add-Pruefung 'Logordner' 'FAIL' "nicht beschreibbar: $($_.Exception.Message)"
    }
}
else {
    Add-Pruefung 'Logordner' 'FAIL' "fehlt: $logDirectory"
}

# --- 3 Ereignislog --------------------------------------------------------
$letzteZeile = $null
$zeilen = 0
if (Test-Path -LiteralPath $logFile -PathType Leaf) {
    $inhalt = @(Get-Content -LiteralPath $logFile | Where-Object { $_.Trim().Length -gt 0 })
    $zeilen = $inhalt.Count
    if ($zeilen -gt 0) {
        $letzteZeile = $inhalt[-1]
        Add-Pruefung 'Ereignislog' 'PASS' "$zeilen Zeilen in $logFile"
    }
    else {
        Add-Pruefung 'Ereignislog' 'WARN' 'Datei vorhanden, aber leer'
    }
}
else {
    Add-Pruefung 'Ereignislog' 'WARN' "noch kein Log unter $logFile - Guardian ist nie gelaufen"
}

# --- 4 Aktualitaet --------------------------------------------------------
if ($letzteZeile) {
    try {
        $stempel = [string]($letzteZeile | ConvertFrom-Json).timestamp
        # Kultur, Format und Zeitzone werden festgelegt. [datetime]::Parse($x)
        # allein benutzt die Kultur des Systems, und das hat am 03.10.2026 im
        # ersten gruenen Lauf auf einem deutschen Rechner danebengegriffen:
        # Der Zeitstempel 2026-10-03T05:58:22Z war Sekunden alt, gemeldet
        # wurden 17.884.801 s. Das sind 207 Tage und 1 Sekunde, also der
        # 10.03.2026 - Monat und Tag vertauscht. Die Pruefung war damit auf
        # jedem Rechner mit anderer Kultur anders falsch.
        #
        # Geschrieben wird mit (Get-Date).ToUniversalTime().ToString("o"),
        # also im Round-Trip-Format mit Z. InvariantCulture nimmt die Kultur
        # des Rechners aus dem Spiel, AdjustToUniversal und AssumeUniversal
        # stellen sicher, dass UTC herauskommt und nicht in Lokalzeit
        # umgerechnet wird - sonst stuende hier Local gegen UTC.
        $zeitstil = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                    [System.Globalization.DateTimeStyles]::AssumeUniversal
        $stempelZeit = [datetime]::Parse($stempel,
            [System.Globalization.CultureInfo]::InvariantCulture, $zeitstil)
        $alter = ((Get-Date).ToUniversalTime() - $stempelZeit).TotalSeconds
        # Toleranz: drei Intervalle plus eine Minute. Der Guardian schreibt erst
        # am Ende eines Intervalls, und ein Rechner kann aus dem Schlaf kommen.
        $grenze = ($intervalSeconds * 3) + 60
        if ($alter -le $grenze) {
            Add-Pruefung 'Aktualitaet' 'PASS' ("letztes Ereignis vor {0:n0} s, Grenze {1:n0} s" -f $alter, $grenze)
        }
        else {
            Add-Pruefung 'Aktualitaet' 'WARN' ("letztes Ereignis vor {0:n0} s, Grenze {1:n0} s - laeuft der Guardian?" -f $alter, $grenze)
        }
    }
    catch {
        Add-Pruefung 'Aktualitaet' 'FAIL' "Zeitstempel nicht lesbar: $($_.Exception.Message)"
    }
}

# --- 5 Kette --------------------------------------------------------------
function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

$kettenState = $stateFile
if (Test-Path -LiteralPath "$logFile.state.json" -PathType Leaf) { $kettenState = "$logFile.state.json" }
if ((Test-Path -LiteralPath $logFile -PathType Leaf) -and (Test-Path -LiteralPath $kettenState -PathType Leaf)) {
    try {
        $state = Get-Content -LiteralPath $kettenState -Raw | ConvertFrom-Json
        $recorded = ''
        if ($null -ne $state.PSObject.Properties['CurrentHash']) { $recorded = [string]$state.CurrentHash }
        elseif ($null -ne $state.PSObject.Properties['hash']) { $recorded = [string]$state.hash }
        else { throw 'State-Datei hat weder CurrentHash noch hash' }

        $previous = ''
        foreach ($zeile in (Get-Content -LiteralPath $logFile | Where-Object { $_.Trim().Length -gt 0 })) {
            $previous = Get-Sha256Text ($previous + $zeile)
        }
        if ($previous -eq $recorded) {
            Add-Pruefung 'Kette' 'PASS' "$zeilen Zeilen nachgerechnet, Kopf stimmt"
        }
        else {
            Add-Pruefung 'Kette' 'FAIL' 'Kette gebrochen - Log wurde veraendert oder zwei Schreibpfade haben geteilt'
        }
    }
    catch {
        Add-Pruefung 'Kette' 'FAIL' $_.Exception.Message
    }
}
elseif (Test-Path -LiteralPath $logFile -PathType Leaf) {
    Add-Pruefung 'Kette' 'WARN' "keine State-Datei zu $logFile"
}

# --- 6 Groesse ------------------------------------------------------------
if (Test-Path -LiteralPath $logFile -PathType Leaf) {
    $groesse = (Get-Item -LiteralPath $logFile).Length
    if ($groesse -le $maxLogBytes) {
        Add-Pruefung 'Groesse' 'PASS' ("{0:n0} von {1:n0} Bytes" -f $groesse, $maxLogBytes)
    }
    else {
        Add-Pruefung 'Groesse' 'WARN' ("{0:n0} Bytes ueber dem Limit von {1:n0} - Rotation greift beim naechsten Ereignis" -f $groesse, $maxLogBytes)
    }
}

# --- 7 Rotation -----------------------------------------------------------
$segmente = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'guardian-events.jsonl.*' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^guardian-events\.jsonl\.\d+$' })
if ($segmente.Count -eq 0) {
    Add-Pruefung 'Rotation' 'PASS' 'noch keine Segmente, das ist vor der ersten Rotation korrekt'
}
else {
    $nummern = @($segmente | ForEach-Object { [int]($_.Name -replace '^guardian-events\.jsonl\.', '') } | Sort-Object)
    $erwartet = 1..($nummern.Count)
    $lueckenlos = $true
    for ($i = 0; $i -lt $nummern.Count; $i++) {
        if ($nummern[$i] -ne $erwartet[$i]) { $lueckenlos = $false }
    }
    $ohneState = @($nummern | Where-Object { -not (Test-Path -LiteralPath "$logFile.$_.state.json" -PathType Leaf) })
    if ($lueckenlos -and $ohneState.Count -eq 0) {
        Add-Pruefung 'Rotation' 'PASS' "$($segmente.Count) Segmente, lueckenlos, jede State-Datei vorhanden"
    }
    elseif (-not $lueckenlos) {
        Add-Pruefung 'Rotation' 'FAIL' "Segmentnummern nicht lueckenlos: $($nummern -join ', ')"
    }
    else {
        Add-Pruefung 'Rotation' 'FAIL' "State-Datei fehlt fuer Segment: $($ohneState -join ', ')"
    }
}

# --- 8 Prozess ------------------------------------------------------------
# Die Ein-Instanz-Sperre im Kern heisst WLAN-Guardian-Einziger-Lauf. Ist sie
# gehalten, laeuft ein Guardian. OpenExisting wirft, wenn nicht.
# Der Kern bindet den Namen an das Log, also muss diese Pruefung denselben
# Namen bilden. Get-Sha256Text ist baugleich zu Get-Sha256 im Kern, und
# ToLowerInvariant kommt dazu, weil Windows-Pfade die Gross- und
# Kleinschreibung nicht unterscheiden.
$mutexName = 'WLAN-Guardian-Einziger-Lauf-' + (Get-Sha256Text $logFile.ToLowerInvariant()).Substring(0, 16)
$laufend = $false
foreach ($praefix in @('Global\', 'Local\')) {
    try {
        $m = [System.Threading.Mutex]::OpenExisting($praefix + $mutexName)
        $m.Dispose()
        $laufend = $true
        break
    }
    catch { continue }
}
if ($laufend) {
    Add-Pruefung 'Prozess' 'PASS' 'Ein-Instanz-Sperre ist gehalten, Guardian laeuft'
}
else {
    Add-Pruefung 'Prozess' 'WARN' 'kein laufender Guardian erkannt'
}

# --- Zusammenfassung ------------------------------------------------------
$fail = @($script:ergebnisse | Where-Object { $_.Status -eq 'FAIL' }).Count
$warn = @($script:ergebnisse | Where-Object { $_.Status -eq 'WARN' }).Count
$pass = @($script:ergebnisse | Where-Object { $_.Status -eq 'PASS' }).Count
$gesamt = if ($fail -gt 0) { 'FAIL' } elseif ($warn -gt 0) { 'WARN' } else { 'PASS' }

if (-not $Quiet) {
    Write-Host ''
    Write-Host "PASS $pass   WARN $warn   FAIL $fail   ERGEBNIS: $gesamt"
}

# Ohne -Quiet gehoert das Objekt nicht in die Ausgabe - sonst steht die ganze
# Liste zusaetzlich zu den Einzelzeilen auf der Konsole und verdeckt das
# Ergebnis. Im ersten echten Lauf war sie sichtbar.
if ($Quiet) {
    [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        Ergebnis = $gesamt
        Pass = $pass
        Warn = $warn
        Fail = $fail
        Pruefungen = $script:ergebnisse
    }
}

if ($fail -gt 0) { exit 2 }
if ($warn -gt 0) { exit 1 }
exit 0
