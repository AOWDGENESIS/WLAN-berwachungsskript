# Architecture

WLAN Guardian follows a modular PowerShell architecture:

```
Guardian
├── Core (State, Config, Health)
├── Devices (Discovery, Identification)
├── Network (Adapter, DNS, Gateway)
├── FritzBox (TR-064 Interface)
├── Service (Background Service)
├── UI (Desktop GUI)
├── Tray (System Tray Agent)
├── Evidence (Chain of Custody)
├── Security (Auth, Audit)
└── Capture (Packet Analysis - optional)
```
