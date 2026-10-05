# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
Versionierung nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.1.0] - 2026-10-02

### Behoben
- **"Starten fehlgeschlagen: Das System kann die angegebene Datei nicht
  finden" beim Knopf "Daemon starten", waehrend der Daemon laengst lief.**
  Oberflaeche und Tray riefen `Start-ScheduledTask` ohne Vorabpruefung. Beide
  pruefen jetzt zuerst die Ein-Instanz-Sperre (`Test-DaemonLaeuft`) und melden
  "Der Daemon laeuft bereits" statt eines Fehlerdialogs; die Fehlermeldung
  nennt jetzt den Task-Namen. Beobachtet am 05.10.2026 im ersten erfolgreichen
  echten Lauf.
- **Autostart-Tasks trugen nackte Interpreternamen.** `pwsh.exe` statt des
  vollen Pfades: Der Task Scheduler loest nackte Namen zur Laufzeit ueber den
  System-PATH auf und meldet 0x80070002, wenn der Eintrag dort fehlt - in der
  Konsole funktioniert derselbe Aufruf (PowerShell#5919). Installer und
  `Set-GuardianAutostart.ps1` schreiben jetzt `(Get-Command ...).Source` in
  die Task-Aktion.

- **Die Installation sah beim Schritt "Installationsordner" aus wie ein
  Haenger.** Der Ordnerdialog wurde im erhoehten Kindprozess geoeffnet und
  gehoert keinem Fenster. Er konnte hinter der Konsole liegen, und im Fenster
  stand zuletzt nur `[1/8] Bestimme den Installationsordner ...` - genau dort
  blieb der echte Lauf am 05.10.2026 stehen. Die Abfrage laeuft jetzt im nicht
  erhoehten Prozess, also in dem Fenster, das der Nutzer sieht, und damit vor
  der UAC-Abfrage. Vorher sagt der Installer, dass ein Fenster kommt und dass
  ein Klick auf die Taskleiste hilft, wenn es verdeckt ist.
- **Kein Ausweg, wenn der Ordnerdialog nicht bedient werden kann.** Bricht er
  ab oder laeuft er gar nicht erst, fragte der Installer nichts weiter und
  beendete sich. Jetzt folgt eine Eingabezeile: Pfad eintippen oder Enter fuer
  den vorgeschlagenen Ordner unter dem Benutzerprofil. Mitkopierte
  Anfuehrungszeichen werden abgetrennt, und Ziel gleich Quellordner wird
  weiterhin abgelehnt, bevor etwas geloescht wird.

- **Ein Fehlschlag der Installation wurde als Erfolg gemeldet.**
  `tools/Install-Guardian.ps1` startet den erhoehten Lauf mit
  `Start-Process -Verb RunAs -Wait`, und `-Wait` gibt den Exit-Code des Kindes
  nicht zurueck. Danach stand ein bedingungsloses `exit 0`. Damit gingen der
  abgebrochene Ordnerdialog, ein fehlgeschlagener Wiederherstellungspunkt und
  jeder geworfene Fehler als Erfolg durch, und `WLAN-Guardian-Start.bat`
  meldete "durchgelaufen, Exit-Code 0", waehrend gar nichts installiert war.
  Das Kind schreibt jetzt eine Erfolgsmeldung, und zwar nur an seinen beiden
  erfolgreichen Enden; fehlt sie, geht der Elternprozess mit `exit 1` heraus.
- **Dasselbe eine Ebene hoeher.** `tools/Start-Guardian-Menue.ps1` rief den
  Installer mit `&` auf und endete unbedingt mit `exit 0`. Ein mit `&`
  aufgerufenes Skript beendet den Aufrufer nicht, also war auch dort jeder
  Fehlschlag unsichtbar. `$global:LASTEXITCODE` wird jetzt vor dem Aufruf auf 0
  gesetzt und danach ausgewertet - dieselbe Reihenfolge wie in `Test-All.ps1` -
  und das Menue beendet sich mit dem uebernommenen Code.

### Behoben
- **Vier Stellen suchten den Daemon nur unter `pwsh.exe`.** Oberflaeche,
  Tray, Installer und Menue filterten
  `Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'"`, waehrend
  `tools/Install-Guardian.ps1` und `tools/Set-GuardianAutostart.ps1`
  ausdruecklich `powershell.exe` in den Autostart eintragen, wenn `pwsh.exe`
  nicht im PATH ist. Auf einem Rechner ohne PowerShell 7 im PATH haette
  "Daemon stoppen" aus dem Menue still nichts getan, und der Installer haette
  den alten Prozess nicht beendet, bevor er dessen Ordner loescht. Der Filter
  lautet jetzt `Name='pwsh.exe' OR Name='powershell.exe'`; die Bindung an
  `Start-Guardian.ps1` beziehungsweise `Guardian.Tray.ps1` in der
  Befehlszeile bleibt, damit weiterhin keine fremde Konsole beendet wird.

### Hinzugefuegt
- **Installationspaket zum Doppelklick.**
  `WLAN-Guardian-Installation-1.1.0.zip` legt `WLAN-Guardian-Start.bat` und
  `LIESMICH-INSTALLATION.txt` an die Archivwurzel und `Projekt/` direkt
  daneben, ohne Versionsordner. Die Batchdatei sucht `pwsh.exe`, faellt auf
  `powershell.exe` zurueck und startet `tools/Start-Guardian-Menue.ps1`; die
  Logik steht dort, weil sie sich in PowerShell pruefen laesst und in Batch
  nicht. CRLF, weil `cmd.exe` mit LF-only bei mehrzeiligen Klammerbloecken
  durcheinanderkommt - `.gitattributes` setzt dafuer `*.bat text eol=crlf`.
- **Menue und Dauerueberwachung.** `tools/Start-Guardian-Menue.ps1` bietet
  installieren, Zustand pruefen, ueberwachen, Daemon starten und stoppen,
  Oberflaeche oeffnen, letzte Ereignisse anzeigen und deinstallieren - als
  Menue nach einem Doppelklick und als Einzelaufruf, also
  `WLAN-Guardian-Start.bat ueberwachen`. Die Ueberwachung schreibt alle
  30 Sekunden eine Zeile mit Zeit, Status, SSID, IPv4, Internet,
  Daemon-Zustand, Loggroesse und Ereigniszahl, und endet auf Q.
  `KeyAvailable` ist in try/catch, weil es bei umgelenkter Eingabe wirft.
- **Notiz zum Installationspfad.** Der Installer schreibt
  `%LOCALAPPDATA%\WLAN-Guardian\install-pfad.txt`, die Deinstallation
  entfernt sie. Der Zielordner wird frei gewaehlt; ohne die Notiz wuesste
  die Batchdatei nach einem Doppelklick nicht, welche Installation sie
  ueberwachen soll.

### Hinzugefuegt
- **Installationsprogramm mit freiem Pfad.** `tools/Install-Guardian.ps1`
  fordert Administratorrechte an, legt einen Windows-Wiederherstellungspunkt
  an, sichert `artifacts` und `config` der alten Installation als ZIP in die
  Dokumente, beendet den alten Daemon, entfernt den alten Autostart, loescht
  den alten Ordner, fragt den Zielordner ab, kopiert, richtet den Autostart
  ein, startet und prueft. Ohne `-InstallDir` oeffnet sich ein Ordnerdialog.
  `-Deinstallieren` macht nur die ersten fuenf Schritte.
  `Checkpoint-Computer` braucht Erhoehung, deshalb die UAC-Abfrage; Daemon und
  Tray laufen weiter mit `-RunLevel Limited`. Schlaegt der
  Wiederherstellungspunkt fehl, bricht der Installer ab, bevor er etwas
  veraendert - ausser mit `-KeinWiederherstellungspunkt`.
- **Echte Oberflaeche.** `src/Guardian.UI/Guardian.UI.ps1` zeigt Status, SSID,
  Adapter, IPv4, Gateway, DNS und Internet, dazu ob der Daemon laeuft, wie
  gross das Log ist und wann das letzte Ereignis kam, sowie die letzten 60
  Ereignisse als Tabelle. Aus dem Fenster heraus laesst sich der Daemon
  starten und stoppen und der Log-Ordner oeffnen. Die Oberflaeche liest nur
  und haelt keine Sperre, sie laeuft also neben dem Daemon.
- **Tray-Symbol.** `src/Guardian.Tray/Guardian.Tray.ps1` legt ein Symbol in
  den Infobereich, gruen bei ONLINE, rot bei OFFLINE, orange bei unbekannt,
  mit Doppelklick auf die Oberflaeche und Start/Stopp im Kontextmenue. Eine
  eigene Sperre verhindert mehrere Symbole, und die drei Icons werden einmal
  gebaut statt alle fuenf Sekunden, weil `Icon.FromHandle` einen nativen
  Handle traegt.

### Behoben
- **Die Oberflaeche war ein Platzhalter und erschien nie.**
  `src/Guardian.UI/Guardian.UI.ps1` rief kein `ShowDialog()` auf: Nach
  `$timer.Start()` endete das Skript, das Fenster war nie sichtbar. Ausserdem
  las es `$obj.GuardianState`, das Ereignis traegt das Feld aber als `status` -
  selbst mit sichtbarem Fenster waere der Status leer geblieben. Und es
  hardkodierte `artifacts` statt das `logDirectory` aus der Config zu lesen.
  Alle drei Punkte sind behoben. Felder werden ueber `PSObject.Properties`
  gelesen, denn unter `Set-StrictMode -Version Latest` wirft der Zugriff auf
  eine nicht vorhandene Eigenschaft eines `PSCustomObject`, und nicht jede
  aeltere Logzeile traegt jedes Feld.
- **`src/Guardian.Tray/` enthielt eine Schleife, die nie lief.** Der Inhalt
  war als "NOCH NICHT VERDRAHTET" gekennzeichnet, wurde von niemandem
  aufgerufen und kam bis Commit 4829fc4 wegen eines zu flachen `$root` nie
  ueber die `Import-Module`-Zeilen hinaus. Der Ordner heisst jetzt, was er
  enthaelt. Der laufende Pfad bleibt `src/Guardian.ps1`.

### Behoben
- **Der Autostart-Bericht nannte die falsche Quelle.** Ohne `-Install` und
  `-Uninstall` schreibt `tools/Set-GuardianAutostart.ps1` nichts, es
  berichtet nur - `Register-ScheduledTask` ist allein ueber `-Install`
  erreichbar. Der Bericht zeigte unter `Startet` und `Argumente` aber die
  Pfade, die diese Kopie des Skripts anlegen wuerde, also im Deploy die des
  Wegwerf-Klons, direkt neben Status und letztem Ergebnis des echten Tasks.
  Im Protokoll vom 04.10.2026 las sich das, als sei der Autostart auf
  `C:\Users\aowdg\WLAN-Deploy7\arbeit\ziel` verbogen. War er nicht.
  Jetzt werden `Execute`, `Arguments` und `WorkingDirectory` aus dem
  registrierten Task gelesen, und das Arbeitsverzeichnis steht mit dabei,
  weil es entscheidet, wohin der Daemon schreibt.

### Geaendert
- **Die Ein-Instanz-Sperre haengt am Log statt am Programm.** Der Name ist
  jetzt `WLAN-Guardian-Einziger-Lauf-` plus die ersten 16 Zeichen der SHA-256
  des Logpfads, klein geschrieben, weil Windows-Pfade die Gross- und
  Kleinschreibung nicht unterscheiden. `tools/Get-GuardianHealth.ps1` bildet
  denselben Namen aus demselben Pfad. Damit gilt genau das, was der Kommentar
  im Kern verspricht: Zwei Laeufe auf dieselbe `guardian-events.jsonl`
  schliessen sich aus, zwei Laeufe auf verschiedene Logs nicht.
  Noetig wurde das am 04.10.2026: Die Testlaeufe in `Test-All.ps1` schreiben in
  eigene Temp-Ordner, teilen also nichts, wurden aber vom laufenden Daemon
  blockiert. `Test-All.ps1` meldete `PASS 5 FAIL 2`, der Deploy brach ab, und
  jeder Deploy musste den Daemon erst anhalten.

### Behoben
- **Die Hauptschleife faengt Fehler jetzt ab.** Sie stand in einem
  `try { } finally { }` ohne `catch`; ein werfendes `Write-GuardianEvent`
  beendete den Dauerlauf mit Exit-Code 1 und ohne jede Diagnose. Beobachtet am
  04.10.2026, als der Installationsordner unter dem laufenden Task geloescht
  und neu geklont wurde. Jetzt wird der Fehler als `GUARDIAN_ERROR` in
  dieselbe Kette geschrieben. Geht auch das nicht, geht die Meldung auf die
  Konsole. Nach fuenf Fehlversuchen in Folge beendet sich der Guardian mit
  Diagnose statt endlos weiterzulaufen. Im Einzellauf (`-Once`) wird weiter
  durchgeworfen, damit `Test-All.ps1` einen echten Fehler nicht als PASS
  verbucht.

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

### Geaendert
- **Der Autostart startet pwsh jetzt mit verstecktem Fenster.**
  `tools/Set-GuardianAutostart.ps1` uebergibt zusaetzlich `-WindowStyle
  Hidden`. Der Task laeuft ohne gespeichertes Kennwort und damit in der
  interaktiven Sitzung; `pwsh.exe` ist ein Konsolenprogramm und legte ein
  sichtbares Fenster an, dessen Schliessen den Guardian am 04.10.2026 mit
  `0xC000013A` beendete. Was versehentlich geschlossen werden kann, wird jetzt
  gar nicht erst angezeigt.
  Zwei Grenzen bleiben und sind Absicht: Ein Dienst ist das nicht, der
  Guardian stirbt weiterhin mit der Sitzung. Und die `Write-Host`-Ausgabe ist
  nirgends mehr sichtbar - was zaehlt, steht in
  `artifacts/guardian-events.jsonl`. Beim Start kann die Konsole kurz
  aufblitzen, bevor die Einstellung greift.
  Ein bereits angelegter Task behaelt die alten Argumente; er muss mit
  `-Uninstall` und `-Install` neu angelegt werden.

### Behoben
- **Der Statuscode-Lookup fand den laufenden Task nicht.** Die Korrektur auf
  `[int64]` hatte den Ueberlauf behoben, aber die Schluessel `267008`,
  `267009` und `267011` waren Int32-Literale, und `ContainsKey` vergleicht mit
  `Object.Equals` - `Int32.Equals(Int64)` ist `false`. Am 04.10.2026 meldete
  das Werkzeug fuer einen gesunden, laufenden Task wieder
  `Der letzte Lauf war nicht erfolgreich, Ergebnis 267009 (0x00041301)`.
  Derselbe Fehler also zum zweiten Mal, nur anders verursacht.
  Verdeckt wurde er dadurch, dass die drei Schluessel ueber `Int32.MaxValue`
  (`3221225786`, `2147750687`, `2147943645`) von selbst Int64 sind und
  funktionierten - `0xC000013A` wurde korrekt benannt, `267009` nicht.
  Beide Tabellen sind durch `-eq`-Vergleiche ersetzt, die numerisch
  konvertieren und die Typfalle nicht haben.

### Behoben
- **Der Autostart-Bericht brach an grossen Ergebniswerten ab.**
  `tools/Set-GuardianAutostart.ps1` castete `LastTaskResult` auf `[int]`.
  Der Taskplaner liefert dort aber auch NTSTATUS-Werte, und am 04.10.2026 lag
  `3221225786` (`0xC000013A`) vor - ueber `Int32.MaxValue`. Das Skript brach
  mit `Der Wert "3221225786" kann nicht in den Typ "System.Int32" konvertiert
  werden` ab, bevor es die Statuscodes auswerten konnte. Der Bericht war damit
  genau in dem Fall unbrauchbar, in dem etwas zu melden gewesen waere. Jetzt
  `[int64]`, und der Wert wird zusaetzlich hexadezimal gezeigt.
- **Bekannte Fehlerschluessel werden benannt.** `0xC000013A` (von aussen
  beendet), `0x8004131F` (Instanz laeuft bereits), `0x800704DD` (Dienst nicht
  verfuegbar) und `0x41306` (Task beendet) bekommen einen Text statt einer
  nackten Zahl. Die Dezimalwerte sind gegen die Hexwerte nachgerechnet.

### Bekannt
- **Der Dauerlauf uebersteht den Taskplaner nicht.** Am 04.10.2026 startete
  der Task um 06:20:51 UTC, schrieb zwei Ereignisse um 06:20:53 UTC und endete
  mit `0xC000013A` - "The application terminated as a result of a CTRL+C",
  also von aussen beendet. Danach `Aktualitaet WARN letztes Ereignis vor
  990 s` und `Prozess WARN`. Der Task laeuft ohne gespeichertes Kennwort und
  damit nur in der interaktiven Sitzung; `pwsh.exe` ist ein Konsolenprogramm,
  und dessen Konsole zu schliessen beendet den Guardian. Ein Dienst im
  eigentlichen Sinn ist das nicht. Moegliche Wege: `-WindowStyle Hidden` in
  der Task-Action, oder ein echter Windows-Dienst. Beides ist noch offen.
- **Ein laufender Autostart galt als Fehlschlag.**
  `tools/Set-GuardianAutostart.ps1` wertete `LastTaskResult` mit `-ne 0` und
  meldete damit `Der letzte Lauf war nicht erfolgreich`, ging mit `exit 1`
  heraus. Am 04.10.2026 traf das einen gesunden Dauerlaeufer: `LastTaskResult`
  war `267009`, also `0x41301` `SCHED_S_TASK_RUNNING` - "laeuft gerade", ein
  Statuscode und fuer einen Dauerlaeufer der Sollzustand. Die Codes `0x41300`
  (bereit), `0x41301` (laeuft) und `0x41303` (noch nie gelaufen) werden jetzt
  als Status erkannt und mit `exit 0` beantwortet. Kleine Werte wie 1 oder 2
  sind Exit-Codes des gestarteten Programms und `0x8007xxxx` Windows-Fehler;
  beide bleiben Fehlschlaege.

- **Die Ein-Instanz-Sperre ist sitzungslokal, wenn `Global\` verweigert
  wird.** Ohne `SeCreateGlobalPrivilege` weicht der Kern auf `Local\` aus, und
  zwei Laeufe in verschiedenen Windows-Sitzungen sehen dann je eine eigene
  Sperre. Das ist eine Eigenschaft des Mechanismus, kein beobachteter Vorfall:
  Der Verdacht, am 04.10.2026 haetten Task und Konsole parallel geschrieben,
  liess sich nicht halten - der Task war zu dem Zeitpunkt bereits mit
  Exit-Code 1 beendet. Im selben Task-Setup (`-AtLogOn` ohne gespeichertes
  Kennwort) greift die Sperre dagegen nachweislich, belegt am 04.10.2026 durch
  `Prozess PASS` und zwei abgewiesene Testlaeufe.
- **Ein relatives `logDirectory` wird unterschiedlich aufgeloest.** Der Kern
  nimmt `Get-Location`, `tools/Get-GuardianHealth.ps1` nimmt den Skriptordner.
  Der Installer schreibt deshalb einen absoluten Pfad in `config/guardian.json`,
  und damit ist der Unterschied weg. Offen bleibt er fuer die mitgelieferte
  `config/guardian.example.json`, die weiterhin `artifacts` enthaelt: Wer den
  Kern von Hand aus einem beliebigen Ordner startet, prueft mit der
  Gesundheitspruefung ein anderes Log, als beschrieben wird.

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
