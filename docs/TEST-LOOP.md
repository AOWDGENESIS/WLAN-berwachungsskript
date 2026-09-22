# Test- und Reparaturregel

BUILD -> VALIDATE -> TEST -> FAIL -> ROOT CAUSE -> FIX -> CLEAN BUILD -> TEST FROM ZERO

Ein Fehler wird nicht uebersprungen.

Testgruppen:
- Encoding
- Strings
- JSON/XML
- Pfade
- .NET Build
- Installer
- Service
- SQLite
- FRITZ!Box
- Netzwerk
- Evidence Chain
- Notifications
- Android Admin
- Upgrade
- Uninstall
- Clean Reinstall
- Final Regression

Release Gate:
ERRORS = 0
UNEXPECTED WARNINGS = 0
FAILED TESTS = 0
UNRESOLVED BLOCKERS = 0
