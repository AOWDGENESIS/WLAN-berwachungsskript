# Guardian.UI Module

## Overview

The UI module provides a Windows Forms-based graphical interface for WLAN Guardian monitoring.

## Features

- Real-time network status display
- Device detection and monitoring
- Event log viewer
- Configuration management
- System tray integration

## Usage

```powershell
& "Start-Guardian-UI.ps1"
```

## Requirements

- Windows 10 or newer
- .NET Framework 4.5+
- PowerShell 5.1+

## Modules

- `Guardian.UI.psm1` - Main UI components
- `Guardian.Tray.ps1` - System tray integration

## Architecture

The UI follows a Model-View-ViewModel pattern:
- **Model**: Core Guardian modules (Devices, Network, Evidence)
- **View**: Windows Forms presentation layer
- **ViewModel**: Event distribution and state management
