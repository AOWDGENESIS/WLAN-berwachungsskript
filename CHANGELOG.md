# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
Versionierung nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.1.0] - 2026-10-02

### Geaendert
- **Schalter ohne Wirkung werden jetzt abgelehnt.** `captureEnabled` und
  `tr069Enabled` stehen in der Beispielconfig, ausgewertet werden sie aber nur
  von `Get-CapturePolicy` und `Get-FritzBoxPolicy`, und beide Funktionen haben
  keine Aufrufer. Wer einen der Schalter auf `true` setzte, bekam
  stillschweigend nichts; wer ihn auf `false` setzte, verliess sich auf eine
  Abschaltung, die es nicht gibt. Bei Schaltern fuer Inhaltsueberwachung und
  Fernzugriff ist beides schlechter als eine klare Absage, deshalb bricht der
  Kern jetzt mit einer Meldung ab. Die Beispielconfig setzt beide auf `false`,
  der normale Pfad ist nicht betroffen.
- Inhalt mit `main` (`0b6221d`) zusammengefuehrt statt daruebergeschrieben.
  Die juengeren Dateien des Ziels bleiben erhalten: `README.md`,
  `src/Guardian-Devices.ps1` mit dem Fix aus `3cc7e93`, sechs Doku-Dateien,
  `tools/Build-Complete-Release.ps1`, `tools/Release-Builder.ps1`.
- Drei Werkzeuge auf ASCII umgestellt. Windows PowerShell 5.1 liest `.ps1`
  ohne BOM als ANSI, Umlaute und Haken waeren im Konsolenfenster zerfallen.

### Hinzugefuegt
- **Siebter Testschritt `Rotation`.** Die Log-Rotation war bisher nur statisch
  geprueft und nie real gelaufen. Der Schritt loest sie ueber echte `-Once`-
  Laeufe aus statt sie nachzubauen: `maxLogBytes` wird auf 200 gesetzt, ein
  Lauf schreibt rund 380 Bytes, also rotiert das Log schon beim zweiten Lauf.
  Geprueft werden sechs Laeufe, das Vorhandensein der Segmente `.1` und `.2`,
  die Obergrenze (`maxLogFiles = 2`, ein Segment `.3` darf nie entstehen, und
  zwar nach jedem Lauf betrachtet, nicht erst am Ende), die State-Datei des
  Segments mit leerem `PreviousHash` und gueltigem `CurrentHash`, sowie die
  Kette jedes Segments einzeln ueber `tests/Verify-Chain.ps1`.
- **Autostart erstmals real verifiziert.** Am 03.10.2026 hat
  `tools/Set-GuardianAutostart.ps1 -Install` auf dem Zielrechner eine geplante
  Aufgabe angelegt (`Angelegt. Status: Ready`, Exit-Code 0) und `-Uninstall`
  hat sie wieder entfernt (Exit-Code 0). Damit ist H5 nicht mehr nur statisch
  geprueft. Der Task laeuft mit `-RunLevel Limited`, ohne Erhoehung und ohne
  gespeichertes Kennwort.
- **Gesundheitspruefung erstmals gruenn.** `Get-GuardianHealth.ps1` meldete
  `PASS 7 WARN 1 FAIL 0`. `Aktualitaet` rechnet jetzt korrekt
  (`letztes Ereignis vor 1 s, Grenze 150 s`), `Kette` rechnet unabhaengig nach
  (`2 Zeilen nachgerechnet, Kopf stimmt`). Das `WARN` bei `Prozess` ist
  erwartet: Im `-Once`-Modus laeuft kein Dauerprozess.

### Behoben
- **Die Aktualitaets-Pruefung rechnete mit der Kultur des Rechners.**
  `tools/Get-GuardianHealth.ps1` parste den Zeitstempel mit
  `[datetime]::Parse($stempel)`, also ohne `CultureInfo`. Im ersten gruenen
  Lauf am 03.10.2026 auf einem deutschen Rechner meldete die Pruefung
  `letztes Ereignis vor 17.884.801 s` fuer ein Ereignis, das Sekunden alt war.
  17.884.801 s sind 207 Tage und 1 Sekunde, und 207 Tage vor dem 03.10.2026
  ist der 10.03.2026 - Monat und Tag vertauscht. Der Aufruf ist jetzt mit
  `InvariantCulture` sowie `AdjustToUniversal` und `AssumeUniversal`, damit
  UTC herauskommt und nicht still in Lokalzeit umgerechnet wird. Geschrieben
  wird ueberall mit `ToUniversalTime().ToString("o")`.
  Neue Pruefung 19 `zeit/kulturabhaengig`, rueckgetestet gegen einen
  Kontrollbaum.
- **Falsche Zeilennummern in den Pruefmeldungen.** Sechs Regeln schnitten
  `<# ... #>`-Blockkommentare ersatzlos heraus und zaehlten danach die Zeilen
  neu. Jede Meldung nannte damit eine zu kleine Zeile - bei einem Fehler, der
  nur ueber die Zeile zu finden ist, ist das die halbe Diagnose. Die
  Blockkommentare werden jetzt durch gleich viele Leerzeilen ersetzt; der
  Kontrolltest meldet Zeile 187 fuer einen Fehler in Zeile 187.
- **`New-Object System.Threading.Mutex(...)` brach den Kern unter PowerShell 7
  ab - die wirkliche Ursache.** `src/Guardian.ps1:358` legte die
  Ein-Instanz-Sperre mit der Kurzform `New-Object System.Threading.Mutex($false,
  $name)` an. Unter 7.6.6 brach das ab mit `Argument: "3" sollte ein
  "System.Management.Automation.PSReference" sein. Verwenden Sie "[ref]".`
  `Mutex` hat einen Konstruktor `(bool, string, out bool createdNew)`;
  "Argument 3" ist dessen out-Parameter. Der Mutex steht vor der Hauptschleife,
  damit lief der Kern ueberhaupt nicht: kein Event, kein Log, die Kette nie
  geschrieben. Ersetzt durch `[System.Threading.Mutex]::new($false, $name)`,
  das die Argumente direkt an den passenden Konstruktor bindet und seit
  PowerShell 5.0 verfuegbar ist. Dieselbe Kurzform ist in
  `tools/New-KitHashes.ps1` und `src/Guardian-Devices.ps1` ersetzt; die sieben
  Stellen in `src/Guardian.UI/Guardian.UI.ps1` sind bewusst nicht angefasst -
  reine `System.Drawing`-Typen ohne out-Parameter, und die GUI ist nicht testbar.
- **`Test-All.ps1` zeigte Fehler ohne Ort.** `Invoke-Step` erfasste nur
  `$_.Exception.Message`. Genau das hat die Fehldiagnose moeglich gemacht: Die
  Meldung `Argument: 3 sollte ein PSReference sein` stand ohne Datei und Zeile
  in der Tabelle, und die Suche ging per Grep auf `TryParse`. Jetzt werden
  `InvocationInfo.ScriptName` und `ScriptLineNumber` mit ausgegeben.
- **`tools/Verify-Release.ps1` verlangte Windows PowerShell 5.1 und benutzte das
  Ergebnis nicht.** `$ps = Get-Command powershell.exe`, bei Fehlen
  `throw "Windows PowerShell is required"` - und danach wurde `$ps` nirgends
  mehr verwendet. Die Pruefung sagte also nichts ueber das Release aus und
  lehnte trotzdem ein System ab, auf dem nur `pwsh` laeuft, obwohl der Kern
  unter beiden Versionen laeuft. Jetzt wird `pwsh.exe` bevorzugt,
  `powershell.exe` als Rueckfall, und der gefundene Interpreter wird gemeldet.
  `src/Guardian.Tray/Guardian.Tray.ps1` und `tools/Set-GuardianAutostart.ps1`
  machten das bereits richtig; dies war die letzte der drei Stellen.
- **`tools/Build-Complete-Release.ps1` baute ein leeres Paket.** `$root` zeigte
  mit nur einem `Split-Path` auf `tools\` statt auf die Projektwurzel. Damit
  schlug jede `Test-Path`-Pruefung fehl, PHASE 1 meldete alle sechs
  Verzeichnisse als fehlend und PHASE 2 kopierte gar nichts - das Skript lief
  trotzdem bis zum Ende durch. Zwei Eintraege in `$rootFiles`
  (`INSTALL-FLOW.md`, `release-manifest.example.json`) waren nach dem Umzug in
  `docs\` beziehungsweise `config\` zusaetzlich unerreichbar; beide Ordner
  werden ohnehin vollstaendig kopiert, die Eintraege sind entfallen. Fehlende
  Quellen werden jetzt rot gemeldet und brechen den Bau ab.
- **`tools/Release-Builder.ps1` hatte `$root = "D:\WLAN Guardian"` fest
  eingetragen.** Das Werkzeug lief damit nur auf einem Rechner mit genau diesem
  Laufwerksbuchstaben und Ordner - `README.md` empfahl den Aufruf aber
  ausdruecklich. Die Wurzel wird jetzt aus `$MyInvocation.MyCommand.Path`
  gerechnet. Vorgabe fuer `-Version` von 1.0.0 auf 1.1.0 angehoben.
- **Fehldiagnose zurueckgenommen: Der Abbruch kam nicht von `TryParse`.**
  Der erste echte Lauf unter 7.6.6 am 02.10.2026 brach im End-to-End-Gate ab
  mit `Argument: 3 sollte ein System.Management.Automation.PSReference sein.
  Verwenden Sie [ref].` Die Ursache wurde in `[int]::TryParse(..., [ref]$var)`
  vermutet und dort geaendert. Das war falsch und hat am Fehlschlag nichts
  geaendert. Die wirkliche Zeile hat erst der direkte Aufruf von
  `Start-Guardian.ps1 -Once` genannt, siehe naechster Eintrag.
  `ConvertTo-GuardianInt` und `-as [System.Net.IPAddress]` bleiben trotzdem:
  Aufrufe mit `[ref]` sind zwischen 5.1 und 7 nicht verlaesslich, nur waren
  sie hier nicht die Ursache. Pruefung 17 `ref/methodenaufruf` bleibt
  ebenfalls, hat den echten Fehler aber nicht gefunden.

- **Schritt 5 `Werkzeuge` in `Test-All.ps1`.** Ruft
  `tools/Get-GuardianHealth.ps1` und `tools/Set-GuardianAutostart.ps1` im
  Berichtsmodus auf und verlangt einen der Exit-Codes, die die Skripte selbst
  setzen. Beide kamen im Testlauf bisher nicht vor. Der `[ref]`-Fehler vom
  02.10.2026 sass in `Get-GuardianHealth.ps1`, und der Testlauf war zu dem
  Zeitpunkt schon gruen durchgelaufen und hatte PASS 4 gemeldet - gefunden hat
  den Fehler erst der manuelle Aufruf danach. Der Testlauf hat damit sechs
  Schritte, End-to-End ist jetzt Schritt 6.
- Pruefung 18 `pfad/hartkodiert` im statischen Pruefstand. Meldet die Zuweisung
  eines absoluten Pfads an eine Variable, also genau das Muster, das
  `Release-Builder.ps1` unbrauchbar machte. Suchpfade in einem Array bleiben
  erlaubt: Dort wird gesucht und geprueft, nicht blind benutzt. Rueckgetestet
  gegen einen Kontrollbaum mit zurueckgebautem `D:\`-Pfad.
- `tools/Bau-Kit.py` baut beide Auslieferungsarchive. Der Bau lief vorher als
  Wegwerf-Heredoc; dort fehlte am 02.10.2026 ein `import json`, was
  `KIT-HASHES.json` auf 0 Byte leerte und die danach ausgegebenen
  Pruefmeldungen auf die ALTEN Archive beziehen liess. Das Skript schreibt das
  Manifest zuerst, verlangt eine saubere statische Pruefung und bricht sonst ab,
  bevor ein Archiv entsteht. Beleg: Aus dem Stand von `4a3828f` baut es die
  veroeffentlichten Archive bytegleich nach (`8EFC40EE...`, `2F729428...`).
- Log-Rotation (C6). `guardian-events.jsonl` wuchs unbegrenzt - bei einem Event
  pro 30 Sekunden rund 30 MB pro Jahr auf einem Rechner, der nie neu gestartet
  wird. Neue Schluessel `maxLogBytes` (Default 5242880) und `maxLogFiles`
  (Default 5). Jedes Segment bekommt eine eigene State-Datei
  `guardian-events.jsonl.<n>.state.json` im Evidence-Format, das
  `tests/Verify-Chain.ps1` automatisch erkennt - die Kette bleibt also je
  Segment pruefbar und reisst nicht.
- Autostart (H5): `tools/Set-GuardianAutostart.ps1`. Legt einen geplanten Task
  an, der `Start-Guardian.ps1` bei der Anmeldung startet. Ohne Schalter
  passiert nichts, das Skript berichtet dann nur. Der Task laeuft mit
  `-RunLevel Limited`, ohne Erhoehung und ohne gespeichertes Kennwort.
  `-Install` und `-Uninstall` schliessen sich aus. Ein Windows-Dienst (H2) ist
  das bewusst nicht: Er braeuchte Administratorrechte und ein eigenes Konto,
  und die Ueberwachung liest die WLAN-Schnittstelle der angemeldeten Sitzung.
- Gesundheitspruefung (H3): `tools/Get-GuardianHealth.ps1`. Acht Einzelpruefungen
  mit PASS, WARN und FAIL - Config, Logordner beschreibbar, Ereignislog,
  Aktualitaet des letzten Ereignisses, lueckenlose Hash-Kette, Groesse gegen
  `maxLogBytes`, Segmentnummern und State-Dateien der Rotation, und ob die
  Ein-Instanz-Sperre gehalten ist. Exit-Codes 0/1/2, damit ist es direkt in
  einem Scheduled Task verwendbar. `-Quiet` liefert nur das Ergebnisobjekt.
- Alarm bei Zustandswechsel (G4). Bisher schrieb der Kern nur den
  wiederkehrenden WLAN-Zustand; ein Wechsel von `ONLINE` auf `OFFLINE` stand
  zwar als neue Zeile im Log, fiel aber nirgends auf. Jetzt gibt es je Wechsel
  ein `STATE_CHANGED`-Ereignis in derselben Hash-Kette plus eine Zeile auf der
  Konsole.
- Geraeteverlauf (D9). `src/Guardian-Devices.ps1` war toter Code - es wurde nur
  von `tests/Release-Gate.ps1` als "muss existieren" geprueft, nie ausgefuehrt,
  damit war auch der Fix aus `3cc7e93` wirkungslos. Der Kern ruft es jetzt auf
  und meldet `DEVICE_ADDED`, `DEVICE_REMOVED` und `DEVICE_SCAN_FAILED` in
  dieselbe Hash-Kette. Neue Schluessel `deviceTrackingEnabled` (Default `false`,
  weil die Nachbartabelle MAC- und IP-Adressen Dritter enthaelt) und
  `deviceScanEveryNPolls` (Default 10). Der erste Lauf schreibt nur einen
  Basisstand und meldet nichts. Verglichen wird ueber `ip` und `mac`, ein
  Rollenwechsel loest kein Ereignis aus.
- `docs/ARCHITEKTUR-ENTSCHEIDUNG.md` - dokumentiert, dass der Monolith die
  MVP-Implementierung bleibt und der modulare Pfad nie gelaufen ist.
- Ein-Instanz-Sperre per Mutex. Zwei gleichzeitige Laeufe haengten beide an
  dieselbe Eventdatei, fuehrten aber je eine eigene State-Datei - die Kette war
  fuer beide unpruefbar. `Global\` wird versucht, bei fehlendem Recht auf
  `Local\` ausgewichen.
- `ENTFERNEN.txt` - abschliessende Liste der Pfade, die ein Deploy aus dem
  Ziel entfernen darf. Nur Umzuege und echte Dublikaten.

## [Unreleased]

### Geaendert
- Repository-Struktur bereinigt. Die per Web-Upload flach abgelegten Dateien
  (`src_Guardian.Evidence_Guardian.Evidence.psm1`, `tests_Release-Gate.ps1`,
  `config_guardian.example (1).json` und 17 weitere) sind in ihre
  Zielverzeichnisse verschoben oder als Duplikat entfernt.
- `INSTALL-FLOW.md` liegt jetzt unter `docs/`, `release-manifest.example.json`
  unter `config/`, `SECURITY.md` im Root. Damit stimmt der Baum mit
  `KIT-HASHES.json` ueberein.
- `tools/Build-Release.ps1` paketiert zusaetzlich `WLAN-Guardian-UI.cmd`.

### Hinzugefuegt
- `tests/Verify-Chain.ps1` - verifiziert die Hash-Chain und erkennt
  manipulierte Zeilen. `-SelfTest` laeuft ohne Windows-Netzwerk-Cmdlets und
  damit auch in CI.
- `tools/New-KitHashes.ps1` - erzeugt `KIT-HASHES.json` aus dem Ist-Stand,
  `-Check` meldet Drift.
- CI-Job `cross-platform` auf `ubuntu-latest` mit Encoding- und BOM-Pruefung.

### Behoben
- `KIT-HASHES.json` war gegenueber dem Baum veraltet: 31 Eintraege gegen 22
  Dateien, 22 Eintraege ohne Datei, 13 Dateien ohne Eintrag, 4 Hashkonflikte.
  Neu erzeugt.

## [1.0.0] - 2026-09-23

### Hinzugefuegt
- Kernmonitor `src/Guardian.ps1` mit SSID-, Adapter-, IPv4-, Gateway-,
  DNS- und Internet-Pruefung.
- Ereignisprotokoll als JSONL mit SHA-256-Hash-Chain.
- Geraete-Discovery `src/Guardian-Devices.ps1` ueber die Windows-Neighbor-Tabelle.
- Module `Guardian.Core`, `Guardian.Devices`, `Guardian.Network`,
  `Guardian.Capture`, `Guardian.Evidence`, `Guardian.FritzBox`,
  `Guardian.Security`, `Guardian.Service`, `Guardian.Tray`, `Guardian.UI`.
- Windows-Launcher `WLAN-Guardian.cmd`, `WLAN-Guardian-UI.cmd`.
- Inno-Setup-Definition `installer/WLAN-Guardian.iss`, Per-User-Installation
  nach `{localappdata}\Programs`.
- Release-Bau `tools/Build-Release.ps1`, Verifikation `tools/Verify-Release.ps1`,
  Release-Gate `tests/Release-Gate.ps1`.

### Behoben
- `306b306` - Per-User-Installer: `PrivilegesRequired=lowest` und
  Desktop-Verknuepfung auf `{userdesktop}` statt oeffentlichem Desktop,
  behebt `0x80070005` bei Installation ohne Adminrechte.
