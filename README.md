# WLAN Guardian

Lokaler Windows-Sicherheitsmonitor für FRITZ!Box-Netzwerke mit Geräteerkennung, Ereignisüberwachung, Beweissicherung, Parental Control und optionaler Netzwerkpaketanalyse.

## Überblick

Das Projekt sammelt lokal WLAN- und Netzwerkinformationen auf einem Windows-Host und schreibt diese als JSON-Events und Geräte-Discovery-Daten. Der Kern arbeitet ohne externe Dienstleister und nutzt nur lokale Windows-APIs und lokale Dateien.

## Funktionen

- WLAN-Status-Erfassung mit SSID, Adapter, IPv4, Gateway und Internet-Prüfung
- Hash-basierte Ereignis-Kette für nachvollziehbare Zustandsänderungen
- Geräte-Discovery basierend auf der Windows-Neighbor-Tabelle
- Config-basierte Laufzeitparameter
- Log- und Artifact-Ausgabe in einem lokalen Verzeichnis
- Optionaler Aufbau für spätere Erweiterungen wie Capture, Evidence, Service und UI

## Voraussetzungen

- Windows 10/11
- PowerShell 5.1+ oder PowerShell 7+
- Optionale Anforderungen je nach Nutzung:
  - dotnet (für Build/Release-Checks)
  - Git, winget, Inno Setup (für Packaging / Installer-Workflows)

## Schnellstart

Aus dem Repository-Root:

```powershell
# Einmalige Auswertung
.\Start-Guardian.ps1 -Once

# Laufender Monitor
.\Start-Guardian.ps1
```

Mit eigener Konfiguration:

```powershell
.\Start-Guardian.ps1 -ConfigPath .\config\guardian.example.json -Once
```

## Konfiguration

Beispielkonfiguration:

```json
{
  "version": 1,
  "intervalSeconds": 30,
  "testHost": "1.1.1.1",
  "dnsName": "example.com",
  "logDirectory": "artifacts",
  "captureEnabled": false,
  "tr069Enabled": false
}
```

Wichtige Parameter:

- intervalSeconds: Polling-Intervall in Sekunden
- testHost: Zielhost für Ping/Reachability-Check
- dnsName: Domain für DNS-Validierung
- logDirectory: Ausgabeordner für Events und State-Dateien
- captureEnabled: optionaler Capture-Modus (noch nicht aktiv)
- tr069Enabled: optionaler TR-069-Integrationspfad (noch nicht aktiv)

## Ausgabedateien

Nach dem Start werden Dateien im konfigurierten Log-Verzeichnis erzeugt, zum Beispiel:

- guardian-events.jsonl
- guardian-chain.json

Zusätzlich kann das Geräte-Discovery über das Skript `src/Guardian-Devices.ps1` generiert werden:

```powershell
.\src\Guardian-Devices.ps1
```

## Projektstruktur

- `src/` – Kernskripte und Modul-Entry Points
- `config/` – Beispielkonfigurationen
- `tests/` – Release-/Qualitätssicherungsprüfungen
- `tools/` – Installations- und Verifikations-Helfer
- `docs/` – Design-, Sicherheits- und Release-Dokumentation

## Qualitätsregel

Das Projekt verwendet eine strikte Validierungslogik:

- Build -> Validate -> Test -> Fix -> Clean Build -> Test from zero
- Keine Teilinstallation darf als erfolgreich gelten
- Release-Gate: keine Fehler, keine unerwarteten Warnungen, keine fehlgeschlagenen Tests

## Hinweis

Die aktuelle Version ist als lokales Windows-Skript mit klarer, nachvollziehbarer Struktur umgesetzt. Erweiterungen wie Paket-Capture, Service-Integration, Evidence-Archivierung oder Betriebssystem-Installer sind im Repository dokumentiert, aber durch die vorhandenen Kernskripte schon nutzbar.
