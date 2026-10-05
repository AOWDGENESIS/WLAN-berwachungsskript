<#
.SYNOPSIS
    WLAN Guardian frisch installieren, mit freiem Pfad und Sicherung vorab.

.DESCRIPTION
    Fuehrt in dieser Reihenfolge aus:

      1. Administratorrechte anfordern, falls noch nicht vorhanden.
      2. Installationsordner abfragen, bevor irgendetwas veraendert wird.
      3. Windows-Wiederherstellungspunkt anlegen.
      4. Alte Ereignisdaten und Config als ZIP in die Dokumente sichern.
      5. Alten Daemon beenden, alten Autostart entfernen, alten Ordner loeschen.
      6. Die Dateien in den gewaehlten Ordner kopieren.
      7. Config mit absolutem logDirectory schreiben.
      8. Autostart fuer den Daemon und fuer das Tray-Symbol einrichten.
      9. Daemon starten, Zustand pruefen, Tray und Oberflaeche oeffnen.

    Der Zielordner wird zuerst abgefragt und nicht erst nach dem Aufraeumen:
    Bricht der Nutzer den Dialog ab, ist noch nichts geloescht, und es ist kein
    Wiederherstellungspunkt verbraucht - Windows legt von sich aus hoechstens
    einen pro 24 Stunden an.

    Der Wiederherstellungspunkt braucht Administratorrechte, Checkpoint-Computer
    laeuft ohne Erhoehung nicht. Der Daemon selbst und das Tray-Symbol laufen
    weiterhin mit begrenzten Rechten.

.PARAMETER InstallDir
    Zielordner. Ohne Angabe wird ein Ordnerdialog geoeffnet.

.PARAMETER Deinstallieren
    Nur sichern und entfernen, nichts installieren.

.PARAMETER KeinWiederherstellungspunkt
    Ueberspringt Schritt 2. Ohne diese Angabe bricht der Installer ab, wenn der
    Wiederherstellungspunkt nicht angelegt werden kann.

.EXAMPLE
    ./tools/Install-Guardian.ps1
    ./tools/Install-Guardian.ps1 -InstallDir D:\WLAN-Guardian
    ./tools/Install-Guardian.ps1 -Deinstallieren
#>
[CmdletBinding()]
param(
    [string]$InstallDir = '',
    [switch]$Deinstallieren,
    [switch]$KeinWiederherstellungspunkt,
    [switch]$KeinTray,
    [string]$ProtokollPfad = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskNameDaemon = 'WLAN Guardian'
$taskNameTray = 'WLAN Guardian UI'
$stempel = (Get-Date).ToString('yyyy-MM-dd-HHmmss')

# Start-Process -Wait gibt den Exit-Code des erhoehten Kindes nicht zurueck.
# Damit der aufrufende Prozess trotzdem weiss, ob es geklappt hat, schreibt
# das Kind diese Datei - und zwar nur an seinen beiden erfolgreichen Enden.
function Write-Erfolgsmeldung {
    if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) {
        [System.IO.File]::WriteAllText(($ProtokollPfad + '.ok'), 'ok',
            [System.Text.UTF8Encoding]::new($false))
    }
}

function Request-InstallDir {
    # Gibt den gewaehlten Zielordner zurueck, oder eine leere Zeichenkette,
    # wenn weder Dialog noch Eingabe einen Ordner geliefert haben.
    param([string]$Quelle)
    $vorgabe = Join-Path $env:USERPROFILE 'WLAN-Guardian'
    # Der Ordnerdialog gehoert keinem Fenster und kann deshalb hinter dem
    # Konsolenfenster liegen. Ohne Hinweis sieht das aus wie ein Haenger -
    # am 05.10.2026 blieb der echte Lauf genau hier stehen. Deshalb wird
    # vorher gesagt, was kommt, und hinterher gibt es die Eingabe per Text
    # als Ausweg, falls das Fenster nicht zu finden ist.
    Write-Host ''
    Write-Host '      Es oeffnet sich jetzt ein Fenster zur Ordnerwahl.' -ForegroundColor Cyan
    Write-Host '      Liegt es hinter diesem Fenster, einmal auf die Taskleiste klicken.' -ForegroundColor Cyan
    Write-Host ('      Ohne Auswahl wird vorgeschlagen: ' + $vorgabe)
    $dialogFehler = $null
    $gewaehlt = ''
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Wohin soll WLAN Guardian installiert werden?'
        # UseDescriptionForTitle gibt es erst ab .NET Core 3, also in Windows
        # PowerShell 5.1 nicht. Unter Set-StrictMode wuerde das Setzen einer
        # nicht vorhandenen Eigenschaft werfen, deshalb wird erst gefragt.
        if ($dialog.PSObject.Properties['UseDescriptionForTitle']) { $dialog.UseDescriptionForTitle = $true }
        $dialog.ShowNewFolderButton = $true
        $dialog.SelectedPath = $vorgabe
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $gewaehlt = $dialog.SelectedPath
        }
    }
    catch {
        $dialogFehler = $_.Exception.Message
    }
    if ([string]::IsNullOrWhiteSpace($gewaehlt)) {
        if ($null -ne $dialogFehler) {
            Write-Host ('      Der Ordnerdialog lief nicht: ' + $dialogFehler) -ForegroundColor Yellow
        }
        else {
            Write-Host '      Kein Ordner gewaehlt.' -ForegroundColor Yellow
        }
        Write-Host '      Der Ordner laesst sich auch hier eintippen.'
        $eingabe = Read-Host ('      Pfad eingeben, oder Enter fuer ' + $vorgabe)
        if ([string]::IsNullOrWhiteSpace($eingabe)) { $eingabe = $vorgabe }
        # Anfuehrungszeichen abziehen: Pfade mit Leerzeichen werden beim
        # Einfuegen aus dem Explorer oft mitgebracht. Die Zeichen stehen hier
        # als [char], damit die Zeile keine ungerade Zahl an Anfuehrungs-
        # zeichen enthaelt - die Kodierungspruefung zaehlt sie pro Zeile.
        $zitat = [string]::new([char[]](34, 39))
        $gewaehlt = $eingabe.Trim().Trim($zitat.ToCharArray())
    }
    if ([string]::IsNullOrWhiteSpace($gewaehlt)) { return '' }
    $voll = [System.IO.Path]::GetFullPath($gewaehlt)
    # Der Installer darf sich nicht selbst ueberschreiben: Die Quelle liegt im
    # entpackten Kit, und wuerde sie mit dem Ziel zusammenfallen, loeschte der
    # Aufraeumschritt die Dateien, aus denen kopiert werden soll.
    if ([string]::Equals($voll.TrimEnd('\'), $Quelle.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Installationsordner und Quellordner sind derselbe: $voll"
    }
    return $voll
}

function Test-Administrator {
    $identitaet = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identitaet)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- 1 Installationsordner bestimmen, bevor Erhoehung und Aenderung -------
# Diese Abfrage laeuft bewusst im nicht erhoehten Prozess. Im erhoehten Kind
# liegt der Ordnerdialog in einem anderen Konsolenfenster und ist leicht zu
# uebersehen; hier erscheint er in genau dem Fenster, das der Nutzer sieht.
# Ausserdem wird der Weg damit vor der UAC-Abfrage geklaert und nicht danach.
if (-not $Deinstallieren -and [string]::IsNullOrWhiteSpace($InstallDir)) {
    $quelleWrapper = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    Write-Host ''
    Write-Host '[1/8] Bestimme den Installationsordner ...'
    $InstallDir = Request-InstallDir -Quelle $quelleWrapper
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        Write-Host 'Kein Ordner bestimmt. Abbruch, es wurde nichts installiert.'
        exit 1
    }
    Write-Host ('      Ziel: ' + $InstallDir)
}

# --- Erhoehung ------------------------------------------------------------
# Der Installer braucht Administratorrechte fuer den Wiederherstellungspunkt.
# Das erhoehte Kind schreibt seine Ausgabe in eine Datei, und dieses Fenster
# gibt sie danach aus - sonst laege der ganze Bericht in einem Fenster, das
# sich mit dem Kindprozess schliesst.
if (-not (Test-Administrator)) {
    $interpreterEigen = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($ProtokollPfad)) {
        $ProtokollPfad = Join-Path ([System.IO.Path]::GetTempPath()) ("wlan-guardian-install-" + [guid]::NewGuid().ToString('N') + '.txt')
    }
    $argumente = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ProtokollPfad', $ProtokollPfad)
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) { $argumente += @('-InstallDir', $InstallDir) }
    if ($Deinstallieren) { $argumente += '-Deinstallieren' }
    if ($KeinWiederherstellungspunkt) { $argumente += '-KeinWiederherstellungspunkt' }
    if ($KeinTray) { $argumente += '-KeinTray' }

    Write-Host 'Der Installer braucht Administratorrechte.'
    Write-Host 'Grund: Ein Windows-Wiederherstellungspunkt laesst sich nur mit Erhoehung anlegen.'
    Write-Host 'Es erscheint jetzt eine UAC-Abfrage.'
    Write-Host ''
    $erfolgsmeldung = $ProtokollPfad + '.ok'
    Remove-Item -LiteralPath $erfolgsmeldung -Force -ErrorAction SilentlyContinue
    try {
        Start-Process -FilePath $interpreterEigen -ArgumentList $argumente -Verb RunAs -Wait
    }
    catch {
        Write-Host "Erhoehung abgelehnt oder fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host 'Ohne Erhoehung gibt es keinen Wiederherstellungspunkt. Zwei Wege:'
        Write-Host '  - PowerShell als Administrator starten und dieses Skript erneut aufrufen'
        Write-Host '  - mit -KeinWiederherstellungspunkt aufrufen, dann entfaellt Schritt 2'
        exit 1
    }
    $erfolgreich = (Test-Path -LiteralPath $erfolgsmeldung)
    Remove-Item -LiteralPath $erfolgsmeldung -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $ProtokollPfad) {
        Write-Host ''
        Write-Host '===== Bericht aus dem erhoehten Lauf ====='
        Get-Content -LiteralPath $ProtokollPfad | ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $ProtokollPfad -Force -ErrorAction SilentlyContinue
    }
    if (-not $erfolgreich) {
        Write-Host ''
        Write-Host 'Der erhoehte Lauf hat NICHT erfolgreich abgeschlossen.' -ForegroundColor Yellow
        Write-Host 'Die Ursache steht im Bericht oben. Es wurde kein Erfolg gemeldet.'
        exit 1
    }
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) {
    Start-Transcript -Path $ProtokollPfad -Force | Out-Null
}

# Diese Datei liegt in tools\, die Quelle ist also eine Ebene hoeher.
$quelle = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host '=== WLAN Guardian Installation ==='
Write-Host ('Quelle      : ' + $quelle)
Write-Host ('Zeitstempel : ' + $stempel)
Write-Host ''

# --- 1 Installationsordner bestimmen, bevor etwas veraendert wird --------

if (-not $Deinstallieren) {
Write-Host ''
Write-Host '[1/8] Bestimme den Installationsordner ...'
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    # Nur erreicht, wenn das Skript direkt ohne -InstallDir aufgerufen wurde.
    # Ueber das Menue steht der Ordner zu diesem Zeitpunkt schon fest.
    $InstallDir = Request-InstallDir -Quelle $quelle
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        Write-Host 'Kein Ordner bestimmt. Abbruch, es wurde nichts installiert.'
        if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) { Stop-Transcript | Out-Null }
        exit 1
    }
    Write-Host ('      Ziel: ' + $InstallDir)
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)

# Der Installer darf sich nicht selbst ueberschreiben: Die Quelle liegt im
# entpackten Kit, und wuerde sie mit dem Ziel zusammenfallen, loeschte Schritt 4
# die Dateien, aus denen kopiert werden soll.
if ([string]::Equals($InstallDir.TrimEnd('\'), $quelle.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Installationsordner und Quellordner sind derselbe: $InstallDir"
}

if (-not (Test-Path -LiteralPath $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Beschreibbar muss er sein, und zwar ohne Erhoehung: Der Daemon laeuft mit
# begrenzten Rechten und schreibt sein Log in diesen Ordner.
$probe = Join-Path $InstallDir ('.schreibprobe-' + [guid]::NewGuid().ToString('N'))
try {
    [System.IO.File]::WriteAllText($probe, 'probe', [System.Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath $probe -Force
}
catch {
    throw "Der Ordner ist ohne Administratorrechte nicht beschreibbar: $InstallDir - $($_.Exception.Message)"
}
Write-Host ('      Ziel: ' + $InstallDir)

# Diese Probe laeuft mit Administratorrechten und beweist deshalb nur, dass der
# Ordner ueberhaupt beschreibbar ist - nicht, dass der Daemon dort schreiben
# darf. Der Daemon laeuft mit begrenzten Rechten. Ein Ordner ausserhalb des
# Benutzerprofils kann Rechte haben, die das verhindern; die endgueltige
# Auskunft gibt die Gesundheitspruefung in Schritt 8.
$profil = [System.IO.Path]::GetFullPath($env:USERPROFILE)
if (-not $InstallDir.StartsWith($profil, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ''
    Write-Host '      Hinweis: Dieser Ordner liegt ausserhalb Ihres Benutzerprofils.' -ForegroundColor Yellow
    Write-Host '      Der Daemon laeuft ohne Erhoehung und muss dort sein Log schreiben koennen.'
    Write-Host ('      Ein Ordner unter ' + $profil + ' funktioniert immer.')
    Write-Host '      Die Gesundheitspruefung in Schritt 8 zeigt, ob es geklappt hat.'
}
}

# --- 2 Wiederherstellungspunkt -------------------------------------------

if ($KeinWiederherstellungspunkt) {
    Write-Host '[2/8] Wiederherstellungspunkt uebersprungen (-KeinWiederherstellungspunkt)'
}
else {
    Write-Host '[2/8] Lege einen Windows-Wiederherstellungspunkt an ...'
    Write-Host '      Das kann bis zu einer Minute dauern.'
    try {
        Checkpoint-Computer -Description ("WLAN Guardian Installation " + $stempel) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Host '      Wiederherstellungspunkt angelegt.'
    }
    catch {
        Write-Host ''
        Write-Host "      Wiederherstellungspunkt fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ''
        Write-Host '      Diagnose, beide Befehle sind nur lesend:'
        Write-Host '        Get-ComputerRestorePoint | Select-Object -Last 3'
        Write-Host '        (Get-CimInstance -ClassName SystemRestoreConfig -Namespace root\default `'
        Write-Host '          -Property RPSessionInterval).RPSessionInterval'
        Write-Host '      Steht dort 0, ist der Computerschutz fuer das Systemlaufwerk aus.'
        Write-Host ''
        Write-Host '      Zweiter haeufiger Grund: Windows legt von sich aus hoechstens einen Punkt'
        Write-Host '      pro 24 Stunden an. Aufheben laesst sich das mit dem DWORD-Wert'
        Write-Host '      SystemRestorePointCreationFrequency = 0 unter'
        Write-Host '      HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        Write-Host ''
        Write-Host '      vssadmin list shadows zeigt Schattenkopien und keine'
        Write-Host '      Wiederherstellungspunkte - das ist nicht dasselbe.'
        Write-Host ''
        Write-Host '      Es wurde noch nichts veraendert. Zwei Wege weiter:'
        Write-Host '        - Computerschutz einschalten und erneut aufrufen'
        Write-Host '        - mit -KeinWiederherstellungspunkt aufrufen'
        if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) { Stop-Transcript | Out-Null }
        exit 1
    }
}

# --- 3 Alte Installation finden ------------------------------------------

Write-Host ''
Write-Host '[3/8] Suche eine vorhandene Installation ...'
$kandidaten = @()
$taskAlt = @(Get-ScheduledTask -TaskName $taskNameDaemon -ErrorAction SilentlyContinue)
if ($taskAlt.Count -gt 0) {
    $aktionen = @($taskAlt[0].Actions)
    if ($aktionen.Count -gt 0) {
        # Ueber PSObject.Properties und nicht direkt: Nicht jeder Aktionstyp
        # traegt ein Arbeitsverzeichnis, und unter Set-StrictMode wirft der
        # Zugriff auf eine nicht vorhandene Eigenschaft.
        $eigenschaft = $aktionen[0].PSObject.Properties['WorkingDirectory']
        if ($null -ne $eigenschaft -and -not [string]::IsNullOrWhiteSpace([string]$eigenschaft.Value)) {
            $kandidaten += [string]$eigenschaft.Value
        }
    }
}
$kandidaten += (Join-Path $env:USERPROFILE 'WLAN-Guardian')

$altOrdner = @()
foreach ($k in $kandidaten) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }
    if (-not (Test-Path -LiteralPath $k -PathType Container)) { continue }
    $voll = [System.IO.Path]::GetFullPath($k)
    if ($altOrdner -contains $voll) { continue }
    $altOrdner += $voll
}

if ($altOrdner.Count -eq 0) {
    Write-Host '      Keine vorhandene Installation gefunden.'
}
else {
    foreach ($o in $altOrdner) { Write-Host ('      gefunden: ' + $o) }
}

# --- 4 Alte Daten sichern -------------------------------------------------

Write-Host ''
Write-Host '[4/8] Sichere alte Ereignisdaten und Config ...'
$dokumente = [Environment]::GetFolderPath('MyDocuments')
$sicherungsZip = Join-Path $dokumente ("WLAN-Guardian-Sicherung-" + $stempel + '.zip')
$anzahlGesichert = 0

if ($altOrdner.Count -eq 0) {
    Write-Host '      Nichts zu sichern.'
}
else {
    $buehne = Join-Path ([System.IO.Path]::GetTempPath()) ("wlan-guardian-sicherung-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $buehne -Force | Out-Null
    try {
        foreach ($o in $altOrdner) {
            $name = Split-Path -Leaf $o
            foreach ($unter in @('artifacts', 'config')) {
                $von = Join-Path $o $unter
                if (-not (Test-Path -LiteralPath $von -PathType Container)) { continue }
                $nach = Join-Path (Join-Path $buehne $name) $unter
                New-Item -ItemType Directory -Path $nach -Force | Out-Null
                foreach ($datei in @(Get-ChildItem -LiteralPath $von -Recurse -File -Force)) {
                    $relativ = $datei.FullName.Substring($von.Length + 1)
                    $zielDatei = Join-Path $nach $relativ
                    $zielOrdner = Split-Path -Parent $zielDatei
                    if (-not (Test-Path -LiteralPath $zielOrdner)) { New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null }
                    Copy-Item -LiteralPath $datei.FullName -Destination $zielDatei -Force
                    $anzahlGesichert++
                }
            }
        }
        if ($anzahlGesichert -gt 0) {
            Compress-Archive -Path (Join-Path $buehne '*') -DestinationPath $sicherungsZip -CompressionLevel Optimal -Force
            Write-Host ("      $anzahlGesichert Datei(en) gesichert nach:")
            Write-Host ('      ' + $sicherungsZip)
        }
        else {
            Write-Host '      Weder artifacts noch config enthielten Dateien.'
        }
    }
    finally {
        Remove-Item -LiteralPath $buehne -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- 5 Alten Daemon beenden und Autostart entfernen -----------------------

Write-Host ''
Write-Host '[5/8] Beende alten Daemon und entferne alten Autostart ...'
foreach ($t in @($taskNameDaemon, $taskNameTray)) {
    if (@(Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue).Count -gt 0) {
        try { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } catch { }
    }
}
Start-Sleep -Seconds 2
# Beide Interpreternamen, nicht nur pwsh.exe. Dieses Skript traegt weiter
# unten powershell.exe in den Autostart ein, wenn pwsh.exe nicht im PATH ist -
# ein Filter auf pwsh.exe allein haette dann nichts gefunden und der alte
# Daemon haette das Loeschen seines eigenen Ordners blockiert.
# Dazu die Bindung an Start-Guardian.ps1 oder Guardian.Tray.ps1 in der
# Befehlszeile: Ein pauschales Get-Process pwsh | Stop-Process wuerde auch
# offene Konsolen des Nutzers toeten.
$prozesse = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*Start-Guardian.ps1*' -or $_.CommandLine -like '*Guardian.Tray.ps1*' })
foreach ($p in $prozesse) {
    Write-Host ('      beende Prozess ' + $p.ProcessId)
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
}
Start-Sleep -Seconds 2
foreach ($t in @($taskNameDaemon, $taskNameTray)) {
    if (@(Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue).Count -gt 0) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host ('      Autostart entfernt: ' + $t)
    }
}

# --- 6 Alten Ordner loeschen ---------------------------------------------

foreach ($o in $altOrdner) {
    if (Test-Path -LiteralPath $o) {
        try {
            Remove-Item -LiteralPath $o -Recurse -Force -ErrorAction Stop
            Write-Host ('      Ordner geloescht: ' + $o)
        }
        catch {
            Write-Host ("      Ordner konnte nicht geloescht werden: $o - $($_.Exception.Message)") -ForegroundColor Yellow
        }
    }
}

if ($Deinstallieren) {
    $marker = Join-Path (Join-Path $env:LOCALAPPDATA 'WLAN-Guardian') 'install-pfad.txt'
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        Write-Host ('      Notiz entfernt: ' + $marker)
    }
    Write-Host ''
    Write-Host 'Deinstallation abgeschlossen. Es wurde nichts neu installiert.'
    Write-Host ('Sicherung: ' + $sicherungsZip)
    Write-Erfolgsmeldung
    if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) { Stop-Transcript | Out-Null }
    exit 0
}

# --- 7 Dateien kopieren ---------------------------------------------------

Write-Host ''
Write-Host '[6/8] Kopiere die Dateien ...'
$anzahlKopiert = 0
foreach ($datei in @(Get-ChildItem -LiteralPath $quelle -Recurse -File -Force)) {
    $relativ = $datei.FullName.Substring($quelle.Length + 1)
    # .git, artifacts und build gehoeren nicht in eine Installation.
    if ($relativ -match '(^|\\)(\.git|artifacts|build)(\\|$)') { continue }
    $zielDatei = Join-Path $InstallDir $relativ
    $zielOrdner = Split-Path -Parent $zielDatei
    if (-not (Test-Path -LiteralPath $zielOrdner)) { New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null }
    Copy-Item -LiteralPath $datei.FullName -Destination $zielDatei -Force
    $anzahlKopiert++
}
Write-Host ("      $anzahlKopiert Datei(en) kopiert.")

# Config mit absolutem logDirectory. Ein relativer Wert wurde im Kern gegen
# Get-Location und in der Gesundheitspruefung gegen die Projektwurzel
# aufgeloest - zwei verschiedene Pfade, sobald der Task aus einem anderen
# Arbeitsverzeichnis startet. Mit einem absoluten Pfad gibt es diesen
# Spielraum nicht mehr.
$artifacts = Join-Path $InstallDir 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

$beispiel = Join-Path $InstallDir 'config\guardian.example.json'
if (-not (Test-Path -LiteralPath $beispiel -PathType Leaf)) { throw "Config-Vorlage fehlt: $beispiel" }
$konfiguration = Get-Content -LiteralPath $beispiel -Raw | ConvertFrom-Json
$konfiguration.logDirectory = $artifacts
$configZiel = Join-Path $InstallDir 'config\guardian.json'
[System.IO.File]::WriteAllText($configZiel, ($konfiguration | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-Host ('      Config geschrieben: ' + $configZiel)
Write-Host ('      logDirectory absolut: ' + $artifacts)

# Notiz fuer tools\Start-Guardian-Menue.ps1. Der Zielordner wird frei gewaehlt,
# und die Batchdatei weiss nach einem Doppelklick nicht, welche Installation
# sie ueberwachen soll. Ohne diese Notiz muesste sie raten.
$markerVerzeichnis = Join-Path $env:LOCALAPPDATA 'WLAN-Guardian'
if (-not (Test-Path -LiteralPath $markerVerzeichnis)) {
    New-Item -ItemType Directory -Path $markerVerzeichnis -Force | Out-Null
}
$marker = Join-Path $markerVerzeichnis 'install-pfad.txt'
[System.IO.File]::WriteAllText($marker, $InstallDir, [System.Text.UTF8Encoding]::new($false))
Write-Host ('      Installationspfad gemerkt in: ' + $marker)

# --- 8 Autostart einrichten ----------------------------------------------

Write-Host ''
Write-Host '[7/8] Richte den Autostart ein ...'
# Voller Pfad statt nacktem Name: Der Task Scheduler loest nackte Namen zur
# Laufzeit ueber den System-PATH auf und meldet 0x80070002 "Das System kann
# die angegebene Datei nicht finden", wenn das dort fehlt - in einer Konsole
# funktioniert derselbe Aufruf (PowerShell#5919). Die Aktion bekommt deshalb
# den Pfad, den Get-Command hier findet.
$befehlPwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($befehlPwsh) { $interpreter = $befehlPwsh.Source }
else { $interpreter = (Get-Command powershell.exe).Source }

$einstellungen = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Daemon: startet bei Anmeldung, versteckt, mit festem Arbeitsverzeichnis.
$argumenteDaemon = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallDir\Start-Guardian.ps1`" -ConfigPath `"$configZiel`""
$aktionDaemon = New-ScheduledTaskAction -Execute $interpreter -Argument $argumenteDaemon -WorkingDirectory $InstallDir
$ausloeser = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName $taskNameDaemon -Action $aktionDaemon -Trigger $ausloeser `
    -Settings $einstellungen -Principal $principal -Description 'WLAN Guardian Ueberwachung' -Force | Out-Null
Write-Host ("      Daemon: $taskNameDaemon (bei Anmeldung, Rechte Limited)")

# Tray: eigener Task ohne Ausloeser. Er wird hier einmal gestartet, und weil
# der Task Limited ist, laeuft das Symbol ohne Erhoehung - auch wenn dieser
# Installer selbst erhoeht laeuft.
if ($KeinTray) {
    Write-Host '      Tray uebersprungen (-KeinTray)'
}
else {
    $argumenteTray = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallDir\src\Guardian.Tray\Guardian.Tray.ps1`" -ConfigPath `"$configZiel`" -UiStarten"
    $aktionTray = New-ScheduledTaskAction -Execute $interpreter -Argument $argumenteTray -WorkingDirectory $InstallDir
    Register-ScheduledTask -TaskName $taskNameTray -Action $aktionTray `
        -Settings $einstellungen -Principal $principal -Description 'WLAN Guardian Infobereich' -Force | Out-Null
    Write-Host ("      Tray  : $taskNameTray (wird jetzt gestartet, kein Ausloeser)")
}

# --- 9 Starten und pruefen ------------------------------------------------

Write-Host ''
Write-Host '[8/8] Starte den Daemon und pruefe den Zustand ...'
Start-ScheduledTask -TaskName $taskNameDaemon
Start-Sleep -Seconds 70

$health = Join-Path $InstallDir 'tools\Get-GuardianHealth.ps1'
if (Test-Path -LiteralPath $health -PathType Leaf) {
    Push-Location $InstallDir
    try {
        & $health -ConfigPath $configZiel
        # Nicht $LASTEXITCODE: Ein mit & aufgerufenes Skript, das selbst exit
        # aufruft, setzt ihn nicht verlaesslich. $? sagt, ob es durchlief.
        if ($?) {
            Write-Host '      Gesundheitspruefung lief durch.'
        }
        else {
            Write-Host '      Gesundheitspruefung meldete einen Fehler.' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '      Bei einem frei gewaehlten Ordner ist die haeufigste Ursache,' -ForegroundColor Yellow
            Write-Host '      dass der Daemon dort ohne Erhoehung nicht schreiben darf.' -ForegroundColor Yellow
            Write-Host '      Pruefen mit:' -ForegroundColor Yellow
            Write-Host ("        & '$health' -ConfigPath '$configZiel'")
        }
    }
    finally { Pop-Location }
}
else {
    Write-Host '      Gesundheitspruefung nicht gefunden, uebersprungen.'
}

if (-not $KeinTray) {
    Start-ScheduledTask -TaskName $taskNameTray
    Write-Host '      Tray-Symbol gestartet, die Oberflaeche oeffnet sich.'
}

Write-Host ''
Write-Host '=== Fertig ==='
Write-Host ('  Installation : ' + $InstallDir)
Write-Host ('  Config       : ' + $configZiel)
Write-Host ('  Ereignisdaten: ' + $artifacts)
Write-Host ('  Sicherung    : ' + $sicherungsZip)
Write-Host ('  Autostart    : ' + $taskNameDaemon + $(if ($KeinTray) { '' } else { ', ' + $taskNameTray }))
Write-Host ''
Write-Host 'Zustand jederzeit pruefen mit:'
Write-Host ("  & '$health' -ConfigPath '$configZiel'")

Write-Erfolgsmeldung
if (-not [string]::IsNullOrWhiteSpace($ProtokollPfad)) { Stop-Transcript | Out-Null }
exit 0
