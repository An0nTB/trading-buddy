# Sonderfälle: synthetische Dateien nach echten Zeilen

Stand 01.10.2026. Alle Werte, Namen und Kennungen sind erfunden (`SYN`). Aufbau und Vorgangsarten folgen öffentlichen Beispielen echter Exporte. Inhalte daraus sind nicht übernommen.

| Datei | Vorbild | Was sie prüft |
|---|---|---|
| `trade_republic_sonderfaelle.csv` | Testdateien `TransactionExport01–06.csv` von Portfolio Performance (github.com/portfolio-performance/portfolio, Stand 30.09.2026) | Kapitalmaßnahmen (Split 10:1, Rückzahlung, Ausübung eines Optionsscheins), Fälligkeit und `TILG` als Verkauf, Dividenden-Korrektur, Einzahlung mit Gebühr, Kartenzahlung, Saveback, unbekannte Arten, Verkauf ohne Kauf, Kauf und Verkauf am selben Tag ohne Uhrzeit |
| `scalable_englisch.csv` | Zeilen aus dem PP-Forum „CSV-Import von Scalable Capital“ (2024) und Ghostfolio-Exporter Issue #272 (2025) | Englische Vorgangsarten (`Buy`, `Sell`, `Savings plan`, `Distribution`, `Deposit`, `Withdrawal`, `Taxes`), positive Stückzahl beim Verkauf, Gebühr ohne Minus, Buchungen um 01:00 oder 02:00 Ortszeit als „nur Datum“, neueste Zeile zuerst |

Annahmen ohne Beleg: Bedeutung von `Bonus` und `Security transfer` bei Scalable; Vorzeichen der Gebühr bei Scalable (Quellen uneins, der Importer bucht sie immer als Abzug).
