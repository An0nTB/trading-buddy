# Krypto

Spot, Börsen, Verwahrung, Perpetuals. Steuern stehen in Kapitel 11.

## 1. Was beim Krypto-Handel anders ist [G]

- **24/7**: Kein Börsenschluss, keine Auktion, aber auch keine Pause. Gaps entstehen eher durch dünne Liquidität am Wochenende als durch Schließzeiten.
- **Schwankung**: deutlich höher als bei großen Aktienindizes. Gleiche Positionsgröße bedeutet daher höheres Risiko je Trade. Einschätzung; am eigenen Datensatz messbar (ATR je Instrument).
- **Viele Handelsplätze** mit eigenen Preisen. Der „Bitcoin-Kurs“ ist je Börse leicht verschieden.
- **Gebühren in Kryptowährung**: Börsen ziehen Gebühren oft in der gehandelten Coin oder im eigenen Börsen-Token ab. Für die Euro-Auswertung muss jede Gebühr zum Kurs des Zeitpunkts umgerechnet werden.

## 2. Wege, Krypto zu handeln [G]

| Weg | Eigentum | Typische Kosten | Hinweise |
|---|---|---|---|
| Zentrale Börse (CEX), Spot | Ja, verwahrt von der Börse | Maker/Taker-Gebühr, Spread | Ausfall- und Sperrrisiko der Börse |
| Neobroker mit Krypto | Je nach Modell | Spread, Ordergebühr | Auszahlung auf eigene Wallet nicht immer möglich |
| Dezentrale Börse (DEX) | Ja, eigene Wallet | Netzwerkgebühr, Pool-Gebühr, Slippage | Smart-Contract-Risiko, keine Rückabwicklung |
| Krypto-CFD | Nein | Spread, Finanzierung | Für Privatkunden in Deutschland Hebel höchstens 2:1 (BaFin 2019) |
| Perpetual Futures | Nein | Gebühr, Funding | Hebel, Liquidation, siehe Abschnitt 4 |
| Krypto-ETP/ETN | Nein, Wertpapier | TER, Spread | Über Wertpapierdepot handelbar |

## 3. Verwahrung [G/F]

- **Selbstverwahrung**: Der private Schlüssel (Seed-Phrase) liegt beim Besitzer. Geht er verloren, ist der Bestand weg. Gibt ihn jemand anderes ein, ist der Bestand auch weg.
- **Verwahrung bei der Börse**: bequem, aber Gegenparteirisiko. Seit MiCA brauchen Anbieter eine EU-Zulassung (Abschnitt 5).
- Überträge zwischen eigenen Wallets sind **keine Trades** und dürfen nicht als Verkauf zählen. Einzahlung, Auszahlung, Übertrag und Tausch sauber trennen.

## 4. Perpetual Futures („Perps“) [F/P]

- Termingeschäft ohne Verfallstag. Eingeführt von BitMEX im Jahr 2016; heute das meistgehandelte Krypto-Derivat (Einschätzung; Herkunft belegt).
- **Funding Rate**: Damit der Perp-Preis nahe am Spotpreis bleibt, zahlen in festen Abständen (oft alle 8 Stunden, je Börse prüfen) die Longs an die Shorts oder umgekehrt. Liegt der Perp über Spot, zahlen meist die Longs.
- **Mark Price**: Referenzpreis, an dem die Börse Gewinne, Verluste und Liquidation misst. Er kann vom letzten Handelspreis abweichen.
- **Liquidation**: Fällt die Sicherheit unter die Erhaltungsmarge, schließt die Börse die Position zwangsweise, oft mit Zusatzgebühr.
- **Isolated Margin**: Risiko auf die eine Position begrenzt. **Cross Margin**: Das ganze Konto haftet.
- Funding-Zahlungen sind laufende Kosten oder Erträge wie der Swap beim CFD. Ohne sie ist das Ergebnis eines Perp-Trades falsch.

## 5. Regulierung in der EU [F]

- **MiCA** (EU-Verordnung über Märkte für Kryptowerte) gilt vollständig seit 30.12.2024. Anbieter von Krypto-Dienstleistungen brauchen eine Zulassung als CASP.
- Übergangsfristen: EU-weit höchstens bis 01.07.2026; Deutschland hat die Frist kürzer gesetzt (Ende 31.12.2025 laut Sekundärquelle). Seitdem müssen Anbieter, die Kunden in Deutschland bedienen, zugelassen sein.
- Krypto-Derivate (Perps, Futures) sind in der EU in der Regel Finanzinstrumente nach MiFID II, nicht MiCA. Viele große Perp-Börsen sitzen außerhalb der EU. Ob ein Anbieter legal tätig sein darf, klärt das BaFin- oder ESMA-Register, nicht die Werbung. Einschätzung.

## 6. Krypto-spezifische Fehlerbilder [F]

- **Hebel auf Volatilität**: Hoher Hebel auf ein ohnehin stark schwankendes Instrument führt zu Liquidationen durch normales Rauschen.
- **Funding übersehen**: Lange gehaltene Perps verlieren über Funding, obwohl der Kurs passt.
- **Nachttrading**: 24/7 verleitet zu Trades zu Zeiten, in denen man müde ist. In der Auswertung nach Uhrzeit sichtbar.
- **Kleine Coins mit dünner Liquidität**: Slippage frisst den Vorteil.

## Quellen

- Wikipedia (2026): [BitMEX](https://en.wikipedia.org/wiki/BitMEX). Sekundärquelle, deckt sich mit Fachblogs.
- Ledger Academy (o. J.): [Perpetual Futures: From Shiller's Idea to DeFi](https://www.ledger.com/academy/series/n3xt/academy-research-perpetual-futures-from-shiller-to-defi).
- BaFin (2019): [Allgemeinverfügung Differenzgeschäfte](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Aufsichtsrecht/Verfuegung/vf_190801_allgvfg_Differenzgeschaefte.html).
- cryptotant.de (2026): [MiCA-Verordnung 2026](https://cryptotant.de/mica-verordnung/), Stand 06.07.2026. Sekundärquelle, Gesetzestext nicht abgerufen.
