# Oberflaeche und Infobereich

## Was laeuft

Der Daemon schreibt, die Oberflaeche liest. Beide haengen an derselben
`guardian-events.jsonl`, aber nur der Daemon haelt die Ein-Instanz-Sperre.
Oberflaeche und Tray-Symbol koennen deshalb laufen, waehrend der Daemon laeuft.

```
src/Guardian.ps1              schreibt Ereignisse, haelt die Sperre
src/Guardian.UI/Guardian.UI.ps1      liest das Log, zeigt es an
src/Guardian.Tray/Guardian.Tray.ps1  Symbol im Infobereich, startet die Oberflaeche
```

## Starten

Nach der Installation liegt beides als geplanter Task vor:

| Task | Ausloeser | Inhalt |
| --- | --- | --- |
| `WLAN Guardian` | bei Anmeldung | der Daemon, versteckt |
| `WLAN Guardian UI` | keiner | Tray-Symbol, wird vom Installer einmal gestartet |

Von Hand:

```powershell
./Start-Guardian-UI.ps1
./src/Guardian.Tray/Guardian.Tray.ps1 -ConfigPath config\guardian.json -UiStarten
Start-ScheduledTask -TaskName 'WLAN Guardian UI'
```

## Oberflaeche

Fenster mit Status, SSID, Adapter, IPv4, Gateway, DNS, Internet, Daemon-Zustand,
Loggroesse, Zeit des letzten Ereignisses und den letzten 60 Ereignissen als
Tabelle. Aktualisierung alle fuenf Sekunden, und die Tabelle wird nur neu
gebaut, wenn sich etwas geaendert hat - sonst flackert sie.

Knoepfe: `Aktualisieren`, `Log-Ordner oeffnen`, `Daemon starten`,
`Daemon stoppen`, `Fenster schliessen`.

`Daemon stoppen` beendet den Task und danach gezielt nur `pwsh`-Prozesse, die
`Start-Guardian.ps1` in der Befehlszeile haben. Nie pauschal alle `pwsh` - das
wuerde offene Konsolen toeten.

## Infobereich

Das Symbol ist gruen bei `ONLINE`, rot bei `OFFLINE`, orange bei unbekannt.
Doppelklick oeffnet die Oberflaeche. Beim Wechsel des Zustands erscheint eine
Ballonmeldung, aber nur bei echter Aenderung.

Die drei Icons werden einmal gebaut. `Icon.FromHandle` uebergibt einen nativen
Handle, und ein Icon, das alle fuenf Sekunden neu entsteht, wuerde ueber Tage
Tausende Handles ansammeln.

## Voraussetzungen

Windows Forms, also Windows. Getestet mit PowerShell 7.6.6. Die Oberflaeche
braucht keine Administratorrechte.

## Geschichte

Bis einschliesslich `119d706` war `Guardian.UI.ps1` ein Platzhalter: kein
`ShowDialog()`, das Feld `GuardianState` statt `status`, und ein hardkodiertes
`artifacts`. Das Fenster erschien nie. `src/Guardian.Tray/` enthielt eine
modulare Schleife, die nie lief und von niemandem aufgerufen wurde.
