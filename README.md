# GENESIS FRITZ!BOX GUARDIAN

Lokaler Windows-Sicherheitsmonitor für WLAN- und FRITZ!Box-Umgebungen mit Geräteerkennung, Ereignisüberwachung, Evidence-Tracking und Installer-/Release-Workflow.

## Zielarchitektur

Das Projekt ist modular aufgebaut und enthält die wichtigsten Bausteine für Monitoring, UI, Service und Paketierung:

- `Guardian.Core` – Zustandsmaschine, Konfiguration, Health-Modelle
- `Guardian.Network` – Adapter-, DNS-, Gateway- und Internetstatus
- `Guardian.Devices` – Geräteerkennung und Nachbarschafts-Scan
- `Guardian.Evidence` – Event- und Hash-Kette für Audit- und Integritätsprüfung
- `Guardian.UI` – Lokale Desktop-Oberfläche
- `Guardian.Service` – Hintergrund-Service / Windows-Service
- `Guardian.Tray` – Tray-Integration und Benachrichtigungen
- `Guardian.Capture` – optionale Paketanalyse, standardmäßig deaktiviert

## Sicherheitsprinzipien

- Keine Passwörter oder FRITZ!Box-Anmeldedaten im Repository
- Keine künstlich erfundenen Geräteinformationen
- `unknown` statt falscher Daten, wenn keine verlässliche Identifikation vorliegt
- Paketaufzeichnung nur explizit aktiviert
- Evidence ist manipulationserschwert und auditierbar, aber nicht pauschal gerichtsfest

## Schnellstart

### Einmaliger Lauf

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Guardian.ps1 -Once
```

### Laufende Überwachung im Konsolenmodus

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Guardian.ps1
```

### GUI starten

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Guardian-UI.ps1
```

### CMD-Launcher

```cmd
WLAN-Guardian.cmd
WLAN-Guardian-UI.cmd
```

## Projektstruktur

```text
WLAN-berwachungsskript/
├── .github/
│   └── workflows/
│       └── build.yml
├── artifacts/
├── build/
├── config/
│   └── guardian.example.json
├── docs/
│   ├── INSTALLATION-DE.md
│   ├── QUICKSTART.md
│   ├── RELEASE-CHECKLIST.md
│   ├── GUARDIAN-UI.md
│   ├── GUARDIAN-SERVICE.md
│   ├── MODULE-REFERENCE.md
│   └── IMPLEMENTATION-STATUS.md
├── installer/
│   ├── README.md
│   └── WLAN-Guardian.iss
├── src/
│   ├── Guardian.ps1
│   ├── Guardian.Core/
│   │   └── Guardian.Core.psm1
│   ├── Guardian.Network/
│   │   └── Guardian.Network.psm1
│   ├── Guardian.Devices/
│   │   └── Guardian.Devices.psm1
│   ├── Guardian.UI/
│   │   ├── Guardian.UI.psm1
│   │   └── Guardian.UI.ps1
│   ├── Guardian.Service/
│   │   └── Guardian.Service.ps1
│   ├── Guardian.Tray/
│   │   └── Guardian.Tray.ps1
│   └── Guardian.Capture/
│       └── Guardian.Capture.psm1
├── tests/
│   └── Release-Gate.ps1
├── tools/
│   ├── Install-Dependencies.ps1
│   ├── Build-Release.ps1
│   ├── Release-Builder.ps1
│   └── Verify-Release.ps1
├── .gitignore
├── INSTALL-FLOW.md
├── KIT-HASHES.json
├── LICENSE
├── README.md
├── Start-Guardian.ps1
├── Start-Guardian-UI.ps1
├── WLAN-Guardian.cmd
├── WLAN-Guardian-UI.cmd
└── release-manifest.example.json
```

## Konfiguration

Die Standardkonfiguration liegt in:

```text
config\guardian.example.json
```

Beispiel:

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

## Ausgabe / Logs

Während der Laufzeit werden Events als JSON-Lines protokolliert:

- `artifacts\guardian-events.jsonl`
- `artifacts\guardian-chain.json`

## Verifikation

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Verify-Release.ps1
```

## Build / Release

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Release-Builder.ps1
```

## Fehlerbehebung

### Skript wird blockiert

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Keine UI

Prüfe, ob die Datei `src\Guardian.UI\Guardian.UI.psm1` vorhanden ist und starte anschließend:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Guardian-UI.ps1
```

### Kein Netzwerkstatus

Prüfe die Konfiguration in `config\guardian.example.json` und die aktive WLAN-Verbindung im Windows-System.

## Support

- GitHub Issues: https://github.com/AOWDGENESIS/WLAN-berwachungsskript/issues
- Installationsdetail: `docs\INSTALLATION-DE.md`

