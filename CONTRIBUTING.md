# Contributing / Mitwirken

## Deutsch

- Fehler und Verbesserungen bitte ueber GitHub **Issues** melden.
  **Keine echten IP-, MAC- oder SSID-Daten** und keine FRITZ!Box-Zugaenge
  anhaengen - nur synthetische Beispieldaten.
- Pull Requests sind willkommen: Beschreibung, reproduzierbare Schritte und
  Tests gehoeren dazu.
- Alle Gates muessen gruen sein:

  ```powershell
  ./tests/Release-Gate.ps1
  ./tests/Verify-Chain.ps1 -SelfTest
  ./tools/New-KitHashes.ps1 -Check
  ```

- Jede neue Erkennungs- oder Ereignisregel braucht einen reproduzierbaren Test
  mit **synthetischen** Fixtures. Echte Netzwerk-Mitschnitte gehoeren nicht ins
  Repository.
- PowerShell-Quellen sind **reines ASCII in UTF-8 ohne BOM**. Der CI-Job
  `cross-platform` prueft das und bricht sonst ab.
- `KIT-HASHES.json` wird nicht von Hand editiert, sondern mit
  `./tools/New-KitHashes.ps1` neu erzeugt.
- Keine Cloud-, Abo- oder Telemetrie-Funktionen. Alles bleibt lokal.
- Paketaufzeichnung bleibt standardmaessig deaktiviert und erfordert
  ausdrueckliches Opt-in (`captureEnabled`).

## English

- Please report bugs and improvements via GitHub **issues**. Do **not** attach
  real IP, MAC or SSID data and no FRITZ!Box credentials - use synthetic data.
- Pull requests are welcome: include a description, reproducible steps and tests.
- All gates must pass:

  ```powershell
  ./tests/Release-Gate.ps1
  ./tests/Verify-Chain.ps1 -SelfTest
  ./tools/New-KitHashes.ps1 -Check
  ```

- Back every new detection or event rule with a reproducible test using
  **synthetic** fixtures. Real network captures do not belong in this repository.
- PowerShell sources are **plain ASCII in UTF-8 without BOM**. The
  `cross-platform` CI job enforces this.
- Do not hand-edit `KIT-HASHES.json`; regenerate it with
  `./tools/New-KitHashes.ps1`.
- No cloud, subscription or telemetry features. Everything stays local.
- Packet capture stays disabled by default and requires explicit opt-in.
