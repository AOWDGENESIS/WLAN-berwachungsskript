# WLAN Guardian Installer

This directory contains the Windows installer definition. The installer packages the PowerShell monitoring application and creates Start Menu shortcuts.

Build requirements:

- Windows 10/11
- PowerShell 5.1+
- Inno Setup 6 (`ISCC.exe`) for an installer EXE

The installer does not bundle Wireshark, Npcap, FRITZ!Box credentials, or any other third-party software.