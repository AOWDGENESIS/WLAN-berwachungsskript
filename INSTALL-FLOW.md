# Automatischer Installationsablauf

1. Administratorrechte pruefen
2. Windows-Version/Architektur pruefen
3. Speicherplatz pruefen
4. vom Benutzer gewaehlte Installationspfade erfassen
5. vorhandene Komponenten erkennen
6. fehlende Komponenten bestimmen
7. offizielle Quelle aufloesen
8. Download in Cache
9. SHA-256 pruefen
10. Signatur pruefen, soweit vorhanden
11. Installer starten
12. Installation validieren
13. Guardian initialisieren
14. Datenbank erzeugen/migrieren
15. Service registrieren
16. Health Check
17. Rollback bei Fehler
18. Abschlussbericht

Kein Teilinstallationszustand darf als erfolgreich gemeldet werden.
