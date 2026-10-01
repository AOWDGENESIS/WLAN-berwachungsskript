# WLAN Guardian Module Reference

## Core Modules

### Guardian.Core
**State machine, configuration, health models**
- `New-GuardianState` - Initialize state
- `Set-GuardianState` - Update state
- `Read-GuardianConfig` - Load configuration

### Guardian.Network
**Adapter, DNS, Gateway monitoring**
- `Get-GuardianNetworkState` - Network status
- IPv4 configuration tracking
- Gateway detection

### Guardian.Devices
**Device detection and identification**
- `Get-GuardianDevices` - Discover devices
- MAC address resolution
- Device role classification (gateway/device)

### Guardian.Evidence
**Event and incident chain-of-custody**
- Hash-based chain validation
- Tamper detection
- Audit trail

### Guardian.Security
**Authorization and audit**
- Permission management
- Change logging
- Security event tracking

### Guardian.FritzBox (Optional)
**TR-064 FRITZ!Box interface**
- Device enumeration via TR-064
- Parental control integration
- Network configuration access

### Guardian.Capture (Optional)
**Network packet analysis**
- Requires Wireshark/Npcap
- Disabled by default
- Enable in config: `"captureEnabled": true`

## Module Loading

```powershell
Import-Module ".\src\Guardian.Core\Guardian.Core.psm1"
Import-Module ".\src\Guardian.Network\Guardian.Network.psm1"
Import-Module ".\src\Guardian.Devices\Guardian.Devices.psm1"
```

## Event Format

All events are logged as JSONL (JSON Lines):

```json
{
  "timestamp": "2026-10-01T08:23:07.2587977Z",
  "status": "ONLINE",
  "ssid": "KKNet157",
  "adapter": "WLAN 2",
  "ipv4": "192.168.178.32",
  "gateway": "192.168.178.1",
  "dnsOk": true,
  "internetOk": true
}
```

## Configuration Schema

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

## Error Handling

All modules use `$ErrorActionPreference = "Stop"` for strict error handling.

Common patterns:
- Missing configuration → throws immediately
- Network errors → logged with retry strategy
- Device enumeration → continues on individual device failures

## Security Principles

- No plaintext passwords in logs
- No FRITZ!Box credentials in repository
- Evidence chain is tamper-resistant
- Local storage only — no cloud uploads
- Encryption at rest recommended for production
