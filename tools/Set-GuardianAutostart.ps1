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
# -WindowStyle Hidden. Der Task laeuft ohne gespeichertes Kennwort und damit
# in der interaktiven Sitzung; pwsh.exe ist ein Konsolenprogramm und legt ein
# sichtbares Fenster an. Am 04.10.2026 endete der Guardian mit 0xC000013A
# ("The application terminated as a result of a CTRL+C"), nachdem dieses
# Fenster geschlossen worden war. Mit verstecktem Fenster gibt es nichts mehr,
# das versehentlich geschlossen werden kann.
#
# Zwei Grenzen bleiben bestehen und sind Absicht, nicht Versehen:
#   - Ein Dienst ist das nicht. Der Guardian stirbt weiterhin mit der Sitzung.
#   - Die Ausgabe von Write-Host ist nirgends mehr sichtbar. Was zaehlt, steht
#     in artifacts/guardian-events.jsonl, und das wird unveraendert geschrieben.
# Beim Start kann die Konsole kurz aufblitzen, bevor die Einstellung greift.
$argumente = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$starter`" -ConfigPath `"$ConfigPath`""

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
    # 0x413xx sind Statuscodes des Taskplaners, keine Fehlschlaege:
    #   0x41300  bereit, wartet auf den naechsten Lauf
    #   0x41301  laeuft gerade
    #   0x41303  ist noch nie gelaufen
    # Fuer einen Dauerlaeufer ist 0x41301 der Sollzustand. Die alte Pruefung auf
    # "-ne 0" hat am 04.10.2026 einen gesunden, laufenden Guardian als
    # "Der letzte Lauf war nicht erfolgreich" gemeldet und ging mit exit 1
    # heraus - genau verkehrt. Dezimal 267009 ist dasselbe wie 0x41301.
    #
    # Kleine Werte wie 1 oder 2 sind dagegen Exit-Codes des gestarteten
    # Programms, und 0x8007xxxx sind Windows-Fehlercodes. Beide bleiben
    # Fehlschlaege.
    # [int64] und nicht [int]. LastTaskResult traegt auch NTSTATUS-Werte wie
    # 0xC000013A (3221225786), und die liegen ueber Int32.MaxValue. Der Cast
    # auf [int] hat am 04.10.2026 genau daran das Skript abgebrochen:
    #   Der Wert "3221225786" kann nicht in den Typ "System.Int32"
    #   konvertiert werden.
    # Damit war der Bericht unbrauchbar, bevor er die Codes unten ueberhaupt
    # auswerten konnte.
    $ergebnis = [int64]$info.LastTaskResult
    $hex = '0x{0:X8}' -f $ergebnis

    # Vergleich mit -eq und nicht ueber eine Hashtabelle. ContainsKey prueft
    # mit Object.Equals, und Int32.Equals(Int64) ist false. Genau das ist am
    # 04.10.2026 passiert: Der Cast auf [int64] hatte den Ueberlauf behoben,
    # aber 267008/267009/267011 sind Int32-Literale, und der Lookup fand den
    # laufenden Task nicht mehr - 267009 wurde als Fehlschlag gemeldet, also
    # derselbe Fehler noch einmal, nur anders herum. Die Schluessel ueber
    # Int32.MaxValue (3221225786, 2147750687, 2147943645) sind von selbst Int64
    # und funktionierten, was den Fehler verdeckt hat. -eq konvertiert
    # numerisch und hat die Falle nicht.
    $statustext = $null
    if ($ergebnis -eq 267008) { $statustext = 'bereit, wartet auf den naechsten Lauf' }
    elseif ($ergebnis -eq 267009) { $statustext = 'laeuft gerade' }
    elseif ($ergebnis -eq 267011) { $statustext = 'ist noch nie gelaufen' }

    $fehlertext = $null
    if ($ergebnis -eq 3221225786) { $fehlertext = 'von aussen beendet - STRG+C, geschlossene Konsole oder beendeter Task' }
    elseif ($ergebnis -eq 2147750687) { $fehlertext = 'eine Instanz dieses Tasks laeuft bereits' }
    elseif ($ergebnis -eq 2147943645) { $fehlertext = 'Dienst nicht verfuegbar - laeuft der Task nur bei angemeldetem Nutzer?' }
    elseif ($ergebnis -eq 267014) { $fehlertext = 'der Task wurde beendet' }

    if ($null -ne $statustext) {
        Write-Host ''
        Write-Host "Letztes Ergebnis ist ein Status und kein Fehler: $statustext."
        Write-Host 'Zustand pruefen mit:'
        Write-Host '  ./tools/Get-GuardianHealth.ps1'
        exit 0
    }
    if ($ergebnis -ne 0 -and $null -ne $info.LastRunTime) {
        Write-Host ''
        if ($null -ne $fehlertext) {
            Write-Host "Der letzte Lauf schlug fehl ($hex): $fehlertext." -ForegroundColor Yellow
        }
        else {
            Write-Host "Der letzte Lauf war nicht erfolgreich, Ergebnis $ergebnis ($hex)." -ForegroundColor Yellow
        }
        Write-Host 'Pruefung mit:'
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
Write-Host "  Fenster     : versteckt, damit es nicht versehentlich geschlossen wird"
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
