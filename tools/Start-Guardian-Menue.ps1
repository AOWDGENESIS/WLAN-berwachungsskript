<#
.SYNOPSIS
    Einstiegspunkt fuer WLAN Guardian: installieren, pruefen, ueberwachen.

.DESCRIPTION
    Dieses Skript ist das, was WLAN-Guardian-Start.bat aufruft. Die Batchdatei
    ist bewusst duenn gehalten - sie sucht nur den Interpreter und haelt am Ende
    das Fenster offen. Saemtliche Logik steht hier, weil sie sich in PowerShell
    pruefen laesst und in Batch nicht.

    Ohne Argument oeffnet sich ein Menue. Mit Argument wird die Aktion direkt
    ausgefuehrt, also auch aus der Eingabeaufforderung heraus:

        WLAN-Guardian-Start.bat              Menue
        WLAN-Guardian-Start.bat status       einmal pruefen
        WLAN-Guardian-Start.bat ueberwachen  Dauerueberwachung
        WLAN-Guardian-Start.bat start        Daemon starten
        WLAN-Guardian-Start.bat stop         Daemon stoppen
        WLAN-Guardian-Start.bat ui           Oberflaeche oeffnen
        WLAN-Guardian-Start.bat log          letzte Ereignisse
        WLAN-Guardian-Start.bat install      neu installieren
        WLAN-Guardian-Start.bat deinstall    sichern und entfernen

.EXAMPLE
    ./tools/Start-Guardian-Menue.ps1
    ./tools/Start-Guardian-Menue.ps1 -Aktion ueberwachen
#>
param(
    [string]$Aktion = '',
    [int]$IntervallSekunden = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:taskDaemon = 'WLAN Guardian'
$script:taskTray = 'WLAN Guardian UI'
# Der Installer merkt sich hier, wohin installiert wurde. Ohne diese Notiz
# wuesste dieses Skript nach einem Doppelklick nicht, welche Installation es
# ueberwachen soll - der Zielordner wird ja im Dialog frei gewaehlt.
$script:markerVerzeichnis = Join-Path $env:LOCALAPPDATA 'WLAN-Guardian'
$script:marker = Join-Path $script:markerVerzeichnis 'install-pfad.txt'
# Wird auf den Exit-Code des Installers oder der Gesundheitspruefung gesetzt,
# damit WLAN-Guardian-Start.bat denselben Code meldet und nicht immer 0.
$script:fehler = 0

# --- Helfer ---------------------------------------------------------------
# Dieselben drei Helfer wie in src\Guardian.UI\ und src\Guardian.Tray\. Sie
# stehen hier ein drittes Mal, weil alle drei Skripte als eigene Prozesse
# laufen und keiner den anderen importiert. Get-Sha256Text ist baugleich zu
# Get-Sha256 im Kern: UTF8, SHA-256, Bindestriche weg, klein geschrieben.

function Get-Feld {
    param($Objekt, [string]$Name, [string]$Standard = '-')
    if ($null -eq $Objekt) { return $Standard }
    $eigenschaft = $Objekt.PSObject.Properties[$Name]
    if ($null -eq $eigenschaft) { return $Standard }
    if ($null -eq $eigenschaft.Value) { return $Standard }
    $wert = [string]$eigenschaft.Value
    if ([string]::IsNullOrWhiteSpace($wert)) { return $Standard }
    return $wert
}

function Get-Sha256Text {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-DaemonLaeuft {
    param([string]$LogPfad)
    $name = 'WLAN-Guardian-Einziger-Lauf-' + (Get-Sha256Text $LogPfad.ToLowerInvariant()).Substring(0, 16)
    foreach ($praefix in @('Global\', 'Local\')) {
        try {
            $m = [System.Threading.Mutex]::OpenExisting($praefix + $name)
            $m.Dispose()
            return $true
        }
        catch { continue }
    }
    return $false
}

function Get-InstallationsPfad {
    if (Test-Path -LiteralPath $script:marker -PathType Leaf) {
        $gemerkt = (Get-Content -LiteralPath $script:marker -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($gemerkt) -and (Test-Path -LiteralPath $gemerkt -PathType Container)) {
            return $gemerkt
        }
    }
    # Keine Notiz: Die gesuchte Installation steht vielleicht schon als
    # Autostart da. Der Task traegt sein Arbeitsverzeichnis, und das ist die
    # Wurzel der Installation - dieselbe Quelle, aus der der Installer in
    # Schritt 3 den alten Ordner ermittelt. Ohne diesen Schritt zeigte das
    # Menue am 05.10.2026 auf den entpackten Kit-Ordner, und die
    # Zustandspruefung meldete FAIL, waehrend der echte Daemon laengst lief.
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        $task = @(Get-ScheduledTask -TaskName $script:taskDaemon -ErrorAction SilentlyContinue)
        if ($task.Count -gt 0) {
            $aktionen = @($task[0].Actions)
            if ($aktionen.Count -gt 0) {
                # Ueber PSObject.Properties: Nicht jeder Aktionstyp traegt ein
                # Arbeitsverzeichnis, und unter Set-StrictMode wirft der
                # Zugriff auf eine nicht vorhandene Eigenschaft.
                $eigenschaft = $aktionen[0].PSObject.Properties['WorkingDirectory']
                if ($null -ne $eigenschaft) {
                    $wd = [string]$eigenschaft.Value
                    if (-not [string]::IsNullOrWhiteSpace($wd) -and (Test-Path -LiteralPath $wd -PathType Container)) {
                        return $wd
                    }
                }
            }
        }
    }
    # Zuletzt der Ort dieses Skripts. Das trifft zu, sobald es aus dem
    # installierten Ordner heraus aufgerufen wird.
    return $script:root
}

function Get-ConfigPfad {
    param([string]$Installation)
    $fest = Join-Path $Installation 'config\guardian.json'
    if (Test-Path -LiteralPath $fest -PathType Leaf) { return $fest }
    return (Join-Path $Installation 'config\guardian.example.json')
}

function Get-LogPfad {
    param([string]$Installation, [string]$ConfigPfad)
    $vorgabe = Join-Path $Installation 'artifacts\guardian-events.jsonl'
    if (-not (Test-Path -LiteralPath $ConfigPfad -PathType Leaf)) { return $vorgabe }
    try { $konfiguration = (Get-Content -LiteralPath $ConfigPfad -Raw | ConvertFrom-Json) }
    catch { return $vorgabe }
    $verzeichnis = Get-Feld -Objekt $konfiguration -Name 'logDirectory' -Standard 'artifacts'
    if ($verzeichnis -eq '-') { $verzeichnis = 'artifacts' }
    if (-not [System.IO.Path]::IsPathRooted($verzeichnis)) {
        $verzeichnis = Join-Path $Installation $verzeichnis
    }
    return (Join-Path $verzeichnis 'guardian-events.jsonl')
}

function Get-Zustand {
    $installation = Get-InstallationsPfad
    $config = Get-ConfigPfad -Installation $installation
    $log = Get-LogPfad -Installation $installation -ConfigPfad $config
    $zustand = 'unbekannt'
    $ssid = '-'
    $ipv4 = '-'
    $internet = '-'
    $zeit = '-'
    $ereignisse = 0
    $bytes = 0
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $bytes = (Get-Item -LiteralPath $log).Length
        $zeilen = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
        $ereignisse = $zeilen.Count
        if ($zeilen.Count -gt 0) {
            try {
                $objekt = $zeilen[$zeilen.Count - 1] | ConvertFrom-Json
                $zustand = Get-Feld -Objekt $objekt -Name 'status' -Standard 'unbekannt'
                $ssid = Get-Feld -Objekt $objekt -Name 'ssid'
                $ipv4 = Get-Feld -Objekt $objekt -Name 'ipv4'
                $internet = Get-Feld -Objekt $objekt -Name 'internetOk'
                $roh = Get-Feld -Objekt $objekt -Name 'timestamp' -Standard ''
                if (-not [string]::IsNullOrWhiteSpace($roh)) {
                    try {
                        $zeit = ([datetime]::Parse($roh, [System.Globalization.CultureInfo]::InvariantCulture,
                            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                            [System.Globalization.DateTimeStyles]::AssumeUniversal)).ToLocalTime().ToString('HH:mm:ss')
                    }
                    catch { $zeit = $roh }
                }
            }
            catch { }
        }
    }
    return [pscustomobject]@{
        Installation = $installation
        Config       = $config
        Log          = $log
        Zustand      = $zustand
        Ssid         = $ssid
        Ipv4         = $ipv4
        Internet     = $internet
        Zeit         = $zeit
        Ereignisse   = $ereignisse
        Bytes        = $bytes
        Laeuft       = (Test-DaemonLaeuft -LogPfad $log)
    }
}

function Write-Zeile {
    param($Z)
    $daemon = if ($Z.Laeuft) { 'laeuft  ' } else { 'GESTOPPT' }
    Write-Host ('{0}  {1,-8} {2,-14} {3,-15} Internet={4,-5} Daemon={5}  {6,9:N0} B  {7,5} Ereignisse' -f `
        $Z.Zeit, $Z.Zustand, $Z.Ssid, $Z.Ipv4, $Z.Internet, $daemon, $Z.Bytes, $Z.Ereignisse)
}

# --- Aktionen -------------------------------------------------------------

function Invoke-Installation {
    param([switch]$Deinstallieren, [switch]$KeinWiederherstellungspunkt)
    $installer = Join-Path $script:root 'tools\Install-Guardian.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Installer fehlt: $installer" }
    $schalter = @()
    if ($Deinstallieren) { $schalter += '-Deinstallieren' }
    if ($KeinWiederherstellungspunkt) { $schalter += '-KeinWiederherstellungspunkt' }
    # $global:LASTEXITCODE vor dem Aufruf auf 0 und danach auswerten - dieselbe
    # Reihenfolge wie in Test-All.ps1. Ein mit & aufgerufenes Skript beendet den
    # Aufrufer nicht; ohne das Vorbelegen stuende hier noch der Wert eines
    # frueheren Programms, und ein Fehlschlag waere unsichtbar.
    $global:LASTEXITCODE = 0
    & $installer @schalter
    if ($LASTEXITCODE -ne 0) {
        $script:fehler = $LASTEXITCODE
        Write-Host ''
        Write-Host ('Der Installer meldete Exit-Code ' + $LASTEXITCODE + '.') -ForegroundColor Yellow
    }
}

function Invoke-Pruefung {
    $z = Get-Zustand
    $health = Join-Path $z.Installation 'tools\Get-GuardianHealth.ps1'
    if (-not (Test-Path -LiteralPath $health -PathType Leaf)) { throw "Gesundheitspruefung fehlt: $health" }
    $global:LASTEXITCODE = 0
    Push-Location $z.Installation
    try { & $health -ConfigPath $z.Config }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { $script:fehler = $LASTEXITCODE }
}

function Invoke-Ueberwachung {
    param([int]$Sekunden)
    $z = Get-Zustand
    Write-Host ('Installation : ' + $z.Installation)
    Write-Host ('Logdatei     : ' + $z.Log)
    Write-Host ('Alle ' + $Sekunden + ' Sekunden. Beenden mit Q oder Strg+C.')
    Write-Host ''
    while ($true) {
        Write-Zeile -Z (Get-Zustand)
        # KeyAvailable wirft, wenn die Eingabe umgelenkt ist - etwa wenn das
        # Skript nicht interaktiv laeuft. Dann wird einfach nicht auf Q gehoert.
        try {
            if ([Console]::KeyAvailable) {
                $taste = [Console]::ReadKey($true)
                if ($taste.Key -eq 'Q') { break }
            }
        }
        catch { }
        Start-Sleep -Seconds $Sekunden
    }
}

function Invoke-Start {
    Start-ScheduledTask -TaskName $script:taskDaemon
    Write-Host ("Task '" + $script:taskDaemon + "' gestartet.")
    Start-Sleep -Seconds 5
    Write-Zeile -Z (Get-Zustand)
}

function Invoke-Stopp {
    try { Stop-ScheduledTask -TaskName $script:taskDaemon -ErrorAction Stop } catch { }
    # Nur Prozesse mit Start-Guardian.ps1 in der Befehlszeile. Ein pauschales
    # Get-Process pwsh | Stop-Process wuerde offene Konsolen toeten.
    $prozesse = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Start-Guardian.ps1*' })
    foreach ($p in $prozesse) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
    Write-Host 'Daemon gestoppt.'
    Start-Sleep -Seconds 2
    Write-Zeile -Z (Get-Zustand)
}

function Invoke-Oberflaeche {
    $z = Get-Zustand
    $ui = Join-Path $z.Installation 'src\Guardian.UI\Guardian.UI.ps1'
    if (-not (Test-Path -LiteralPath $ui -PathType Leaf)) { throw "Oberflaeche fehlt: $ui" }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $ui, '-ConfigPath', $z.Config, '-TaskName', $script:taskDaemon
    ) -WindowStyle Hidden
    Write-Host 'Oberflaeche geoeffnet.'
}

function Invoke-Protokoll {
    param([int]$Anzahl = 20)
    $z = Get-Zustand
    Write-Host ('Logdatei: ' + $z.Log)
    if (-not (Test-Path -LiteralPath $z.Log -PathType Leaf)) {
        Write-Host 'Es gibt noch keine Logdatei. Der Daemon ist vermoetlich nie gelaufen.'
        return
    }
    $zeilen = @(Get-Content -LiteralPath $z.Log -Tail $Anzahl -ErrorAction SilentlyContinue)
    if ($zeilen.Count -eq 0) { Write-Host 'Die Logdatei ist leer.'; return }
    Write-Host ''
    foreach ($zeile in $zeilen) {
        try {
            $o = $zeile | ConvertFrom-Json
            Write-Host ('{0}  {1,-14} {2,-14} {3,-15} dns={4,-5} internet={5,-5} {6}' -f `
                (Get-Feld -Objekt $o -Name 'timestamp'), (Get-Feld -Objekt $o -Name 'status'),
                (Get-Feld -Objekt $o -Name 'ssid'), (Get-Feld -Objekt $o -Name 'ipv4'),
                (Get-Feld -Objekt $o -Name 'dnsOk'), (Get-Feld -Objekt $o -Name 'internetOk'),
                (Get-Feld -Objekt $o -Name 'event' -Standard ''))
        }
        catch { Write-Host $zeile }
    }
}

# --- Menue ----------------------------------------------------------------

function Show-Menue {
    while ($true) {
        $z = Get-Zustand
        Write-Host ''
        Write-Host '=== WLAN Guardian ==='
        Write-Host ('  Installation : ' + $z.Installation)
        Write-Host ('  Zustand      : ' + $z.Zustand + '   Daemon: ' + $(if ($z.Laeuft) { 'laeuft' } else { 'gestoppt' }))
        Write-Host ''
        Write-Host '  1  Neu installieren oder aktualisieren'
        Write-Host '  2  Zustand pruefen (acht Pruefungen)'
        Write-Host ('  3  Dauerueberwachung, alle ' + $IntervallSekunden + ' Sekunden')
        Write-Host '  4  Daemon starten'
        Write-Host '  5  Daemon stoppen'
        Write-Host '  6  Oberflaeche oeffnen'
        Write-Host '  7  Letzte 20 Ereignisse anzeigen'
        Write-Host '  8  Deinstallieren, mit ZIP-Sicherung'
        Write-Host '  9  Installieren OHNE Wiederherstellungspunkt'
        Write-Host '  0  Beenden'
        Write-Host ''
        $wahl = Read-Host 'Auswahl'
        switch ($wahl) {
            '1' { Invoke-Installation }
            '2' { Invoke-Pruefung }
            '3' { Invoke-Ueberwachung -Sekunden $IntervallSekunden }
            '4' { Invoke-Start }
            '5' { Invoke-Stopp }
            '6' { Invoke-Oberflaeche }
            '7' { Invoke-Protokoll }
            '8' { Invoke-Installation -Deinstallieren }
            '9' { Invoke-Installation -KeinWiederherstellungspunkt }
            '0' { return }
            default { Write-Host 'Diese Auswahl gibt es nicht.' }
        }
    }
}

# --- Einstieg -------------------------------------------------------------

switch ($Aktion.Trim().ToLowerInvariant()) {
    '' { Show-Menue }
    'install' { Invoke-Installation }
    'neu' { Invoke-Installation }
    'status' { Invoke-Pruefung }
    'pruefen' { Invoke-Pruefung }
    'ueberwachen' { Invoke-Ueberwachung -Sekunden $IntervallSekunden }
    'monitor' { Invoke-Ueberwachung -Sekunden $IntervallSekunden }
    'start' { Invoke-Start }
    'stop' { Invoke-Stopp }
    'ui' { Invoke-Oberflaeche }
    'oberflaeche' { Invoke-Oberflaeche }
    'log' { Invoke-Protokoll }
    'deinstall' { Invoke-Installation -Deinstallieren }
    'ohnepunkt' { Invoke-Installation -KeinWiederherstellungspunkt }
    'deinstallieren' { Invoke-Installation -Deinstallieren }
    default {
        Write-Host "Unbekannte Aktion: $Aktion"
        Write-Host 'Moeglich sind: install, ohnepunkt, status, ueberwachen, start, stop, ui, log, deinstall'
        exit 1
    }
}
exit $script:fehler
