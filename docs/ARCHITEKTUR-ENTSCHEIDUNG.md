# Architektur-Entscheidung: zwei Implementierungen

Stand: 2026-10-02

## Befund

Im Baum liegen zwei parallele Implementierungen der Ueberwachung.

**Pfad A - Monolith, erreichbar und gelaufen**

```
WLAN-Guardian.cmd -> Start-Guardian.ps1 -> src/Guardian.ps1
```

`src/Guardian.ps1` enthaelt `Get-WlanState`, `Get-Sha256` und
`Write-GuardianEvent` selbst und laedt kein Modul. Dieser Pfad ist am
02.10.2026 unter PowerShell 7.6.6 real durchgelaufen: SSID, Adapter, IPv4,
Gateway, DNS und Internet wurden erfasst, ein Ereignis geschrieben, die Kette
verifiziert.

**Pfad B - modular, nie gelaufen**

```
(niemand) -> src/Guardian.Tray/Guardian.Tray.ps1 -> src/Guardian.Service/Guardian.Service.ps1
             -> Guardian.Core, Guardian.Network, Guardian.Devices, Guardian.Evidence
```

Zwei Gruende, warum dieser Pfad nie funktioniert hat:

1. `Guardian.Tray.ps1` hatte einen falschen `$root` und baute
   `src\Guardian.Tray\src\Guardian.Service\...`. Diese Datei existiert nicht.
2. `Guardian.Service.ps1` hatte denselben Fehler eine Ebene flacher. Damit
   schlugen **alle vier** `Import-Module` fehl, bevor irgendetwas anderes lief.

Beide sind behoben (Commit `4829fc4`), aber ein Lauf hat das nicht bestaetigt.

Von 11 exportierten Modulfunktionen hatten 6 keine Aufrufer. `src/Guardian-Devices.ps1`
wurde nur von `tests/Release-Gate.ps1` als "muss existieren" geprueft, aber nie
ausgefuehrt - damit war auch der Fix aus Commit `3cc7e93` wirkungslos.

## Entscheidung

**Pfad A bleibt die MVP-Implementierung.** Pfad B wird nicht entfernt, aber als
noch nicht verdrahtet gekennzeichnet.

Begruendung: Pfad A ist der einzige Pfad mit einem echten Lauf. Pfad B
umzubauen oder zum Hauptpfad zu machen bedeutet, die einzige getestete
Komponente durch eine nie ausgefuehrte zu ersetzen. In einer Bauumgebung ohne
PowerShell-Laufzeit ist das nicht zu verantworten.

## Kollisionsrisiko und seine Behandlung

Beide Pfade haengen an dieselbe `guardian-events.jsonl`, fuehren aber je eine
eigene State-Datei (`guardian-chain.json` gegenueber `<log>.state.json`). Liefen
beide gleichzeitig, waere die Kette fuer beide unpruefbar.

Behandelt durch die Ein-Instanz-Sperre (Commit `59501ed`): Der zweite Start
bricht mit `Guardian laeuft bereits` ab, statt die Datei zu teilen. Damit ist
die Kollision ausgeschlossen, solange die Sperre greift.

## Was den toten Code inzwischen belebt

`src/Guardian-Devices.ps1` wird seit der Geraeteverlauf-Umsetzung (D9) vom Kern
aufgerufen und ausgewertet. Damit ist die Datei mit dem Fix `3cc7e93`
erreichbar. Die Module `Guardian.Capture`, `Guardian.FritzBox` und
`Guardian.Security` bleiben unverdrahtet - ihre Funktionen `Get-CapturePolicy`,
`Get-FritzBoxPolicy` und `Test-GuardianAuthorization` haben weiterhin keine
Aufrufer.

## Voraussetzung fuer einen spaeteren Wechsel auf Pfad B

1. Ein realer Lauf von `Guardian.Service.ps1` unter PowerShell, protokolliert.
2. Nachweis, dass `Write-GuardianEvidence` und `Write-GuardianEvent` dieselbe
   Kette erzeugen - beide nutzen `SHA256(previous + json)`, aber die
   State-Formate unterscheiden sich.
3. Entscheidung, ob `Set-GuardianState` mit seinen zehn Zustaenden den
   Drei-Zustands-Status des Monolithen (`ONLINE`, `LOCAL_ONLY`, `OFFLINE`)
   ersetzt oder ergaenzt.
4. Erst dann Pfad A zurueckziehen, nicht vorher.

## C7 SQLite-Persistenz: zurueckgestellt

Nicht Teil des MVP, und bewusst nicht halb eingebaut.

Gruende:

- PowerShell bringt keinen SQLite-Treiber mit. Noetig waere
  `System.Data.SQLite` oder `Microsoft.Data.Sqlite` als Assembly, also eine
  binaere Abhaengigkeit, die der Nutzer erst installieren muesste. Das
  widerspricht dem Ziel, ohne Installation und ohne Fremdabhaengigkeit zu laufen.
- Die MVP-Anforderung ist JSONL-Logging mit manipulationssicherer Kette. Beides
  ist erfuellt: JSONL ist anhaengend, und die Hash-Kette ist nachtraeglich
  pruefbar.
- Was SQLite zusaetzlich braechte, ist Abfragbarkeit ueber lange Zeitraeume.
  Dafuer reicht heute die Log-Rotation mit `maxLogBytes` und `maxLogFiles`.

Voraussetzung, falls es spaeter kommt: ein Treiber, der ohne Admin-Rechte und
ohne Netz auskommt, plus ein Migrationspfad von JSONL nach SQLite, der die
bestehende Kette nicht verwirft.
