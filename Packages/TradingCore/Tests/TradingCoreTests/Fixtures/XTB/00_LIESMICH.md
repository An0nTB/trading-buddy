# XTB: synthetische Excel-Dateien

Stand 01.10.2026. Alle Werte, Namen und Kennungen sind erfunden (`SYNTHETISCH`, `SYN`). Die Dateien entstehen mit `python3 erzeuge.py` (nur Standardbibliothek) und sind bei jedem Lauf gleich. Sollwerte der Tests unabhängig mit openpyxl 3.1.5 nachgerechnet.

| Datei | Vorbild | Was sie prüft |
|---|---|---|
| `xtb_einfach.xlsx` | Aufbau der R2-Testdatei (Recherche R2, 01.10.2026) | Beschriftung links, Wert rechts; Texte direkt in der Zelle; Zeiten als Text `TT/MM/JJJJ hh:mm:ss`; Summenzeile `Total`; CFD und Aktie gemischt; Kommission als eigene Kassenzeile |
| `xtb_sonderfaelle.xlsx` | Spalten und Kopfbereich nach xtb-xlsx-cleaner (github.com/Piotr20/xtb-xlsx-cleaner, Stand 28.12.2025); Vorgangsarten nach dem Beispielexport von Export-To-Ghostfolio (github.com/dickwolff/Export-To-Ghostfolio, `samples/xtb-export.csv`, Stand 06.02.2026) | Beschriftungen in Zeile 6 und Werte in Zeile 7, Kopf in Zeile 13; drittes Blatt mit offenen Positionen; gemeinsame Texte mit Formatierung und Lautschrift; Excel-Datumswerte über die Umstellung auf Sommerzeit; Gleitkomma-Reste wie `23.050000000000001`; leere Zeile mitten in der Tabelle; Spalten `Open origin` und `Close origin`; unbekannte Seite `BUY LIMIT`; Kassenarten `Profit/Loss (FX/CFD)`, `Stocks/ETF purchase`, `Rollover`, `DIVIDENT`, `Withholding tax`, `Free funds interests (tax)`, `SEC fee`, `Spin off`, `Subaccount Transfer`; `&` im Symbol |

Ausgedacht, um Robustheit zu prüfen: Spalten `Open origin` und `Close origin`, Kassenarten `Rollover` und `Subaccount Transfer`, Seite `BUY LIMIT`. Annahmen ohne Beleg: Zeitzone der Zeiten (Vorgabe deutsche Ortszeit); Zeiten als Excel-Datum statt als Text in echten Dateien (xtb-xlsx-cleaner liest beides); Lage der Summenzeile; Bedeutung von `Spin off` (der Importer bucht es als „sonstiges“ mit Hinweis). Die Importer gelten als ungeprüft, bis eine echte Datei durchgelaufen ist.
