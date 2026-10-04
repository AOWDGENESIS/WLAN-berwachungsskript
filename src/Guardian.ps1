param(
    [switch]$Once,
    [string]$ConfigPath = ".\config\guardian.example.json"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

# Bisher lief diese Datei ganz ohne Pruefung. Die Validierung steckt in
# Read-GuardianConfig (src/Guardian.Core), das aber nur der Dienst laedt - und
# der Dienst ist ueber den Tray-Pfad nicht erreichbar. Damit war der einzige
# tatsaechlich ausgefuehrte Pfad der ungepruefte: intervalSeconds = 0 ergab eine
# Schleife ohne Pause, ein fehlendes logDirectory einen Laufzeitfehler tief
# unten in New-Item.
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

foreach ($pflicht in @('intervalSeconds', 'logDirectory')) {
    if ($null -eq $config.PSObject.Properties[$pflicht]) {
        throw "Configuration key missing: $pflicht"
    }
}
$intervalSeconds = ConvertTo-GuardianInt $config.intervalSeconds 0
if ($intervalSeconds -lt 1) { throw "intervalSeconds must be greater than zero: $($config.intervalSeconds)" }
if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) { throw 'logDirectory is required' }

# Schalter ohne Wirkung. captureEnabled und tr069Enabled stehen in der
# Beispielconfig, gelesen werden sie aber nur von Get-CapturePolicy
# (src/Guardian.Capture) beziehungsweise Get-FritzBoxPolicy
# (src/Guardian.FritzBox) - und beide Funktionen haben keine Aufrufer.
# Wer einen der Schalter auf true setzt, bekommt stillschweigend nichts. Wer
# ihn auf false setzt, verlaesst sich auf eine Abschaltung, die es nicht gibt.
# Beides ist schlechter als eine klare Absage, zumal bei Schaltern, die
# Inhaltsueberwachung und Fernzugriff betreffen. Die Beispielconfig setzt beide
# auf false, der normale Pfad ist davon nicht betroffen.
foreach ($schalter in @('captureEnabled', 'tr069Enabled')) {
    if ($null -ne $config.PSObject.Properties[$schalter] -and [bool]$config.$schalter) {
        throw "$schalter ist in dieser Version nicht umgesetzt und kann nicht aktiviert werden. Der Schalter steht in der Konfiguration, aber keine Code-Stelle wertet ihn aus."
    }
}

# Log-Rotation (C6). Ohne sie wuchs guardian-events.jsonl unbegrenzt - bei einem
# Event pro 30 Sekunden sind das rund 30 MB pro Jahr allein an Nutzdaten, auf
# einem Rechner, der nie neu gestartet wird. Beide Werte sind optional, die
# Defaults greifen, wenn die Konfiguration sie nicht nennt.
$maxLogBytes = 5242880
$maxLogFiles = 5
if ($null -ne $config.PSObject.Properties['maxLogBytes'] -and $config.maxLogBytes) {
    $parsed = ConvertTo-GuardianInt $config.maxLogBytes 0
    if ($parsed -gt 0) { $maxLogBytes = $parsed }
}
if ($null -ne $config.PSObject.Properties['maxLogFiles'] -and $config.maxLogFiles) {
    $parsed = ConvertTo-GuardianInt $config.maxLogFiles 0
    if ($parsed -gt 0) { $maxLogFiles = $parsed }
}

$logDirectory = [string]$config.logDirectory
if (-not [System.IO.Path]::IsPathRooted($logDirectory)) {
    $logDirectory = Join-Path (Get-Location).Path $logDirectory
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$logFile = Join-Path $logDirectory "guardian-events.jsonl"
$deviceScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "src\Guardian-Devices.ps1"
$deviceSnapshot = Join-Path $logDirectory "guardian-devices.snapshot.json"
$deviceJson = Join-Path $logDirectory "guardian-devices.json"

# Geraeteverlauf (D9). src/Guardian-Devices.ps1 las die Nachbartabelle bisher
# nur, wenn jemand das Skript von Hand aufrief - es war toter Code, und damit
# auch der Fix aus Commit 3cc7e93. Jetzt wertet der Kern es aus und meldet
# Aenderungen als Ereignisse in dieselbe Hash-Kette.
#
# Standard ist AUS. Die Nachbartabelle enthaelt MAC- und IP-Adressen von
# Geraeten Dritter, das gehoert nicht ungefragt in ein Log. Ausserdem wird nur
# passiv gelesen: activeScan bleibt false, es gibt keinen ARP-Ping.
$deviceTrackingEnabled = $false
if ($null -ne $config.PSObject.Properties['deviceTrackingEnabled']) {
    $deviceTrackingEnabled = [bool]$config.deviceTrackingEnabled
}
$deviceScanEveryNPolls = 10
if ($null -ne $config.PSObject.Properties['deviceScanEveryNPolls'] -and $config.deviceScanEveryNPolls) {
    $parsed = ConvertTo-GuardianInt $config.deviceScanEveryNPolls 0
    if ($parsed -gt 0) { $deviceScanEveryNPolls = $parsed }
}
$stateFile = Join-Path $logDirectory "guardian-chain.json"

function Get-WlanState {
    $ssid = $null
    $adapter = $null
    $ipv4 = $null
    $gateway = $null
    $dnsOk = $false
    $internetOk = $false

    $wlanText = netsh wlan show interfaces 2>$null
    if ($wlanText) {
        # -First 1: Select-String liefert bei mehreren Treffern ein Array, und
        # .Line waere dann ein String-Array statt einer Zeile.
        $ssidLine = @($wlanText | Select-String "^\s*SSID\s*:") | Select-Object -First 1
        if ($ssidLine) {
            $ssid = ($ssidLine.Line -split ":",2)[1].Trim()
        }
    }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Up" })

    # WLAN hat Vorrang. Ohne diese Bevorzugung griff Select-Object -First 1 auf
    # den erstbesten aktiven Adapter - an einem Rechner mit Kabel und Funk also
    # auf Ethernet. Das Event haette dann die SSID aus netsh und die IPv4 samt
    # Gateway aus dem Kabel gemischt, also zwei verschiedene Netze in einer
    # Zeile. Fuer einen WLAN-Waechter ist das der falsche Messpunkt.
    $wlanAdapter = @($adapters | Where-Object {
        $_.PhysicalMediaType -like "*Wireless*" -or
        $_.PhysicalMediaType -like "*802.11*" -or
        $_.Name -eq "WLAN" -or $_.Name -eq "Wi-Fi"
    })
    if ($wlanAdapter.Count -gt 0) {
        $adapter = [string]$wlanAdapter[0].Name
    }
    elseif ($adapters.Count -gt 0) {
        $adapter = [string]$adapters[0].Name
    }

    if ($adapter) {
        $ip = Get-NetIPAddress -InterfaceAlias $adapter -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1

        if ($ip) {
            $ipv4 = $ip.IPAddress
        }

        $route = Get-NetRoute -InterfaceAlias $adapter -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($route) {
            $gateway = $route.NextHop
        }
    }

    if ($null -ne $config.PSObject.Properties['dnsName'] -and $config.dnsName) {
        try {
            Resolve-DnsName -Name $config.dnsName -Type A -ErrorAction Stop | Out-Null
            $dnsOk = $true
        }
        catch {
            $dnsOk = $false
        }
    }

    if ($null -ne $config.PSObject.Properties['testHost'] -and $config.testHost) {
        try {
            $internetOk = Test-Connection -ComputerName $config.testHost -Count 1 -Quiet -ErrorAction Stop
        }
        catch {
            $internetOk = $false
        }
    }

    $status = "OFFLINE"
    if ($internetOk -and $ipv4) {
        $status = "ONLINE"
    }
    if ($ipv4 -and -not $internetOk) {
        $status = "LOCAL_ONLY"
    }

    [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        status = $status
        ssid = $ssid
        adapter = $adapter
        ipv4 = $ipv4
        gateway = $gateway
        dnsOk = $dnsOk
        internetOk = $internetOk
    }
}

function Get-Sha256 {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-GuardianDeviceChanges {
    <#
        Liefert die Geraeteaenderungen seit dem letzten Abgleich.

        Beim allerersten Lauf wird nur ein Basisstand geschrieben und keine
        Aenderung gemeldet - sonst flutete der Start das Log mit einem
        DEVICE_ADDED je vorhandenem Geraet. Verglichen wird ueber ip+mac, weil
        die Rollenvergabe aus der Nachbartabelle zwischen Laeufen schwanken kann
        und eine Rolle keine Identitaet ist.
    #>
    param([object]$Current)

    $jetzt = @()
    foreach ($d in @($Current.devices)) {
        if ($null -eq $d) { continue }
        $jetzt += [pscustomobject]@{
            ip = [string]$d.ip
            mac = [string]$d.mac
            role = [string]$d.role
        }
    }

    $frueher = @()
    $hatBasis = $false
    if (Test-Path -LiteralPath $deviceSnapshot -PathType Leaf) {
        try {
            $alt = Get-Content -LiteralPath $deviceSnapshot -Raw | ConvertFrom-Json
            foreach ($d in @($alt.devices)) {
                if ($null -eq $d) { continue }
                $frueher += [pscustomobject]@{
                    ip = [string]$d.ip
                    mac = [string]$d.mac
                    role = [string]$d.role
                }
            }
            $hatBasis = $true
        }
        catch { $frueher = @(); $hatBasis = $false }
    }

    [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
        DeviceCount = $jetzt.Count
        devices = $jetzt
    } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $deviceSnapshot -Encoding utf8

    if (-not $hatBasis) {
        return [pscustomobject]@{ Basis = $true; Hinzugekommen = @(); Verschwunden = @() }
    }

    $altSchluessel = @($frueher | ForEach-Object { "$($_.ip)|$($_.mac)" })
    $neuSchluessel = @($jetzt | ForEach-Object { "$($_.ip)|$($_.mac)" })

    return [pscustomobject]@{
        Basis = $false
        Hinzugekommen = @($jetzt | Where-Object { $altSchluessel -notcontains "$($_.ip)|$($_.mac)" })
        Verschwunden = @($frueher | Where-Object { $neuSchluessel -notcontains "$($_.ip)|$($_.mac)" })
    }
}

function Invoke-GuardianLogRotation {
    <#
        Dreht das Eventlog, sobald es $maxLogBytes ueberschreitet.

        Die Hash-Kette darf dabei nicht reissen. Deshalb bekommt jedes Segment
        seine eigene State-Datei im Evidence-Format, also
        guardian-events.<n>.jsonl.state.json mit CurrentHash und PreviousHash.
        tests/Verify-Chain.ps1 erkennt dieses Format automatisch und kann jedes
        Segment einzeln pruefen. Das aktuelle Segment startet danach mit einem
        leeren previous, guardian-chain.json wird entfernt.
    #>
    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) { return }
    if ((Get-Item -LiteralPath $logFile).Length -le $maxLogBytes) { return }

    $kopf = ''
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        try { $kopf = [string]((Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).hash) }
        catch { $kopf = '' }
    }

    $aeltestes = "$logFile.$maxLogFiles"
    if (Test-Path -LiteralPath $aeltestes) { Remove-Item -LiteralPath $aeltestes -Force }
    if (Test-Path -LiteralPath "$aeltestes.state.json") { Remove-Item -LiteralPath "$aeltestes.state.json" -Force }

    for ($i = $maxLogFiles - 1; $i -ge 1; $i--) {
        $von = "$logFile.$i"
        if (Test-Path -LiteralPath $von) { Move-Item -LiteralPath $von -Destination "$logFile.$($i + 1)" -Force }
        $vonState = "$von.state.json"
        if (Test-Path -LiteralPath $vonState) { Move-Item -LiteralPath $vonState -Destination "$logFile.$($i + 1).state.json" -Force }
    }

    Move-Item -LiteralPath $logFile -Destination "$logFile.1" -Force
    [pscustomobject]@{ PreviousHash = ''; CurrentHash = $kopf } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath "$logFile.1.state.json" -Encoding utf8

    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Write-Host "Log rotiert: $logFile.1"
}

function Write-GuardianEvent {
    param([object]$Event)

    Invoke-GuardianLogRotation

    $json = $Event | ConvertTo-Json -Compress -Depth 8
    $previous = ""

    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($state.hash) {
                $previous = [string]$state.hash
            }
        }
        catch {
            $previous = ""
        }
    }

    $chainInput = $previous + $json
    $hash = Get-Sha256 $chainInput

    Add-Content -LiteralPath $logFile -Value $json -Encoding utf8
    @{ hash = $hash; previous = $previous } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $stateFile -Encoding utf8

    $Event
}

# Ein-Instanz-Sperre. Zwei gleichzeitige Laeufe haengen beide an dieselbe
# guardian-events.jsonl, fuehren aber je eine eigene State-Datei - die Kette
# waere fuer beide unpruefbar. Genau das passiert, wenn Konsole und Dienst
# parallel laufen.
# Global\ sperrt ueber alle Sitzungen hinweg, braucht dafuer aber
# SeCreateGlobalPrivilege. Ein normaler Nutzer hat das nicht, deshalb wird bei
# UnauthorizedAccessException auf den sitzungslokalen Namen ausgewichen - dann
# schuetzt die Sperre immer noch vor zwei Konsolenlaeufen desselben Nutzers.
#
# Der Name haengt am Log und nicht am Programm. Ausschliessen sollen sich zwei
# Laeufe, die dieselbe guardian-events.jsonl schreiben - genau das sagt der
# Kommentar oben. Ein fester Name sperrte dagegen global: Die Testlaeufe in
# Test-All.ps1 schreiben in eigene Temp-Ordner, teilen also nichts, und wurden
# am 04.10.2026 trotzdem abgewiesen, weil der Daemon lief. Test-All.ps1 konnte
# damit nie gruen werden, solange der Guardian laeuft, und jeder Deploy musste
# ihn erst anhalten.
#
# Ein Hash des Pfads haelt den Namen kurz und frei von Zeichen, die in einem
# Mutex-Namen nichts zu suchen haben. Klein geschrieben, weil Windows-Pfade
# nicht zwischen Gross- und Kleinschreibung unterscheiden.
$mutexKennung = (Get-Sha256 $logFile.ToLowerInvariant()).Substring(0, 16)
$mutexName = 'WLAN-Guardian-Einziger-Lauf-' + $mutexKennung
$mutex = $null
foreach ($praefix in @('Global\', 'Local\')) {
    try {
        # [Typ]::new() statt New-Object Typ(...). Die Kurzform hatte am
        # 02.10.2026 den ersten echten Lauf unter PowerShell 7.6.6 abgebrochen:
        #   Argument: "3" sollte ein "System.Management.Automation.PSReference"
        #   sein. Verwenden Sie "[ref]".
        # System.Threading.Mutex hat einen Konstruktor
        # (bool, string, out bool createdNew); "Argument 3" ist dessen
        # out-Parameter. ::new() bindet die Argumente direkt an den passenden
        # Konstruktor und ist seit PowerShell 5.0 verfuegbar, also in beiden
        # Versionen gleich.
        $mutex = [System.Threading.Mutex]::new($false, ($praefix + $mutexName))
        break
    }
    catch [System.UnauthorizedAccessException] { continue }
}
if ($null -eq $mutex) { throw 'Mutex konnte nicht angelegt werden, weder global noch sitzungslokal.' }

$hatSperre = $false
try {
    $hatSperre = $mutex.WaitOne(0, $false)
}
catch [System.Threading.AbandonedMutexException] {
    $hatSperre = $true
}
if (-not $hatSperre) {
    throw 'Guardian laeuft bereits. Zweiter Start abgebrochen, sonst wuerden zwei Schreibpfade dieselbe Eventdatei teilen.'
}

try {
$pollZaehler = 0
$letzterStatus = $null
$fehlerInFolge = 0
do {
    try {
    $event = Get-WlanState
    Write-GuardianEvent $event | ConvertTo-Json -Compress

    # Zustandswechsel (G4). Bisher schrieb der Kern nur den wiederkehrenden
    # WLAN-Zustand; ein Wechsel von ONLINE auf OFFLINE stand zwar als neue Zeile
    # im Log, fiel aber nirgends auf. Wer das Log nicht offen hat, erfaehrt von
    # einem Ausfall nichts. Deshalb gibt es jetzt ein eigenes Ereignis je
    # Wechsel, in derselben Hash-Kette, plus eine Zeile auf der Konsole.
    $statusJetzt = [string]$event.status
    if ($letzterStatus -ne $statusJetzt) {
        $vorher = $letzterStatus
        if ([string]::IsNullOrEmpty($vorher)) { $vorher = 'START' }
        Write-GuardianEvent ([ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            eventType = "STATE_CHANGED"
            from = $vorher
            to = $statusJetzt
            ssid = $event.ssid
            adapter = $event.adapter
            ipv4 = $event.ipv4
            dnsOk = $event.dnsOk
            internetOk = $event.internetOk
        }) | Out-Null
        Write-Host "Zustandswechsel: $vorher -> $statusJetzt"
        $letzterStatus = $statusJetzt
    }

    $pollZaehler++
    if ($deviceTrackingEnabled -and ($pollZaehler % $deviceScanEveryNPolls -eq 1 -or $Once)) {
        if (Test-Path -LiteralPath $deviceScript -PathType Leaf) {
            # Die JSON-Datei wird gelesen, nicht die Standardausgabe geparst.
            # Das Skript gibt das Ergebnis zusaetzlich auf stdout aus, aber
            # diese Ausgabe kommt als Zeilenarray zurueck und wuerde schon an
            # einer einzigen Write-Host-Zeile im Skript zerbrechen. Die Datei
            # schreibt das Skript selbst mit UTF-8 ohne BOM, sie ist die
            # verlaesslichere Quelle.
            try {
                & $deviceScript -OutputPath $deviceJson | Out-Null
                if (-not (Test-Path -LiteralPath $deviceJson -PathType Leaf)) {
                    throw "Geraetedatei wurde nicht geschrieben: $deviceJson"
                }
                $bestand = Get-Content -LiteralPath $deviceJson -Raw | ConvertFrom-Json
                $aenderung = Get-GuardianDeviceChanges -Current $bestand
                if (-not $aenderung.Basis) {
                    foreach ($d in $aenderung.Hinzugekommen) {
                        Write-GuardianEvent ([ordered]@{
                            timestamp = (Get-Date).ToUniversalTime().ToString("o")
                            eventType = "DEVICE_ADDED"
                            ip = $d.ip
                            mac = $d.mac
                            role = $d.role
                        }) | Out-Null
                    }
                    foreach ($d in $aenderung.Verschwunden) {
                        Write-GuardianEvent ([ordered]@{
                            timestamp = (Get-Date).ToUniversalTime().ToString("o")
                            eventType = "DEVICE_REMOVED"
                            ip = $d.ip
                            mac = $d.mac
                            role = $d.role
                        }) | Out-Null
                    }
                }
            }
            catch {
                # Ein fehlgeschlagener Geraeteabgleich darf die Ueberwachung
                # nicht beenden. Der Fehler wird selbst als Ereignis
                # festgehalten, damit er in der Kette sichtbar bleibt.
                Write-GuardianEvent ([ordered]@{
                    timestamp = (Get-Date).ToUniversalTime().ToString("o")
                    eventType = "DEVICE_SCAN_FAILED"
                    reason = [string]$_.Exception.Message
                }) | Out-Null
            }
        }
    }

    $fehlerInFolge = 0
    }
    catch {
        # Im Einzellauf soll der Fehler sichtbar bleiben - Test-All.ps1 wertet
        # genau das aus, und ein verschluckter Fehler waere dort ein falsches
        # PASS. Abgefangen wird nur im Dauerlauf.
        if ($Once) { throw }
        $fehlerInFolge = $fehlerInFolge + 1
        $meldung = [string]$_.Exception.Message
        # Der Fehler gehoert in die Kette, sonst ist er nicht nachweisbar. Geht
        # das nicht - etwa weil das Logverzeichnis verschwunden ist - dann auf
        # die Konsole. Am 04.10.2026 endete der Guardian genau so: Ordner unter
        # dem laufenden Prozess neu geklont, Add-Content wirft, try/finally ohne
        # catch, Exit-Code 1 und nirgends eine Spur.
        $protokolliert = $false
        try {
            Write-GuardianEvent ([ordered]@{
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
                eventType = 'GUARDIAN_ERROR'
                reason = $meldung
            }) | Out-Null
            $protokolliert = $true
        }
        catch { }
        if (-not $protokolliert) {
            Write-Host "Guardian-Fehler, nicht protokollierbar: $meldung"
        }
        # Fuenf Fehlversuche in Folge heisst, dass sich von selbst nichts mehr
        # erholt. Dann mit Diagnose beenden statt endlos weiterzulaufen. Die
        # Pause danach gibt dem System Zeit, etwa ein wieder eingehaengtes
        # Verzeichnis sichtbar zu machen.
        if ($fehlerInFolge -ge 5) {
            throw "Fuenf aufeinanderfolgende Fehler, der Guardian beendet sich. Letzter Fehler: $meldung"
        }
    }
    if ($Once) {
        break
    }
    Start-Sleep -Seconds $intervalSeconds
} while ($true)
}
finally {
    if ($hatSperre) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
