# Guardian.Service Module

## Overview

The Service module provides background service functionality for continuous WLAN Guardian monitoring without GUI.

## Features

- Windows Service registration and management
- Automatic startup on system boot
- Background event processing
- Health monitoring
- Automatic restart on failure

## Installation as Service

```powershell
# Register service
New-Service -Name "WLAN-Guardian" `
  -BinaryPathName "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\Path\To\Start-Guardian.ps1`"" `
  -DisplayName "WLAN Guardian" `
  -StartupType Automatic

# Start service
Start-Service -Name "WLAN-Guardian"
```

## Management

```powershell
# Check status
Get-Service -Name "WLAN-Guardian"

# Stop service
Stop-Service -Name "WLAN-Guardian"

# Remove service
Remove-Service -Name "WLAN-Guardian"
```

## Architecture

- **Core**: Guardian.Core for state management
- **Modules**: Device detection, network monitoring, evidence storage
- **Recovery**: Automatic restart on crash
- **Logging**: Event log integration
