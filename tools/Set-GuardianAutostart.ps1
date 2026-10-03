<#
.SYNOPSIS
    Automatischer Start von WLAN Guardian nach der Anmeldung (H5).

.DESCRIPTION
    Legt einen geplanten Task an, der Start-Guardian.ps1 bei der Anmeldung des
    aktuellen Nutzers startet, oder entfernt ihn wieder.

    Sicherheit:
      - Ohne Schalter passiert nichts. Das Skript berichtet dann nur, ob der
        Task existiert, ob er aktiviert ist und wie der letzte Lauf ausging.
      - -Install und -Uninstall schliessen sich aus.
      - Der Task laeuft mit -RunLevel Limited, also ohne Administratorrechte
        und ohne Erhoehung.
      - Es wird kein Kennwort gespeichert und kein SYSTEM-Konto verwendet.
      - Vor jeder Aenderung wird ausgegeben, was genau passiert.

    Warum ein geplanter Task und kein Windows-Dienst: Ein Dienst braeuchte
    Administratorrechte und ein eigenes Konto, und die Ueberwachung liest die
    WLAN-Schnittstelle der angemeldeten Sitzung. H2 bleibt deshalb offen.

.PARAMETER Install
    Task anlegen. Bricht ab, wenn er schon existiert.

.PARAMETER Uninstall
    Task entfernen. Bricht nicht ab, wenn er nicht existiert.

.PARAMETER TaskName
    Name des Tasks. Default: 'WLAN Guardian'.

.PARAMETER ConfigPath
    Konfiguration, die der Task verwenden soll. Default: die Beispielconfig.
    Wird absolut gespeichert, sonst findet der Task sie bei anderem
    Arbeitsverzeichnis nicht.

.EXAMPLE
    ./tools/Set-GuardianAutostart.ps1

.EXAMPLE
    ./tools/Set-GuardianAutostart.ps1 -Install

.EXAMPLE
    ./tools/Set-GuardianAutostart.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [string]$TaskName = 'WLAN Guardian',
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Zwei Ebenen: diese Datei liegt in tools\, also Datei -> tools -> Projektwurzel.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$starter = Join-Path $root 'Start-Guardian.ps1'

if ($Install -and $Uninstall) {
    throw '-Install und -Uninstall schliessen sich aus.'
}

if (-not (Test-Path -LiteralPath $starter -PathType Leaf)) {
    throw "Start-Guardian.ps1 nicht gefunden: $starter"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $root 'config\guardian.example.json'
}
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    # Absolut speichern. Der Task startet mit einem anderen Arbeitsverzeichnis,
    # ein relativer Pfad wuerde dort nicht aufloesen.
    $ConfigPath = Join-Path $root $ConfigPath
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Konfiguration nicht gefunden: $ConfigPath"
}

# Interpreter waehlen wie WLAN-Guardian.cmd: pwsh, wenn vorhanden, sonst 5.1.
$interpreter = 'powershell.exe'
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { $interpreter = 'pwsh.exe' }
$argumente = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$starter`" -ConfigPath `"$ConfigPath`""

# Geplante Tasks brauchen das ScheduledTasks-Modul. Auf Systemen ohne es gibt
# es noch schtasks.exe, aber dann ist der Rueckgabewert schwerer zu lesen.
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
    throw 'Register-ScheduledTask nicht verfuegbar. Auf diesem System kann der Autostart nicht eingerichtet werden.'
}

# In @() geklammert. Get-ScheduledTask liefert je nach PowerShell-Version
# entweder $null oder ein leeres Array, wenn der Task nicht existiert. Ein
# Vergleich auf $null allein haette einen der beiden Faelle durchgelassen.
$vorhanden = @(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)

# --- nur berichten --------------------------------------------------------
if (-not $Install -and -not $Uninstall) {
    if ($vorhanden.Count -eq 0) {
        Write-Host "Autostart: nicht eingerichtet (Task '$TaskName' existiert nicht)"
        Write-Host ''
        Write-Host 'Anlegen mit:'
        Write-Host "  ./tools/Set-GuardianAutostart.ps1 -Install"
        exit 0
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "Task            : $TaskName"
    Write-Host "Status          : $($vorhanden[0].State)"
    Write-Host "Letzter Lauf    : $($info.LastRunTime)"
    Write-Host "Letztes Ergebnis: $($info.LastTaskResult)"
    Write-Host "Naechster Lauf  : $($info.NextRunTime)"
    Write-Host ''
    Write-Host "Startet         : $interpreter"
    Write-Host "Argumente       : $argumente"
    if ([int]$info.LastTaskResult -ne 0 -and $null -ne $info.LastRunTime) {
        Write-Host ''
        Write-Host 'Der letzte Lauf war nicht erfolgreich. Pruefung mit:' -ForegroundColor Yellow
        Write-Host '  ./tools/Get-GuardianHealth.ps1'
        exit 1
    }
    exit 0
}

# --- entfernen ------------------------------------------------------------
if ($Uninstall) {
    if ($vorhanden.Count -eq 0) {
        Write-Host "Task '$TaskName' existiert nicht, es gibt nichts zu entfernen."
        exit 0
    }
    Write-Host "Entferne Task '$TaskName'"
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host 'Entfernt. Der Guardian laeuft nicht mehr automatisch.'
    exit 0
}

# --- anlegen --------------------------------------------------------------
if ($vorhanden.Count -gt 0) {
    throw "Task '$TaskName' existiert bereits. Erst -Uninstall, dann -Install."
}

Write-Host 'Lege den Autostart an:'
Write-Host "  Name        : $TaskName"
Write-Host "  Ausloeser   : bei Anmeldung des aktuellen Nutzers"
Write-Host "  Rechte      : Limited, keine Erhoehung, kein gespeichertes Kennwort"
Write-Host "  Interpreter : $interpreter"
Write-Host "  Skript      : $starter"
Write-Host "  Config      : $ConfigPath"
Write-Host ''

$aktion = New-ScheduledTaskAction -Execute $interpreter -Argument $argumente -WorkingDirectory $root
$ausloeser = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$optionen = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

# -RunLevel Limited ist bewusst gesetzt: Die Ueberwachung braucht keine
# Administratorrechte, und ein Task mit Erhoehung waere ein unnoetig grosses
# Ziel, falls das Skript je ersetzt wuerde.
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $aktion -Trigger $ausloeser `
    -Settings $optionen -Principal $principal -Description 'WLAN Guardian Ueberwachung' | Out-Null

$kontrolle = @(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
if ($kontrolle.Count -eq 0) {
    throw 'Task wurde nicht angelegt, Register-ScheduledTask lieferte keinen Fehler.'
}

Write-Host "Angelegt. Status: $($kontrolle[0].State)"
Write-Host ''
Write-Host 'Sofort einmal ausprobieren, ohne auf die naechste Anmeldung zu warten:'
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host 'Danach pruefen:'
Write-Host '  ./tools/Get-GuardianHealth.ps1'
exit 0
