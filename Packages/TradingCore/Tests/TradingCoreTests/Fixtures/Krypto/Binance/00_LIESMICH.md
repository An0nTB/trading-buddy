# Binance-Testdateien (synthetisch)

Erzeugt mit `python3 erzeuge.py` (02.10.2026). Keine echten Konten, Werte erfunden.

| Datei | Inhalt |
|---|---|
| binance_einfach.csv | LF, ohne BOM, Tausenderkomma in Price und Amount (in Anführungszeichen), Gebühr in der Basis (Kauf BTC) und in der Gegenwährung, USDT als Gegenwährung, 29.03.2026 (Zeitumstellung, in UTC ohne Wirkung), zwei gleiche Teilausführungen in derselben Sekunde |
| binance_sonderfaelle.csv | BOM, CRLF, Krypto gegen Krypto (ETHBTC), Gebühr in BNB, Basis mit Ziffer am Anfang (1INCH), Gebühr in der Basis bei BNB-Kauf und bei einem Verkauf, Paar passt nicht zum Kürzel von Amount, Gebühr 0 in BNB |
| binance_transaktionen.csv | Transaktionsverlauf v3 (User ID, Time, Account, Operation, Coin, Change, Remark), wird erkannt und abgelehnt |

Sollwerte (Python, unabhängig vom Swift-Code): einfach Kassenwirkung −484,93938, FIFO netto BTC/EUR 18,76062 und ETH/USDT 96,90, SOL/EUR bleibt mit zwei Käufen offen; Sonderfälle Kassenwirkung 269,34, Hinweise in Zeile 2, 3 (Gebühr BNB, Trade ohne Gebühr verbucht) und 7.

Formatannahmen:
- Kopf `Date(UTC),Pair,Side,Price,Executed,Amount,Fee`, Kürzel ohne Trenner an Executed, Amount und Fee, Paar ohne Trenner: R2 Abschnitt 4 und R2_Testdaten (Sekundärquelle 2021, Spaltennamen seit 2021 unverändert laut Einschätzung).
- Zeiten in UTC, Export höchstens 6 Monate je Datei: Binance FAQ (2026), siehe R2.
- Gebühr häufig in BNB: Binance FAQ (2025/2026), siehe R2.
- Gebühr in der Basis beim Verkauf: nicht belegt, symmetrisch zum Kauf behandelt (Einschätzung).
- Transaktionsverlauf v1 bis v3: CoinTaxman src/book.py (2026).

Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
