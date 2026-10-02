# Bitpanda-Testdateien (synthetisch)

Erzeugt mit `python3 erzeuge.py` (02.10.2026). Keine echten Konten, Kennungen erfunden.

| Datei | Inhalt |
|---|---|
| bitpanda_neu.csv | sechs Hinweiszeilen, Kopf in Zeile 7 mit 17 Spalten (mit „Tax Fiat“), CRLF, Anführungszeichen nur wo nötig; Fiat-Einzahlung und -Auszahlung mit Gebühr, BTC-Runde über die Zeitumstellung am 29.03.2026, ETH-Kauf mit Gebühr in BEST, Staking-Ertrag „rewards“, transfer(stake), Krypto-Auszahlung, Verkauf mit Steuer, transfer (Airdrop), Kauf gegen TRY |
| bitpanda_alt.csv | BOM, LF, alle Felder in Anführungszeichen, Kopf mit 16 Spalten ohne „Tax Fiat“ |

Sollwerte (Python, unabhängig vom Swift-Code): neu Kassenwirkung 587,65, FIFO netto BTC/EUR 14,65 und ETH/EUR 14,00, offen bleiben die ETH-Käufe SYN-BP-0003 (Rest) und SYN-BP-0004; Hinweise in Zeile 10, 13, 14, 15, 17 und 18. Alt: Kassenwirkung 1.014,65, keine Hinweise.

Formatannahmen und Belege:
- Kopf und Vorspann: CoinTaxman src/book.py (GitHub, Abruf 01.10.2026; Kopf in Zeile 7, 16 Spalten); BittyTax src/bittytax/conv/parsers/bitpanda.py (GitHub, Abruf 01.10.2026; zusätzliche Spalte „Tax Fiat“).
- Amount Fiat bei buy und sell enthält die Gebühr in Fiat: Annahme aus beiden Parsern (CoinTaxman rechnet Preis = Amount Fiat / Amount Asset, BittyTax bucht Amount Fiat als vollen Gegenwert). Von Bitpanda nicht belegt; Bitpanda-Hilfeseiten waren aus der Sandbox nicht erreichbar.
- Einzahlung: Amount Fiat nach Gebühr; Auszahlung: Gebühr zusätzlich (BittyTax).
- Staking-Erträge heißen „rewards“, vor dem 14.06.2022 eingehender „transfer“ (CoinTaxman Issue 155, GitHub).
- Spread steckt im Preis und wird nicht getrennt gebucht; „Tax Fiat“ wird nur als Hinweis gemeldet, weil unbelegt ist, ob Amount Fiat die Steuer schon enthält.

Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
