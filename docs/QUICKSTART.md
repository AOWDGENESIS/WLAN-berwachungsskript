# WLAN Guardian Quick Start

## Installation

### Option 1: Installer EXE
```
WLAN-Guardian-Setup-1.0.0.exe
```

### Option 2: Extract ZIP
```powershell
Expand-Archive -Path "WLAN-Guardian-1.0.0.zip" -DestinationPath "D:\WLAN Guardian"
```

## First Run

### Test (once, no service)
```powershell
cd "D:\WLAN Guardian"
powershell -ExecutionPolicy Bypass -File "Start-Guardian.ps1" -Once
```

Expected output:
```json
{"timestamp":"2026-10-01T08:23:07...","status":"ONLINE","ssid":"YourNetwork",...}
```

### Continuous Monitoring (Console)
```powershell
& "D:\WLAN Guardian\Start-Guardian.ps1"
```

### GUI Mode
```powershell
& "D:\WLAN Guardian\Start-Guardian-UI.ps1"
```

### Windows Service (if you want to monitor in background)
```powershell
# From admin PowerShell
New-Service -Name "WLAN-Guardian" `
  -BinaryPathName "powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\WLAN Guardian\Start-Guardian.ps1'" `
  -DisplayName "WLAN Guardian" -StartupType Automatic

Start-Service "WLAN-Guardian"
```

## Configuration

Edit: `config/guardian.example.json`

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

## Output

Events logged to:
- `artifacts/guardian-events.jsonl` - Event stream
- `artifacts/guardian-chain.json` - Integrity chain

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Script is not signed" | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| "Config not found" | Ensure `config/guardian.example.json` exists |
| No devices detected | Check WLAN connection; requires active devices on network |
| High CPU usage | Increase `intervalSeconds` in config |

## Next Steps

- Read `docs/MODULE-REFERENCE.md` for full API
- Review `docs/INSTALLATION-DE.md` for detailed German guide
- Check GitHub issues for known limitations

## Support

https://github.com/AOWDGENESIS/WLAN-berwachungsskript/issues
