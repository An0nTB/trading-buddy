# Kosten und Steuern in Deutschland

**Kein Steuerrat.** Einordnung, damit die richtigen Daten gesammelt werden. Für die Steuererklärung gelten Steuerberater und Jahressteuerbescheinigung.

## 1. Kostenarten im Trading [G]

| Kostenart | Wo sie auftaucht | Sichtbar im Export? |
|---|---|---|
| Ordergebühr, Kommission | Aktien, ETFs, Futures, teils CFDs | Meist ja |
| Fremdkosten, Börsenentgelt | Je Handelsplatz | Teils, oft in der Ordergebühr enthalten |
| Spread | Alle, besonders CFDs, Zertifikate, Krypto | **Nein**, steckt im Preis |
| Swap, Overnight-Finanzierung | CFDs, Forex | Ja (bei MetaTrader Spalte R/O) |
| Finanzierungskosten im Produkt | Open-End-Turbos | **Nein**, über Anpassung des Finanzierungslevels |
| Funding | Krypto-Perps | Ja, als eigene Buchung |
| Maker/Taker-Gebühr | Krypto-Börsen, Futures | Ja, oft in Coin |
| Währungsumrechnung | Handel in Fremdwährung | Teils als Aufschlag im Kurs |
| Depot, Verwahrung, Inaktivität | Je Broker | Selten im Trade-Export |
| Produktkosten (TER) | ETFs, ETPs | Nein, im Kurs |

Die App fragt je Broker, wie diese Kosten berechnet werden, bevor sie rechnet. Versteckte Kosten (Spread, Finanzierung im Turbo) kann sie nur schätzen; die Schätzung ist als solche markiert.

Kennzahl: **Kostenquote** = Summe Kosten ÷ Summe Brutto-Gewinne. Bei kurzfristigem Handel oft der Unterschied zwischen Plus und Minus (Einschätzung, am eigenen Datensatz messbar).

## 2. Kapitalerträge: Grundzüge [G]

| Punkt | Stand | Beleg |
|---|---|---|
| Abgeltungsteuer | 25 % auf Kapitalerträge, plus 5,5 % Solidaritätszuschlag darauf, gegebenenfalls Kirchensteuer | § 32d EStG |
| Sparer-Pauschbetrag | 1.000 € je Person, 2.000 € bei Zusammenveranlagung, seit 2023 | § 20 Abs. 9 EStG |
| Aktienverluste | Nur mit Gewinnen aus Aktienverkäufen verrechenbar (eigener Verlusttopf) | § 20 Abs. 6 EStG; mit dem JStG 2024 **nicht** abgeschafft |
| Termingeschäfte (CFDs, Optionen, Futures) | Die frühere Grenze von 20.000 € Verlustverrechnung pro Jahr wurde mit dem Jahressteuergesetz 2024 gestrichen, anwendbar in allen offenen Fällen | CMS 2024, Ecovis 2024 |
| Aktienfonds (ETFs) | Teilfreistellung 30 % bei Aktienfonds; jährliche Vorabpauschale | InvStG § 20, § 18 |

## 3. Inländischer oder ausländischer Broker [F]

- Inländische Banken und Broker führen die Abgeltungsteuer in der Regel selbst ab und stellen eine Jahressteuerbescheinigung aus.
- Bei ausländischen Brokern und vielen Krypto-Börsen müssen Erträge selbst in der Steuererklärung (Anlage KAP bzw. Anlage SO) angegeben werden. Was der eigene Broker tut, je Broker prüfen, nicht raten.
- Deshalb gibt es je Konto das Feld „Broker führt Steuer ab: ja, nein, unbekannt“.

## 4. Krypto (Spot, privat gehalten) [G/F]

| Punkt | Stand | Beleg |
|---|---|---|
| Einordnung | Private Veräußerungsgeschäfte | § 23 Abs. 1 Nr. 2 EStG |
| Haltefrist | Verkauf nach **mehr als einem Jahr** steuerfrei; innerhalb eines Jahres steuerpflichtig | § 23 EStG; BMF-Schreiben 06.03.2025 |
| Tausch Krypto gegen Krypto | Gilt als Veräußerung, die Frist für die neue Coin beginnt neu | BMF-Schreiben 06.03.2025 (über Hortmann Law) |
| Freigrenze | Gewinne unter 1.000 € im Jahr steuerfrei; ab 1.000 € ist **alles** steuerpflichtig (Freigrenze, kein Freibetrag); seit 2024, vorher 600 € | § 23 Abs. 3 EStG |
| Verbrauchsfolge | FIFO je Wallet | BMF-Schreiben 06.03.2025 |
| Staking | Keine Verlängerung der Haltefrist auf zehn Jahre | BMF-Schreiben (über Hortmann Law) |
| Steuersatz | Persönlicher Einkommensteuersatz, nicht Abgeltungsteuer | § 22 Nr. 2, § 23 EStG |
| Krypto-Derivate (Perps, CFDs) | Anders zu behandeln als Spot (Einschätzung: Kapitalerträge, Termingeschäfte) | Nicht abschließend geprüft |

Für Krypto-Spot braucht es Anschaffungsdatum und -kosten je Bestand und Wallet (FIFO), sonst ist die Haltefrist nicht bestimmbar.

## 5. Was die App aus Steuersicht leisten kann und was nicht [F]

- **Kann**: Kosten vollständig sammeln, Ergebnis nach Verlusttöpfen gruppieren (Aktien, Termingeschäfte, Sonstiges, Krypto), Haltefristen anzeigen.
- **Kann nicht und soll nicht**: verbindlich Steuer berechnen. Jede Steuerzahl in der App trägt den Hinweis „Orientierung, keine Steuerberechnung“.

## Quellen

- CMS (2024): [Verlustverrechnungsbeschränkung bei Termingeschäften: Gesetzgeber schafft Vorschrift ab](https://cms.law/de/deu/legal-updates/verlustverrechnungsbeschraenkung-bei-termingeschaeften-gesetzgeber-schafft-vorschrift-ab). Legal Update 22.10.2024.
- Ecovis (2024): [Verlustverrechnung bei Termingeschäften](https://ecovis-kso.com/blog/verlustverrechnung-termingeschaefte-2024/).
- Hortmann Law (2025): [Krypto-Steuern nach § 23 EStG](https://www.hortmannlaw.com/articles/einkommensteuer-ss-23-estg-krypto-gewinne-krypto-verluste-haltefrist-freigrenze-staking-lending-dokumentationspflichten-verluste-durch-betrug-hacks). BMF-Schreiben selbst nicht abgerufen.
- Blockpit (2026): [Krypto Freibetrag und Freigrenze](https://www.blockpit.io/de-de/steuer-guides/krypto-freibetrag-freigrenze).
- Einkommensteuergesetz (EStG), Investmentsteuergesetz (InvStG), jeweils gültige Fassung; Paragrafen nicht im Gesetzestext nachgeschlagen.
