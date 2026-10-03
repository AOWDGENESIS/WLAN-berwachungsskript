# Testanleitung WLAN Guardian

Dieses Archiv ist in sich geschlossen. Nach dem Entpacken ist es ein
vollstaendiges, testfaehiges Projekt - es fehlt keine Datei, die von einem der
Skripte erwartet wird.

## Inhalt

```
WLAN-Guardian-1.1.0/
  Test-All.ps1              Ein-Klick-Testlauf, fasst alle Gates zusammen
  Start-Guardian.ps1        Einstiegspunkt Kommandozeile
  WLAN-Guardian.cmd         Doppelklick-Start
  config/                   Beispielkonfiguration und Release-Manifest
  src/                      Kern und zehn Module
  tests/                    Release-Gate und Hash-Chain-Verifikation
  tools/                    Release-Bau, Verifikation, Manifest-Erzeugung
  installer/                Inno-Setup-Definition
  docs/                     Struktur, Sicherheit, Testregel, Architektur
  .github/workflows/        CI-Workflow, greift erst an der Repository-Wurzel
  KIT-HASHES.json           SHA-256 aller Dateien dieses Archivs
```

## Voraussetzungen

- Windows 10 oder 11
- PowerShell 5.1 oder neuer. PowerShell 7 wird bevorzugt und automatisch
  verwendet, wenn `pwsh.exe` im PATH steht.

Fuer den Paketbau zusaetzlich:

- .NET SDK
- Inno Setup 6 (`ISCC.exe`), nur fuer die Installer-EXE

## Schnellster Weg: alles auf einmal

Aus dem entpackten Ordner:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./Test-All.ps1
```

Der Lauf fuehrt fuenf Pruefungen aus und bricht nicht beim ersten Fehler ab:

| Nr | Pruefung | Was passiert |
|---|---|---|
| 1 | Release-Gate | Pflichtdateien vorhanden, Konfiguration gueltig |
| 2 | Hash-Chain Selbsttest | Kette aufbauen, pruefen, bewusst brechen, Bruch muss auffallen |
| 3 | KIT-HASHES | Manifest gegen den Ist-Baum, meldet jede Abweichung |
| 4 | Kodierung | kein UTF8-BOM, reines ASCII in allen `*.ps1` und `*.psm1` |
| 5 | End-to-End | echter Lauf mit `-Once`, danach wird die erzeugte Kette verifiziert |

Am Ende steht eine Tabelle und `ERGEBNIS: PASS` oder `ERGEBNIS: FAIL`.
Der Exit-Code ist die Anzahl der fehlgeschlagenen Pruefungen, also `0` bei
einem sauberen Lauf.

Schritt 5 braucht Windows mit `Get-NetAdapter`. Fehlt das Cmdlet, wird er als
`SKIP` gewertet und zaehlt nicht als Fehler. Auf Linux oder in CI ohne
Windows-Netzwerkstack gilt:

```powershell
./Test-All.ps1 -SkipEndToEnd
```

## Einzelpruefungen

```powershell
./tests/Release-Gate.ps1
./tests/Verify-Chain.ps1 -SelfTest
./tools/New-KitHashes.ps1 -Check
```

## Manueller Lauf

```powershell
# Einmalige Auswertung
./Start-Guardian.ps1 -Once

# Dauerlauf mit 30 Sekunden Intervall
./Start-Guardian.ps1
```

Ausgabe landet in `artifacts/`:

- `guardian-events.jsonl` - ein JSON-Objekt pro Zeile
- `guardian-chain.json`   - letzter Hash und sein Vorgaenger

Eine echte Auswertung verifizieren:

```powershell
./tests/Verify-Chain.ps1 -LogPath ./artifacts/guardian-events.jsonl
```

Das Skript rechnet die Kette Zeile fuer Zeile nach und vergleicht das Ergebnis
mit der State-Datei. Eine veraenderte Zeile faellt auf, weil sich ab dort jeder
Folgehash aendert.

## Geraete-Discovery

```powershell
./src/Guardian-Devices.ps1
```

Liest die Windows-Neighbor-Tabelle und schreibt `artifacts/guardian-devices.json`.
Es wird nicht aktiv gescannt, `activeScan` bleibt `false`.

## Autostart einrichten (H5)

Zuerst nur nachsehen, das veraendert nichts:

```powershell
./tools/Set-GuardianAutostart.ps1
```

Anlegen:

```powershell
./tools/Set-GuardianAutostart.ps1 -Install
Start-ScheduledTask -TaskName 'WLAN Guardian'
./tools/Get-GuardianHealth.ps1
```

Der Task startet `Start-Guardian.ps1` bei der Anmeldung des aktuellen Nutzers,
mit `-RunLevel Limited` - keine Administratorrechte, kein gespeichertes
Kennwort, kein SYSTEM-Konto. Er benutzt `pwsh`, wenn es installiert ist, sonst
Windows PowerShell, genau wie `WLAN-Guardian.cmd`.

Wieder entfernen:

```powershell
./tools/Set-GuardianAutostart.ps1 -Uninstall
```

Ein zweiter `-Install` bricht ab, solange der Task existiert. Das ist Absicht:
Ein stillschweigendes Ersetzen wuerde eine geaenderte Config unbemerkt
uebernehmen.

## Gesundheit pruefen (H3)

```powershell
./tools/Get-GuardianHealth.ps1
```

Acht Pruefungen, je eine Zeile, am Ende `PASS n   WARN n   FAIL n`. Exit-Code
0 bei durchgehend PASS, 1 bei einem WARN, 2 bei einem FAIL:

```powershell
./tools/Get-GuardianHealth.ps1
$LASTEXITCODE
```

Nach einem einzelnen Lauf mit `-Once` ist `Aktualitaet` erwartbar WARN und
`Prozess` ebenfalls - der Guardian laeuft dann nicht mehr. Das ist kein Fehler.
Als Maschinenwert:

```powershell
./tools/Get-GuardianHealth.ps1 -Quiet | ConvertTo-Json -Depth 4
```

Die Kette wird dabei unabhaengig von `tests/Verify-Chain.ps1` nachgerechnet,
beide lesen dieselben Dateien. Melden beide FAIL, ist das Log veraendert worden
oder zwei Schreibpfade haben es geteilt.

## Geraeteverlauf pruefen (D9)

Standardmaessig aus. `deviceTrackingEnabled` schreibt MAC- und IP-Adressen aus
der Nachbartabelle ins Log, das soll niemand ungefragt bekommen. Es wird nur
passiv gelesen, `activeScan` bleibt `false` - kein ARP-Ping.

Zum Testen einschalten und den Abstand auf jeden Lauf setzen:

```powershell
$cfg = Get-Content .\config\guardian.example.json -Raw | ConvertFrom-Json
$cfg.deviceTrackingEnabled = $true
$cfg.deviceScanEveryNPolls = 1
$cfg | ConvertTo-Json | Set-Content .\config\guardian.local.json
./Start-Guardian.ps1 -Once -ConfigPath .\config\guardian.local.json
```

Der erste Lauf schreibt nur einen Basisstand nach
`artifacts/guardian-devices.snapshot.json` und meldet bewusst nichts - sonst
flutete der Start das Log mit einem `DEVICE_ADDED` je vorhandenem Geraet. Ab
dem zweiten Lauf erscheinen `DEVICE_ADDED` und `DEVICE_REMOVED` in derselben
Hash-Kette. Ein Rollenwechsel loest kein Ereignis aus, verglichen wird ueber
`ip` und `mac`. Schlug der Abgleich fehl, steht `DEVICE_SCAN_FAILED` mit Grund
in der Kette - die Ueberwachung laeuft weiter.

Danach `config/guardian.local.json` wieder loeschen, `.gitignore` deckt
`config/*.local.json` bereits ab.

## Log-Rotation pruefen

`artifacts/guardian-events.jsonl` wird ab `maxLogBytes` (Default 5 MB) gedreht.
Die Segmente heissen `guardian-events.jsonl.1` bis `.5`, jedes mit eigener
State-Datei. Einzelpruefung eines Segments:

```powershell
./tests/Verify-Chain.ps1 -LogPath .\artifacts\guardian-events.jsonl.1
```

Zum Ausloesen ohne 5 MB warten, `maxLogBytes` in der Config kurz auf einen
kleinen Wert setzen, etwa 2048, und mehrere Laeufe mit `-Once` anhaengen:

```powershell
1..10 | ForEach-Object { ./Start-Guardian.ps1 -Once | Out-Null }
Get-ChildItem artifacts\guardian-events.jsonl*
```

Zwei gleichzeitige Laeufe sind gesperrt. Der zweite bricht mit
`Guardian laeuft bereits` ab, statt dieselbe Eventdatei zu teilen.

## Paket bauen

```powershell
./tools/Build-Release.ps1 -SkipInstaller
```

Erzeugt `build/WLAN-Guardian-1.0.0/` und `build/WLAN-Guardian-1.0.0.zip` und
verifiziert beides anschliessend mit `tools/Verify-Release.ps1`. Ohne
`-SkipInstaller` wird zusaetzlich `ISCC.exe` fuer die Setup-EXE aufgerufen.

## Integritaet des Archivs pruefen

`KIT-HASHES.json` enthaelt SHA-256 und Groesse jeder Datei. Abgleich:

```powershell
./tools/New-KitHashes.ps1 -Check
```

Neu erzeugen nach einer Aenderung - niemals von Hand editieren:

```powershell
./tools/New-KitHashes.ps1
```

## CI

`.github/workflows/wlan-guardian.yml` liegt in diesem Archiv bereits an der
Stelle, an der GitHub sie ausfuehrt: unter `.github/workflows/` an der
obersten Ebene. Wird der Ordnerinhalt in ein leeres Repository gelegt und
gepusht, laeuft der Workflow automatisch - `gate` auf `ubuntu-latest`,
`package` mit End-to-End auf `windows-latest`.

In einem Unterordner eines anderen Repositories wird die Datei von GitHub
stillschweigend ignoriert.

## Was dieses Testkit bewusst nicht enthaelt

- Keine FRITZ!Box-Zugangsdaten. `tr069Enabled` steht auf `false`.
- Keine Paketaufzeichnung. `captureEnabled` steht auf `false` und verlangt
  ausdrueckliches Opt-in.
- Keine echten IP-, MAC- oder SSID-Daten als Testfixtures.
- Keine Cloud-, Abo- oder Telemetrieanteile.
