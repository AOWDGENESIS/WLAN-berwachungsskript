# GENESIS FRITZ!BOX GUARDIAN

Lokaler Windows-Sicherheitsmonitor für FRITZ!Box-Netzwerke mit Geräteerkennung, Netzwerküberwachung, Event- und Evidence-Management, Security-Basis und Installer-Workflow.

## Zielarchitektur

Das Projekt ist in klar getrennte Module unterteilt:

- `Guardian.Core` – Zustandsmaschine, Policy Engine, Konfiguration, Event- und Health-Modelle
- `Guardian.Service` – Windows-Service für laufende Überwachung ohne GUI
- `Guardian.UI` – Desktop-Oberfläche
- `Guardian.Tray` – Tray-Agent und Benachrichtigungen
- `Guardian.FritzBox` – TR-064/FRITZ!Box-Zugriff
- `Guardian.Network` – Netzwerk-/Adapter-/DNS-/Gateway-Status
- `Guardian.Devices` – Geräteerkennung und Geräteverwaltung
- `Guardian.Evidence` – Event- und Incident-Hash-Chain
- `Guardian.Security` – Autorisierung, Audit, Changelog, Lokal-Sicherheit
- `Guardian.Capture` – optionale Packet-Analyse, standardmäßig deaktiviert
- `Android Guardian Admin` – Android-Admin-Komponente mit Keystore-/Biometric-Guardrails

## Sicherheitsprinzipien

- Keine Passwörter/FRITZ!Box-Anmeldedaten im Repository
- Keine künstlich erfundenen Geräteinformationen
- `unknown` statt falscher Daten, falls keine verlässliche Identifikation vorliegt
- Paketaufzeichnung nur explizit aktiviert
- Evidence ist manipulationserschwert und auditierbar, aber nicht pauschal gerichtsfest

## Schnellstart

Einmaliger Lauf:

```powershell
.\Start-Guardian.ps1 -Once
```

Kontinuierliche Überwachung:

```powershell
.\Start-Guardian.ps1
```

## Windows-Release bauen

Der reproduzierbare Build erzeugt ein ZIP und mit Inno Setup zusätzlich eine
Installations-EXE:

```powershell
.\tests\Release-Gate.ps1
.\tools\Build-Release.ps1 -Version 1.0.0 -RequireInstaller
```

Wenn `ISCC.exe` nicht im PATH oder in `Program Files\Inno Setup 6` liegt,
kann der Pfad explizit angegeben werden:

```powershell
.\tools\Build-Release.ps1 -Version 1.0.0 -RequireInstaller `
    -InnoSetupPath "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

Die Artefakte liegen anschließend unter `build\`:
`WLAN-Guardian-1.0.0.zip` und `WLAN-Guardian-Setup-1.0.0.exe`.