# Distribution Policy

Guardian bevorzugt kostenlose und Open-Source-Komponenten.

Wir unterscheiden:
1. Projektbestandteile
2. Build-Abhaengigkeiten
3. optionale Laufzeitkomponenten
4. externe Installer

Wireshark:
Die offizielle Windows-Version enthaelt Npcap fuer Live Packet Capture.
Npcap hat eigene Lizenzbedingungen. Deshalb wird kein eigener Npcap-Bundle
gebaut. Der offizielle Wireshark-Installer wird verwendet.

Jede externe Datei:
- kommt aus einer definierten offiziellen Quelle
- wird heruntergeladen
- wird auf Hash/Signatur geprueft
- wird erst danach ausgefuehrt
- wird mit Version und Hash im Release-Manifest dokumentiert
