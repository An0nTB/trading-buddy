# Coinbase-Testdateien (synthetisch)

Erzeugt mit `python3 erzeuge.py` (02.10.2026). Keine echten Konten, Kennungen erfunden. Das Skript rechnet die Sollwerte mit eigenem Leser.

| Datei | Inhalt |
|---|---|
| coinbase_v4.csv | Kopf ab 2023/2024 mit `ID`, Vorspann Leerzeile, „Transactions“, Nutzerzeile; Zeit „… UTC“; Beträge mit „€“, Tausenderkommas in Anführungszeichen, Verkäufe negativ; Buy, Sell, Advanced Trade, drei Convert (lesbar, Tausenderkomma, mehrdeutig „1,234 XRP“), Staking, Rewards, Learning Reward, Ein- und Auszahlung EUR, Send, Receive, unbekannte Art |
| coinbase_v3.csv | Kopf Ende 2021 bis 2023/2024 (`Spot Price Currency`), Vorspann mit Steuersatz, ISO-Zeit mit „Z“, keine ID; Coinbase Earn, Send ohne Beträge |
| coinbase_v1.csv | Kopf bis Mitte 2021 (`EUR Subtotal`), Währung nur im Spaltennamen; Kauf ohne Subtotal (Wert = Menge × Preis) |

Sollwerte (Python, unabhängig vom Swift-Code): v4 11 Ausführungen, 5 Geldbewegungen, Hinweise in Zeile 11, 17, 18, 19, Kassenwirkung 89,70 EUR; v3 Kassenwirkung −31,65, Hinweis Zeile 12; v1 Kassenwirkung 425,00. BTC-Runde v4: Kauf 489,00 gesamt, Verkauf 487,00 netto, Ergebnis −2,00 EUR inklusive Kosten 18,00 (wie R2).

Quellen zum Aufbau: CoinTaxman src/book.py, github.com/provinzio/CoinTaxman (2026: Köpfe v1 bis v4, Vorspann, Zeitformate, Convert-Text „Converted X A to Y B“, Coinbase Earn und Learning Reward als Kauf, Rewards Income als Staking, Subtotal-Ersatz aus Menge × Preis); R2 Abschnitt 4 (01.10.2026); Coinbase Help „Statements“ (2026). Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
