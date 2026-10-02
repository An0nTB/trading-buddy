# Märkte und Instrumente

Einordnung und Begriffe, keine Empfehlung für ein Produkt.

## 1. Was ein Markt ist [G]

- Ein Markt bringt Käufer und Verkäufer zusammen. Der Preis entsteht dort, wo beide handeln.
- **Geldkurs (Bid)**: zu diesem Preis kauft jemand ab. **Briefkurs (Ask)**: zu diesem Preis verkauft jemand.
- **Spread** = Ask minus Bid. Jeder Trade startet mit dem Spread im Minus. Für die Auswertung zählt der Spread als Kosten, auch wenn er nirgends als Gebühr auftaucht.
- **Liquidität**: wie viel sich handeln lässt, ohne den Preis zu bewegen. Wenig Liquidität heißt breite Spreads, Sprünge und schlechtere Ausführung.
- **Long** = auf steigende Kurse setzen (kaufen). **Short** = auf fallende Kurse setzen (leer verkaufen oder ein Short-Produkt kaufen).

## 2. Anlageklassen im Überblick [G]

| Klasse | Was gehandelt wird | Typische Wege in Deutschland | Besonderheit für die Auswertung |
|---|---|---|---|
| Aktien | Anteile an Unternehmen | Börse oder außerbörslich (Neobroker) | Dividenden, Splits, Nachrichten zum Unternehmen |
| ETFs | Fonds, der einen Index nachbildet | Börse, Sparplan | Langfristig, wenig Trades, Kosten über TER |
| Anleihen | Schuldtitel mit Zins | Börse | Für Trading selten, wichtig als Zinssignal |
| Indizes | Korb von Aktien (DAX 40, S&P 500, Nasdaq 100) | Nur über ETF, Future, CFD, Zertifikat | Symbolnamen je Broker verschieden (de40.c = DAX) |
| Devisen (Forex) | Währungspaare (EUR/USD) | CFD oder Future | 24 h an Werktagen, Pips, Swap über Nacht |
| Rohstoffe | Gold, Öl, Gas | CFD, Future, ETC | Rollover bei Futures, Lagerkosten im Preis |
| Krypto | Bitcoin, Ether, weitere | Krypto-Börse, Neobroker, CFD | 24/7, Gebühren oft in der Kryptowährung (Kapitel 3) |
| Derivate | Produkte, deren Wert von einem Basiswert abhängt | Optionsscheine, Knock-outs, CFDs, Futures, Optionen | Hebel, Finanzierungskosten, Laufzeit (Kapitel 2) |

Größenordnung: Der weltweite Devisenhandel lag im April 2025 bei 9,6 Billionen US-Dollar pro Tag (BIS 2025). Der Devisenmarkt ist damit der liquideste Markt, für Privatleute aber fast nur über Hebelprodukte erreichbar.

## 3. Direktes Eigentum oder Wette auf den Preis [G]

Diese Unterscheidung ist die wichtigste für Anfänger.

- **Direktes Eigentum**: Aktie, ETF-Anteil, Bitcoin auf eigener Wallet. Der Wert gehört dem Käufer. Verlust höchstens der Einsatz. Keine Laufzeit, keine Finanzierungskosten.
- **Wette auf den Preis** (Derivat): CFD, Knock-out, Optionsschein, Future. Es gibt nur einen Vertrag, dazu Hebel, Laufzeiten oder laufende Kosten, bei Zertifikaten das Risiko, dass der Herausgeber ausfällt.
- **ETFs** sind in Deutschland Sondervermögen: Das Geld im Fonds ist vom Vermögen der Fondsgesellschaft getrennt. **Zertifikate** (Knock-outs, Faktor, Optionsscheine) sind Schuldverschreibungen des Emittenten. Fällt der Emittent aus, kann der Wert verloren sein (Emittentenrisiko).

## 4. Börse und außerbörslicher Handel [F]

- **Börse** (zum Beispiel Xetra, NYSE, Nasdaq): Orderbuch, Regeln, Aufsicht durch die Handelsüberwachung.
- **Außerbörslich (OTC)** und **Market Maker**: Ein Händler stellt Kurse und ist das Gegenüber. Üblich bei CFDs, vielen Zertifikaten und bei Neobrokern über bestimmte Handelsplätze.
- **Xetra-Zeiten**: Hauptsitzung 9:00 bis 17:30 Uhr mit Schlussauktion um 17:30. Seit 01.12.2025 können Privatanleger Aktien, ETFs und ETPs zusätzlich von 8:00 bis 22:00 Uhr handeln. Offizielle Preise entstehen weiter in den Auktionen.
- **Payment for Order Flow** (Rückvergütung vom Handelsplatz an den Broker) ist in der EU nach Art. 39a MiFIR verboten; die deutsche Ausnahme endete am 30.06.2026. Gebührenmodelle der Neobroker können sich dadurch 2026 ändern. Deshalb fragt die App das Kostenmodell je Broker ab.

## 5. Zeit und Handelsfenster [G]

- Jede Börse hat Öffnungszeiten, Auktionen und Feiertage. Krypto handelt rund um die Uhr. Devisen von Sonntagabend bis Freitagabend (mitteleuropäische Zeit).
- Die ersten und letzten Minuten einer Sitzung sind meist am lebhaftesten (Volumen, Spreads). Einschätzung aus der Praxis, nicht mit Studie belegt.
- **Lücken (Gaps)**: Zwischen Schluss und nächster Eröffnung kann der Kurs springen. Ein Stop schützt dann nicht zum gesetzten Preis. Wichtig für Haltedauer über Nacht und übers Wochenende.

## 6. Begriffe für die Auswertung [G]

| Begriff | Bedeutung |
|---|---|
| Basiswert | Das, worauf sich ein Derivat bezieht (DAX, Gold, Apple) |
| Punkt, Pip, Tick | Kleinste übliche Preisbewegung; Wert je Punkt hängt vom Produkt ab |
| Lot | Handelsgröße bei Forex und CFD; 1 Standard-Lot Forex = 100.000 Einheiten der Basiswährung (je Broker prüfen) |
| Nominalwert | Wert der Position ohne Hebel (Menge × Kurs × Punktwert) |
| Margin | Sicherheitsleistung für eine Hebelposition |
| Swap, Rollover, Finanzierung | Kosten oder Gutschrift für Halten über Nacht |
| Realisiert, unrealisiert | Geschlossene Trades zählen als realisiert, offene als schwebend (Floating P/L) |

## Quellen

- BIS (2025): [Global FX trading hits $9.6 trillion per day in April 2025](https://www.bis.org/media-releases/20250930-global-fx-trading-hits-96-trillion-day-april-2025-and-otc-interest-rate-derivatives-surge-79). Pressemitteilung 30.09.2025.
- Kagels, K. (2026): [Xetra Handelszeiten 2026](https://www.kagels-trading.de/xetra-handelszeiten/); broker-test.de (2025): [Längere Xetra-Handelszeiten seit dem 1. Dezember 2025](https://broker-test.de/trading-news/laengere-xetra-handelszeiten-seit-dem-1-dezember-2025/). Sekundärquellen, Deutsche Börse nicht abgerufen.
- paytechlaw (2026): [The PFOF ban comes into force](https://paytechlaw.com/en/the-pfof-ban-comes-into-force/). Fachportal, 24.07.2026.
- ETFs als Sondervermögen, Zertifikate als Schuldverschreibungen: fachlicher Standard (KAGB, Zertifikatebedingungen), nicht im Gesetzestext nachgeschlagen.
