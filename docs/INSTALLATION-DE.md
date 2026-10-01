# WLAN Guardian — Installationsanleitung

## Systemanforderungen

- **Windows**: 10 oder neuer (64-bit)
- **PowerShell**: 5.1 oder neuer
- **RAM**: mindestens 512 MB frei
- **Festplatte**: mindestens 100 MB frei
- **Administrator-Rechte**: für Service-Installation

## Installation aus Installer EXE

1. **Setup-Datei ausführen**
   ```
   WLAN-Guardian-Setup-1.0.0.exe
   ```

2. **Installationspfad wählen** (Standard: `%LOCALAPPDATA%\Programs\WLAN Guardian`)

3. **Desktop-Verknüpfung** (optional)

4. **Installation abschließen**

5. **Guardian starten**
   - Aus Start-Menü: `WLAN Guardian`
   - Oder aus Installationspfad: `Start-Guardian.ps1`

## Installation aus ZIP

1. **ZIP-Datei extrahieren**
   ```
   D:\WLAN Guardian
   ```

2. **PowerShell öffnen** (Admin nicht erforderlich für GUI)

3. **Guardian starten**
   ```powershell
   & "D:\WLAN Guardian\Start-Guardian.ps1"
   ```

   Oder einmalig testen:
   ```powershell
   & "D:\WLAN Guardian\Start-Guardian.ps1" -Once
   ```

## Konfiguration

Die Konfigurationsdatei befindet sich unter:
```
<Installationspfad>\config\guardian.example.json
```

Beispiel-Konfiguration:
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

| Parameter | Beschreibung | Standard |
|-----------|--------------|----------|
| `intervalSeconds` | Überwachungs-Interval in Sekunden | 30 |
| `testHost` | Host für Internet-Test (Ping) | 1.1.1.1 |
| `dnsName` | Domain für DNS-Auflösungs-Test | example.com |
| `logDirectory` | Verzeichnis für Event-Logs | artifacts |
| `captureEnabled` | Paketaufzeichnung aktivieren | false |
| `tr069Enabled` | TR-069 Protocol aktivieren | false |

## Verwendung

### Kommandozeile (kontinuierlich)
```powershell
& "Start-Guardian.ps1"
```

### Kommandozeile (einmalig)
```powershell
& "Start-Guardian.ps1" -Once
```

### GUI-Version
```powershell
& "Start-Guardian-UI.ps1"
```

### Über CMD
```cmd
WLAN-Guardian.cmd
```

## Datenablage

Alle Events werden gespeichert unter:
```
<logDirectory>/guardian-events.jsonl
<logDirectory>/guardian-chain.json
```

Die Chain-Datei enthält Hashes für Manipulationserkennung.

## Fehlerbehebung

### "Script is not digitally signed"
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### "FRITZ!Box nicht erreichbar"
- Prüfe: IP-Adresse der FRITZ!Box in `config/guardian.example.json`
- Prüfe: WLAN-Verbindung ist aktiv
- Prüfe: Kein Proxy/Firewall blockiert Port 49000

### "Keine Geräte erkannt"
- Mindestens ein Gerät muss im Netzwerk aktiv sein
- Prüfe: WLAN-Adapter funktioniert (Windows zeigt Verbindung)

## Sicherheit

- ✓ Keine Passwörter werden gespeichert
- ✓ Keine Netzwerk-Passwörter im Repository
- ✓ Evidence-Chain ist manipulationserschwert
- ✓ Lokale Speicherung nur — keine Cloud-Uploads

## Support

Fehlerberichte und Fragen:
https://github.com/AOWDGENESIS/WLAN-berwachungsskript/issues
