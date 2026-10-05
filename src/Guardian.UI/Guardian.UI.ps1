<#
.SYNOPSIS
    Grafische Oberflaeche fuer WLAN Guardian.

.DESCRIPTION
    Zeigt den aktuellen Zustand, den Daemon-Status und die letzten Ereignisse
    aus guardian-events.jsonl. Das Fenster liest nur, es schreibt nichts in das
    Log und haelt keine Ein-Instanz-Sperre. Es kann deshalb laufen, waehrend
    der Daemon laeuft.

    Die fruehere Fassung dieser Datei war ein Platzhalter: Sie las
    $obj.GuardianState, das Ereignis heisst aber "status", und sie rief nie
    ShowDialog() auf. Damit endete das Skript, bevor ein Fenster sichtbar war -
    die GUI erschien nie. Beide Punkte sind hier behoben.

.EXAMPLE
    ./Start-Guardian-UI.ps1
    ./src/Guardian.UI/Guardian.UI.ps1 -ConfigPath C:\Pfad\config\guardian.json
#>
param(
    [string]$ConfigPath = '',
    [string]$TaskName = 'WLAN Guardian'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Diese Datei liegt in src\Guardian.UI\, also drei Ebenen unter der Wurzel:
#   Datei -> Guardian.UI -> src -> Projektwurzel
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root 'config\guardian.example.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $root $ConfigPath
}

# --- Helfer ---------------------------------------------------------------

# Unter Set-StrictMode -Version Latest wirft der Zugriff auf eine nicht
# vorhandene Eigenschaft eines PSCustomObject. ConvertFrom-Json liefert genau
# so ein Objekt, und nicht jedes Ereignis traegt jedes Feld - die aelteren
# Zeilen im Log stammen aus Versionen ohne deviceTracking. Deshalb wird jedes
# Feld ueber PSObject.Properties geholt: Das liefert $null statt zu werfen.
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

# Baugleich zu Get-Sha256 in src\Guardian.ps1 und Get-Sha256Text in
# tools\Get-GuardianHealth.ps1: UTF8, SHA-256, Bindestriche weg, klein.
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

function Get-Konfiguration {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

# Das logDirectory wird hier genauso aufgeloest wie im Kern. Steht ein absoluter
# Pfad in der Config - der Installer schreibt einen - gibt es ueberhaupt keinen
# Spielraum mehr. Ein relativer Pfad wird gegen die Projektwurzel aufgeloest.
function Get-LogPfad {
    param($Konfiguration)
    if ($null -eq $Konfiguration) { return (Join-Path $root 'artifacts\guardian-events.jsonl') }
    $verzeichnis = Get-Feld -Objekt $Konfiguration -Name 'logDirectory' -Standard 'artifacts'
    if ($verzeichnis -eq '-') { $verzeichnis = 'artifacts' }
    if (-not [System.IO.Path]::IsPathRooted($verzeichnis)) {
        $verzeichnis = Join-Path $root $verzeichnis
    }
    return (Join-Path $verzeichnis 'guardian-events.jsonl')
}

# Dieselbe Sperre, die der Kern haelt. Gehalten heisst: ein Daemon laeuft, und
# zwar einer, der in dieses Log schreibt.
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

function Get-LetzteZeilen {
    param([string]$LogPfad, [int]$Anzahl)
    if (-not (Test-Path -LiteralPath $LogPfad -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $LogPfad -Tail $Anzahl -ErrorAction SilentlyContinue)
}

function Get-MenschenZeit {
    param([string]$Wert)
    if ([string]::IsNullOrWhiteSpace($Wert)) { return '-' }
    try {
        $zeit = [datetime]::Parse($Wert, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
        return $zeit.ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')
    }
    catch {
        return $Wert
    }
}

# --- Zustand sammeln ------------------------------------------------------

function Get-Anzeige {
    $log = Get-LogPfad -Konfiguration (Get-Konfiguration)
    $zeilen = Get-LetzteZeilen -LogPfad $log -Anzahl 60
    $ereignisse = @()
    foreach ($zeile in $zeilen) {
        if ([string]::IsNullOrWhiteSpace($zeile)) { continue }
        try { $ereignisse += ($zeile | ConvertFrom-Json) }
        catch { continue }
    }
    $letztes = $null
    if ($ereignisse.Count -gt 0) { $letztes = $ereignisse[$ereignisse.Count - 1] }

    $groesse = 0
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $groesse = (Get-Item -LiteralPath $log).Length
    }

    return [pscustomobject]@{
        LogPfad    = $log
        Ereignisse = $ereignisse
        Letztes    = $letztes
        Bytes      = $groesse
        Laeuft     = (Test-DaemonLaeuft -LogPfad $log)
    }
}

# --- Fenster aufbauen -----------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = 'WLAN Guardian'
$form.ClientSize = New-Object System.Drawing.Size(1000, 700)
$form.MinimumSize = New-Object System.Drawing.Size(860, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$titel = New-Object System.Windows.Forms.Label
$titel.Text = 'WLAN GUARDIAN'
$titel.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$titel.AutoSize = $true
$titel.Location = New-Object System.Drawing.Point(20, 14)
$form.Controls.Add($titel)

$statusAnzeige = New-Object System.Windows.Forms.Label
$statusAnzeige.Text = 'STATUS: unbekannt'
$statusAnzeige.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$statusAnzeige.AutoSize = $true
$statusAnzeige.Location = New-Object System.Drawing.Point(20, 52)
$statusAnzeige.ForeColor = [System.Drawing.Color]::DarkOrange
$form.Controls.Add($statusAnzeige)

# Zwei Gruppen mit fester Beschriftungstabelle statt einzeln hingetippter
# Koordinaten: weniger Zeilen, und die Zeilen stehen garantiert untereinander.
function New-Gruppe {
    param([string]$TitelText, [int]$X, [string[]]$Zeilen)
    $gruppe = New-Object System.Windows.Forms.GroupBox
    $gruppe.Text = $TitelText
    $gruppe.Location = New-Object System.Drawing.Point($X, 104)
    $gruppe.Size = New-Object System.Drawing.Size(462, 158)
    $gruppe.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $werte = @{}
    $y = 24
    foreach ($zeile in $Zeilen) {
        $name = New-Object System.Windows.Forms.Label
        $name.Text = $zeile
        $name.Location = New-Object System.Drawing.Point(12, $y)
        $name.Size = New-Object System.Drawing.Size(150, 20)
        $gruppe.Controls.Add($name)
        $wert = New-Object System.Windows.Forms.Label
        $wert.Text = '-'
        $wert.Location = New-Object System.Drawing.Point(168, $y)
        $wert.Size = New-Object System.Drawing.Size(282, 20)
        $wert.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $gruppe.Controls.Add($wert)
        $werte[$zeile] = $wert
        $y += 22
    }
    return [pscustomobject]@{ Gruppe = $gruppe; Werte = $werte }
}

$verbindung = New-Gruppe -TitelText 'Verbindung' -X 20 -Zeilen @('SSID', 'Adapter', 'IPv4', 'Gateway', 'DNS', 'Internet')
$form.Controls.Add($verbindung.Gruppe)

$daemon = New-Gruppe -TitelText 'Daemon' -X 500 -Zeilen @('Prozess', 'Ereignisse', 'Loggroesse', 'Letztes Ereignis', 'Logdatei', 'Config')
$form.Controls.Add($daemon.Gruppe)

$tabelle = New-Object System.Windows.Forms.DataGridView
$tabelle.Location = New-Object System.Drawing.Point(20, 274)
$tabelle.Size = New-Object System.Drawing.Size(960, 356)
$tabelle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor
    [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$tabelle.AllowUserToAddRows = $false
$tabelle.AllowUserToDeleteRows = $false
$tabelle.AllowUserToResizeRows = $false
$tabelle.ReadOnly = $true
$tabelle.RowHeadersVisible = $false
$tabelle.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$tabelle.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$tabelle.MultiSelect = $false
[void]$tabelle.Columns.Add('zeit', 'Zeit')
[void]$tabelle.Columns.Add('status', 'Status')
[void]$tabelle.Columns.Add('ssid', 'SSID')
[void]$tabelle.Columns.Add('ipv4', 'IPv4')
[void]$tabelle.Columns.Add('internet', 'Internet')
[void]$tabelle.Columns.Add('ereignis', 'Ereignis')
$tabelle.Columns['zeit'].FillWeight = 130
$tabelle.Columns['status'].FillWeight = 90
$tabelle.Columns['ssid'].FillWeight = 120
$tabelle.Columns['ipv4'].FillWeight = 110
$tabelle.Columns['internet'].FillWeight = 80
$tabelle.Columns['ereignis'].FillWeight = 150
$form.Controls.Add($tabelle)

$knopfLeiste = New-Object System.Windows.Forms.Panel
$knopfLeiste.Location = New-Object System.Drawing.Point(20, 642)
$knopfLeiste.Size = New-Object System.Drawing.Size(960, 40)
$knopfLeiste.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($knopfLeiste)

function New-Knopf {
    param([string]$Text, [int]$X, [int]$Breite)
    $knopf = New-Object System.Windows.Forms.Button
    $knopf.Text = $Text
    $knopf.Location = New-Object System.Drawing.Point($X, 6)
    $knopf.Size = New-Object System.Drawing.Size($Breite, 30)
    $knopfLeiste.Controls.Add($knopf)
    return $knopf
}

$knopfAktualisieren = New-Knopf -Text 'Aktualisieren' -X 0 -Breite 120
$knopfOrdner = New-Knopf -Text 'Log-Ordner oeffnen' -X 130 -Breite 150
$knopfStart = New-Knopf -Text 'Daemon starten' -X 290 -Breite 140
$knopfStopp = New-Knopf -Text 'Daemon stoppen' -X 440 -Breite 140
$knopfSchliessen = New-Knopf -Text 'Fenster schliessen' -X 820 -Breite 140
$knopfSchliessen.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

# --- Inhalt fuellen -------------------------------------------------------

$script:signatur = ''

function Update-Anzeige {
    $anzeige = Get-Anzeige
    $letztes = $anzeige.Letztes

    $zustand = Get-Feld -Objekt $letztes -Name 'status' -Standard 'unbekannt'
    $statusAnzeige.Text = 'STATUS: ' + $zustand
    switch ($zustand) {
        'ONLINE' { $statusAnzeige.ForeColor = [System.Drawing.Color]::ForestGreen }
        'OFFLINE' { $statusAnzeige.ForeColor = [System.Drawing.Color]::Firebrick }
        default { $statusAnzeige.ForeColor = [System.Drawing.Color]::DarkOrange }
    }

    $verbindung.Werte['SSID'].Text = Get-Feld -Objekt $letztes -Name 'ssid'
    $verbindung.Werte['Adapter'].Text = Get-Feld -Objekt $letztes -Name 'adapter'
    $verbindung.Werte['IPv4'].Text = Get-Feld -Objekt $letztes -Name 'ipv4'
    $verbindung.Werte['Gateway'].Text = Get-Feld -Objekt $letztes -Name 'gateway'
    $verbindung.Werte['DNS'].Text = Get-Feld -Objekt $letztes -Name 'dnsOk'
    $verbindung.Werte['Internet'].Text = Get-Feld -Objekt $letztes -Name 'internetOk'

    $daemon.Werte['Prozess'].Text = $(if ($anzeige.Laeuft) { 'laeuft, Sperre ist gehalten' } else { 'laeuft nicht' })
    $daemon.Werte['Prozess'].ForeColor = $(if ($anzeige.Laeuft) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Firebrick })
    $daemon.Werte['Ereignisse'].Text = [string]$anzeige.Ereignisse.Count + ' angezeigt (letztes Ende des Logs)'
    $daemon.Werte['Loggroesse'].Text = '{0:N0} Bytes' -f $anzeige.Bytes
    $daemon.Werte['Letztes Ereignis'].Text = Get-MenschenZeit -Wert (Get-Feld -Objekt $letztes -Name 'timestamp' -Standard '')
    $daemon.Werte['Logdatei'].Text = $anzeige.LogPfad
    $daemon.Werte['Config'].Text = $ConfigPath

    # Die Zeilen werden nur neu gebaut, wenn sich wirklich etwas geaendert hat.
    # Ohne diesen Vergleich flackert die Tabelle alle fuenf Sekunden.
    $neu = ($anzeige.Ereignisse | ForEach-Object {
        (Get-Feld -Objekt $_ -Name 'timestamp') + '|' + (Get-Feld -Objekt $_ -Name 'status')
    }) -join ';'
    if ($neu -ne $script:signatur) {
        $script:signatur = $neu
        $tabelle.SuspendLayout()
        $tabelle.Rows.Clear()
        # Neuestes zuerst, damit der oberste Eintrag der aktuelle ist.
        for ($i = $anzeige.Ereignisse.Count - 1; $i -ge 0; $i--) {
            $e = $anzeige.Ereignisse[$i]
            [void]$tabelle.Rows.Add(
                (Get-MenschenZeit -Wert (Get-Feld -Objekt $e -Name 'timestamp' -Standard '')),
                (Get-Feld -Objekt $e -Name 'status'),
                (Get-Feld -Objekt $e -Name 'ssid'),
                (Get-Feld -Objekt $e -Name 'ipv4'),
                (Get-Feld -Objekt $e -Name 'internetOk'),
                (Get-Feld -Objekt $e -Name 'event' -Standard '')
            )
        }
        $tabelle.ResumeLayout()
    }
}

# --- Daemon steuern -------------------------------------------------------

$knopfStart.Add_Click({
    # Laeuft der Daemon bereits, gibt es nichts zu starten. Start-ScheduledTask
    # gegen einen laufenden Task lieferte am 05.10.2026 statt einer sauberen
    # Meldung den irrefuehrenden Fehler "Das System kann die angegebene Datei
    # nicht finden" - deshalb zuerst die Sperre pruefen.
    if (Test-DaemonLaeuft -LogPfad (Get-LogPfad -Konfiguration (Get-Konfiguration))) {
        [void][System.Windows.Forms.MessageBox]::Show('Der Daemon laeuft bereits. Es gibt nichts zu starten.', 'WLAN Guardian',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    else {
        try {
            Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
            [void][System.Windows.Forms.MessageBox]::Show("Task '$TaskName' wurde gestartet.", 'WLAN Guardian',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        catch {
            [void][System.Windows.Forms.MessageBox]::Show("Starten fehlgeschlagen (Task '$TaskName'): $($_.Exception.Message)", 'WLAN Guardian',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    Update-Anzeige
})

$knopfStopp.Add_Click({
    try {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    }
    catch { }
    # Stop-ScheduledTask beendet den Task, nicht immer auch den pwsh-Prozess
    # darunter. Deshalb wird gezielt nur der Prozess beendet, der
    # Start-Guardian.ps1 in der Befehlszeile hat - nie pauschal alle pwsh.
    $prozesse = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Start-Guardian.ps1*' })
    foreach ($p in $prozesse) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
    Update-Anzeige
})

$knopfAktualisieren.Add_Click({ Update-Anzeige })

$knopfOrdner.Add_Click({
    $verzeichnis = Split-Path -Parent (Get-LogPfad -Konfiguration (Get-Konfiguration))
    if (Test-Path -LiteralPath $verzeichnis) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $verzeichnis
    }
    else {
        [void][System.Windows.Forms.MessageBox]::Show("Ordner existiert nicht: $verzeichnis", 'WLAN Guardian',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

$knopfSchliessen.Add_Click({ $form.Close() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Anzeige })

$form.Add_Shown({
    Update-Anzeige
    $timer.Start()
})
$form.Add_FormClosed({ $timer.Stop() })

# Ohne ShowDialog() kehrt das Skript sofort zurueck und das Fenster ist nie zu
# sehen. Genau daran ist die alte Fassung gescheitert.
[void]$form.ShowDialog()
