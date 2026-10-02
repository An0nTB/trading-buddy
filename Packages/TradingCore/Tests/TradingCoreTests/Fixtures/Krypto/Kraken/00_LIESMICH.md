# Kraken-Testdateien (synthetisch)

Erzeugt mit `python3 erzeuge.py` (01.10.2026). Keine echten Konten, Kennungen erfunden.

| Datei | Inhalt |
|---|---|
| kraken_einfach.csv | CRLF, alle Felder in Anführungszeichen, alte Paare (XXBTZEUR, XETHZUSD) und neue (SOL/EUR), Sekundenbruchteile, 29.03.2026 (Zeitumstellung in Europa, in UTC ohne Wirkung) |
| kraken_sonderfaelle.csv | BOM, LF, Krypto gegen Krypto (XETHXXBT), Margin-Trade, XXDG, Paar ohne Präfix (ADAEUR), USDT als Gegenwährung, unbekannter Typ „settle“ |

Sollwerte (Python, unabhängig vom Swift-Code): einfach Kassenwirkung −1.437,8415, FIFO netto BTC/EUR 21,815 und SOL/EUR 44,2435, ETH/USD bleibt offen; Sonderfälle Kassenwirkung 297,40, Hinweise in Zeile 2, 3 und 7.

Quellen zum Aufbau: Kraken Support, Artikel 360001184886 und 360001206766 (2025/2026, Trades-Export, Spalten); docs.kraken.com „Get Trades History“ (2026: `cost` und `fee` in der Gegenwährung); R2 Abschnitt 4 (01.10.2026); CoinTaxman src/book.py (2026) als Zweitquelle. Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
