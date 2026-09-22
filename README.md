# Installer

Zwei Ebenen:

1. Bootstrapper
   - erkennt fehlende Komponenten
   - laesst Installationspfade waehlen
   - laedt offizielle Pakete
   - prueft Hash/Signatur
   - installiert
   - validiert
   - rollt bei Fehlern zurueck

2. Guardian Installer
   - Service
   - UI/Tray
   - Datenbankmigration
   - Firewall-Regeln
   - Repair
   - Uninstall

Wireshark/Npcap:
Offiziellen Wireshark Windows Installer verwenden. Dieser enthaelt Npcap
fuer Live Capture. Keine eigene Npcap-Weiterverteilung.
