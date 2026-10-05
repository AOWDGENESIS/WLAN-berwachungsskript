<#
.SYNOPSIS
    WLAN Guardian im Infobereich (Tray).

.DESCRIPTION
    Legt ein Symbol in den Infobereich, das den Zustand farbig anzeigt:
    gruen fuer ONLINE, rot fuer OFFLINE, orange fuer unbekannt. Aus dem
    Kontextmenue heraus laesst sich die Oberflaeche oeffnen und der Daemon
    starten oder stoppen.

    Diese Datei ersetzt den frueheren Inhalt von src\Guardian.Tray\: Dort stand
    eine modulare Ueberwachungsschleife, die als "NOCH NICHT VERDRAHTET"
    gekennzeichnet war, von niemandem aufgerufen wurde und bis Commit 4829fc4
    wegen eines zu flachen $root nie ueber die Import-Module-Zeilen hinauskam.
    Der laufende Pfad ist und bleibt src\Guardian.ps1.

.EXAMPLE
    ./src/Guardian.Tray/Guardian.Tray.ps1 -ConfigPath C:\Pfad\config\guardian.json -UiStarten
#>
param(
    [string]$ConfigPath = '',
    [string]$TaskName = 'WLAN Guardian',
    [switch]$UiStarten
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Datei -> Guardian.Tray -> src -> Projektwurzel
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root 'config\guardian.example.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $root $ConfigPath
}

# Nur ein Tray-Symbol pro Rechner. Ohne diese Sperre wuerde jeder erneute
# Aufruf ein zusaetzliches Symbol ablegen, und die liessen sich nur muehsam
# wieder einsammeln.
$script:trayMutex = $null
foreach ($praefix in @('Global\', 'Local\')) {
    try {
        $script:trayMutex = [System.Threading.Mutex]::new($false, ($praefix + 'WLAN-Guardian-Tray'))
        if (-not $script:trayMutex.WaitOne(0, $false)) {
            $script:trayMutex.Dispose()
            $script:trayMutex = $null
        }
        if ($null -ne $script:trayMutex) { break }
    }
    catch { continue }
}
if ($null -eq $script:trayMutex) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'WLAN Guardian laeuft bereits im Infobereich.', 'WLAN Guardian',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    exit 0
}

# --- Helfer ---------------------------------------------------------------

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

function Get-LogPfad {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return (Join-Path $root 'artifacts\guardian-events.jsonl')
    }
    try { $konfiguration = (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json) }
    catch { return (Join-Path $root 'artifacts\guardian-events.jsonl') }
    $verzeichnis = Get-Feld -Objekt $konfiguration -Name 'logDirectory' -Standard 'artifacts'
    if ($verzeichnis -eq '-') { $verzeichnis = 'artifacts' }
    if (-not [System.IO.Path]::IsPathRooted($verzeichnis)) {
        $verzeichnis = Join-Path $root $verzeichnis
    }
    return (Join-Path $verzeichnis 'guardian-events.jsonl')
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

function Get-AktuellerZustand {
    $log = Get-LogPfad
    $zustand = 'unbekannt'
    $zeit = ''
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $letzte = @(Get-Content -LiteralPath $log -Tail 1 -ErrorAction SilentlyContinue)
        if ($letzte.Count -gt 0) {
            try {
                $objekt = $letzte[0] | ConvertFrom-Json
                $zustand = Get-Feld -Objekt $objekt -Name 'status' -Standard 'unbekannt'
                $zeit = Get-Feld -Objekt $objekt -Name 'timestamp' -Standard ''
            }
            catch { }
        }
    }
    return [pscustomobject]@{
        LogPfad = $log
        Zustand = $zustand
        Zeit    = $zeit
        Laeuft  = (Test-DaemonLaeuft -LogPfad $log)
    }
}

# Die drei Symbole werden einmal gebaut und dann wiederverwendet. Ein Icon aus
# GetHicon() traegt einen nativen Handle; wuerde er alle paar Sekunden neu
# erzeugt, sammelte der Prozess ueber Tage Tausende Handles an.
function New-StatusIcon {
    param([System.Drawing.Color]$Farbe)
    $bild = New-Object System.Drawing.Bitmap(16, 16)
    $grafik = [System.Drawing.Graphics]::FromImage($bild)
    try {
        $grafik.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $grafik.Clear([System.Drawing.Color]::Transparent)
        $pinsel = New-Object System.Drawing.SolidBrush($Farbe)
        try { $grafik.FillEllipse($pinsel, 1, 1, 13, 13) }
        finally { $pinsel.Dispose() }
        $rand = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 0, 0, 0))
        try { $grafik.DrawEllipse($rand, 1, 1, 13, 13) }
        finally { $rand.Dispose() }
        return [System.Drawing.Icon]::FromHandle($bild.GetHicon())
    }
    finally {
        $grafik.Dispose()
    }
}

$script:icons = @{
    'ONLINE'    = (New-StatusIcon -Farbe ([System.Drawing.Color]::ForestGreen))
    'OFFLINE'   = (New-StatusIcon -Farbe ([System.Drawing.Color]::Firebrick))
    'unbekannt' = (New-StatusIcon -Farbe ([System.Drawing.Color]::DarkOrange))
}

$script:interpreter = (Get-Process -Id $PID).Path
$script:uiPfad = Join-Path $root 'src\Guardian.UI\Guardian.UI.ps1'

function Start-Oberflaeche {
    if (-not (Test-Path -LiteralPath $script:uiPfad -PathType Leaf)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Oberflaeche nicht gefunden: $($script:uiPfad)", 'WLAN Guardian',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    # Als eigener Prozess und nicht per & im Tray: Ein modaler ShowDialog()
    # wuerde die Nachrichtenschleife des Tray-Symbols blockieren.
    Start-Process -FilePath $script:interpreter -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $script:uiPfad, '-ConfigPath', $ConfigPath, '-TaskName', $TaskName
    ) -WindowStyle Hidden
}

function Stop-Daemon {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { }
    # Nur Prozesse mit Start-Guardian.ps1 in der Befehlszeile. Ein pauschales
    # Get-Process pwsh | Stop-Process wuerde auch offene Konsolen toeten.
    $prozesse = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Start-Guardian.ps1*' })
    foreach ($p in $prozesse) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# --- Symbol und Menue -----------------------------------------------------

$script:zustandAlt = ''

$kontext = New-Object System.Windows.Forms.ContextMenuStrip
$eintragOeffnen = $kontext.Items.Add('WLAN Guardian oeffnen')
[void]$kontext.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$eintragStart = $kontext.Items.Add('Daemon starten')
$eintragStopp = $kontext.Items.Add('Daemon stoppen')
[void]$kontext.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$eintragOrdner = $kontext.Items.Add('Log-Ordner oeffnen')
$eintragZustand = $kontext.Items.Add('Zustand anzeigen')
[void]$kontext.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$eintragBeenden = $kontext.Items.Add('Beenden')

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.ContextMenuStrip = $kontext
$tray.Icon = $script:icons['unbekannt']
$tray.Text = 'WLAN Guardian'
$tray.Visible = $true

$eintragOeffnen.Add_Click({ Start-Oberflaeche })
$tray.Add_MouseDoubleClick({ Start-Oberflaeche })

$eintragStart.Add_Click({
    if (Test-DaemonLaeuft -LogPfad (Get-LogPfad)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Der Daemon laeuft bereits. Es gibt nichts zu starten.', 'WLAN Guardian',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    else {
        try { Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop }
        catch {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Starten fehlgeschlagen (Task '$TaskName'): $($_.Exception.Message)", 'WLAN Guardian',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
    Start-Sleep -Seconds 2
    Update-Symbol
})

$eintragStopp.Add_Click({ Stop-Daemon; Update-Symbol })

$eintragOrdner.Add_Click({
    $verzeichnis = Split-Path -Parent (Get-LogPfad)
    if (Test-Path -LiteralPath $verzeichnis) { Start-Process -FilePath 'explorer.exe' -ArgumentList $verzeichnis }
    else {
        [void][System.Windows.Forms.MessageBox]::Show("Ordner existiert nicht: $verzeichnis", 'WLAN Guardian',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

$eintragZustand.Add_Click({
    $z = Get-AktuellerZustand
    $groesse = 0
    if (Test-Path -LiteralPath $z.LogPfad -PathType Leaf) { $groesse = (Get-Item -LiteralPath $z.LogPfad).Length }
    $meldung = "Zustand       : $($z.Zustand)" + [Environment]::NewLine +
        "Daemon        : $(if ($z.Laeuft) { 'laeuft' } else { 'laeuft nicht' })" + [Environment]::NewLine +
        "Letztes Ereignis: $(if ([string]::IsNullOrWhiteSpace($z.Zeit)) { '-' } else { $z.Zeit })" + [Environment]::NewLine +
        "Loggroesse    : $('{0:N0}' -f $groesse) Bytes" + [Environment]::NewLine +
        "Logdatei      : $($z.LogPfad)"
    [void][System.Windows.Forms.MessageBox]::Show($meldung, 'WLAN Guardian - Zustand',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

$kontextBeenden = New-Object System.Windows.Forms.ApplicationContext
$eintragBeenden.Add_Click({
    $tray.Visible = $false
    $tray.Dispose()
    $kontextBeenden.ExitThread()
})

function Update-Symbol {
    $z = Get-AktuellerZustand
    $schluessel = $z.Zustand
    if (-not $script:icons.ContainsKey($schluessel)) { $schluessel = 'unbekannt' }
    $tray.Icon = $script:icons[$schluessel]

    $daemon = if ($z.Laeuft) { 'Daemon laeuft' } else { 'Daemon laeuft NICHT' }
    $tray.Text = "WLAN Guardian - $($z.Zustand) - $daemon"
    if ($tray.Text.Length -gt 63) { $tray.Text = $tray.Text.Substring(0, 63) }

    # Eine Ballonmeldung nur bei echter Aenderung, nicht alle fuenf Sekunden.
    if ($z.Zustand -ne $script:zustandAlt -and -not [string]::IsNullOrWhiteSpace($script:zustandAlt)) {
        $tray.ShowBalloonTip(4000, 'WLAN Guardian',
            "Zustand gewechselt: $($script:zustandAlt) -> $($z.Zustand)",
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
    $script:zustandAlt = $z.Zustand
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.Add_Tick({ Update-Symbol })

Update-Symbol
$timer.Start()

if ($UiStarten) { Start-Oberflaeche }

# Die Nachrichtenschleife muss laufen, sonst verschwindet das Symbol sofort.
[System.Windows.Forms.Application]::Run($kontextBeenden)

$timer.Stop()
$tray.Visible = $false
$tray.Dispose()
if ($null -ne $script:trayMutex) {
    $script:trayMutex.ReleaseMutex()
    $script:trayMutex.Dispose()
}
