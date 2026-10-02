# Hebelprodukte und Derivate

Ziel: Funktionsweise verstehen und richtig auswerten. Die Aufsichtszahlen stehen als nüchterner Rahmen hier, nicht als Warnung; was zählt, ist der eigene Datensatz über die Zeit.

## 1. Hebel in einem Satz [G]

Hebel heißt: Mit wenig eigenem Geld bewegt man eine große Position. Gewinne und Verluste wachsen im selben Verhältnis. Hebel selbst ist nicht das Risiko; das Risiko ist **Positionsgröße × Abstand zum Ausstieg** (Kapitel 7).

## 2. Was die Aufsicht über Privatanleger misst [G]

| Produkt | Befund | Quelle |
|---|---|---|
| CFDs | 74 bis 89 % der Privatkonten verlieren Geld; Durchschnittsverlust je Kunde 1.600 bis 29.000 € | ESMA, 27.03.2018 |
| Turbo- und Knock-out-Zertifikate in Deutschland | 74,2 % der rund 543.000 Privatanleger mit Verlust (2019 bis 2023); Ø Verlust 6.358 €; zusammen über 3,4 Mrd. € | BaFin-Studie, 21.05.2025 |
| Turbos, Häufigkeit | Über 1.000 Transaktionen: 91 % mit Verlust; 1 bis 10 Transaktionen: 70 % | BaFin-Studie, 21.05.2025 |
| Turbos, Haltedauer | Rund 70 % weniger als 24 Stunden gehalten | BaFin-Studie, 21.05.2025 |

## 3. CFD (Contract for Difference) [G]

- Vertrag mit dem Broker über die Kursdifferenz. Der Basiswert gehört einem nicht. Gegenüber ist meist der Broker selbst.
- Regeln für Privatkunden in Deutschland (BaFin-Allgemeinverfügung vom 23.07.2019, gilt seit 01.08.2019, übernimmt die ESMA-Maßnahme von 2018):
- Mindest-Sicherheit (Margin) beim Eröffnen: 3,33 % Haupt-Währungspaare (Hebel 30:1), 5 % Hauptindizes, Gold und weitere (20:1), 10 % andere Rohstoffe und Indizes (10:1), 20 % Einzelaktien (5:1), 50 % Kryptowerte (2:1).
- Zwangsschließung, wenn das Konto unter 50 % der nötigen Margin fällt. Kein Nachschuss: Verlust höchstens das Geld auf dem CFD-Konto. Keine Boni oder Gebührenrabatte als Lockmittel.
- Kosten: Spread, gegebenenfalls Kommission, **Overnight-Finanzierung** (Swap) je Nacht, am Wochenende oft dreifach (Brokerregel, je Broker prüfen). Im MetaTrader-Auszug stehen diese Kosten in den Spalten Commission und R/O; beides gehört ins Netto-Ergebnis.

## 4. Knock-out-Zertifikate (Turbos, Mini-Futures) [G/F]

- Zertifikat einer Bank, das einen Basiswert mit Hebel abbildet. Es gibt eine **Knock-out-Schwelle**: Wird sie berührt, verfällt das Papier fast oder ganz wertlos.
- **Open-End-Turbos** haben ein Finanzierungslevel, das täglich angepasst wird; darüber laufen Finanzierungskosten, ohne dass sie als Gebühr erscheinen.
- Hebel ≈ Kurs Basiswert × Bezugsverhältnis ÷ Preis des Zertifikats. Je näher die Schwelle, desto höher der Hebel und desto wahrscheinlicher der Knock-out.
- Kein Stop schützt vor einem Gap über die Schwelle hinweg. Emittentenrisiko: Schuldverschreibung der Bank.
- **BaFin-Produktintervention** (Beschluss 15.10.2025, gilt seit 16.06.2026): standardisierte Risikowarnung, Kenntnistest durch Broker und Banken (alle sechs Monate wiederholbar), keine Lockangebote wie Gebührenrabatte.

## 5. Faktor-Zertifikate [F]

- Konstanter Hebel, der **täglich zurückgesetzt** wird. Dadurch ist das Ergebnis pfadabhängig.
- Rechenbeispiel (eigene Rechnung, ohne Kosten): Basiswert 100 → 110 → 99, also −1 %. Faktor 5 Long: +50 % → 150, dann −50 % → 75, also −25 %. Seitwärts schwankende Märkte zehren den Wert auf.
- Für Trends über wenige Tage gedacht, nicht zum langen Halten. Einschätzung.

## 6. Optionsscheine [F]

- Recht (keine Pflicht), einen Basiswert zu einem **Basispreis** bis zu einem Termin zu kaufen (Call) oder zu verkaufen (Put). Ausgegeben von Banken.
- Preis = innerer Wert + **Zeitwert**. Der Zeitwert schmilzt zum Laufzeitende hin.
- Der Preis hängt stark von der **impliziten Volatilität** ab: Fällt die erwartete Schwankung (zum Beispiel nach Quartalszahlen), kann ein Schein trotz richtiger Richtung verlieren.
- Die Bank stellt die Kurse selbst und kann die Volatilität im Preis verändern. Einschätzung, in der Fachliteratur verbreitet.

## 7. Futures [F/P]

- Börsengehandelter, standardisierter Vertrag über Kauf oder Verkauf zu einem festen Termin. Gegenüber ist die Clearingstelle der Börse.
- Kontraktgrößen an der Eurex: DAX-Future 25 € je Indexpunkt, Mini-DAX 5 €, Micro-DAX 1 € (Eurex 2026). Bei 100 Punkten Bewegung also 2.500 €, 500 € oder 100 € je Kontrakt.
- **Margin** wird täglich abgerechnet (Mark-to-Market). Grundsätzlich ist ein Nachschuss über das eingezahlte Geld hinaus möglich. Die BaFin untersagt seit 01.01.2023 den Vertrieb spekulativer Futures **mit** Nachschusspflicht an Privatkunden; erlaubt bleibt der Handel, wenn der Broker den Nachschuss vertraglich ausschließt. Wie der eigene Broker das umsetzt, dort nachfragen.
- Verfall und **Rollover** auf den nächsten Kontrakt. In der Auswertung als eigener Vorgang führen, nicht als neuer Trade.
- Vorteil gegenüber CFD aus Profi-Sicht: transparentes Orderbuch, zentrale Clearingstelle. Einschätzung.

## 8. Optionen an der Börse und die Griechen [P]

- Wie Optionsscheine, aber an der Börse (Eurex, US-Optionsbörsen), standardisiert, mit Kauf **und** Verkauf.
- **Stillhalter** (Verkäufer) kassieren die Prämie und tragen das Risiko. Beim ungedeckten Verkauf eines Calls ist der Verlust theoretisch unbegrenzt.
- Typische Strategien: gedeckter Call, Cash-Secured Put, Spreads (begrenztes Risiko), Straddle (Wette auf Bewegung). Für die Auswertung zählt das Risiko der **gesamten** Kombination, nicht der einzelnen Beine.
- Die Griechen: Delta (Preisänderung je Bewegung des Basiswerts), Gamma (Änderung des Deltas), Theta (Zeitwertverlust je Tag), Vega (Empfindlichkeit für Volatilität), Omega (effektiver Hebel).

## 9. Was die Auswertung bei Derivaten zusätzlich braucht [F]

| Feld | Warum |
|---|---|
| Produkttyp (CFD, KO, Faktor, OS, Future, Option) | Kosten und Risiko verschieden |
| Basiswert vereinheitlicht | „de40.c“, „DAX-Turbo XY“ und „FDAX“ beziehen sich alle auf den DAX |
| Punktwert bzw. Bezugsverhältnis | Ohne ihn keine Positionsgröße und kein R |
| Finanzierung, Swap, Rollover | Sonst sieht ein langes Halten zu gut aus |
| Knock-out ja/nein | Eigener Ausstiegsgrund, getrennt von Stop und Ziel |
| Emittent | Konzentration auf eine Bank sichtbar machen |

## Quellen

- ESMA (2018): [Pressemitteilung ESMA71-98-128 zur Produktintervention](https://www.esma.europa.eu/sites/default/files/library/esma71-98-128_press_release_product_intervention.pdf), 27.03.2018.
- BaFin (2019): [Allgemeinverfügung bezüglich Differenzgeschäfte](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Aufsichtsrecht/Verfuegung/vf_190801_allgvfg_Differenzgeschaefte.html).
- BaFin (2025): [Studie Vertrieb von Turbo-Zertifikaten](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Fachartikel/2025/Studie_250521_Turbo_Zertifikate.html), 21.05.2025.
- BaFin (2025): [BaFin interveniert bei Turbo-Zertifikaten](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Pressemitteilung/2025/pm_2025_10_15_Turbo_Zertifikat_Knock_Out.html), 15.10.2025.
- BaFin (2022): [Anhörung Futures mit Nachschusspflichten](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Aufsichtsrecht/Verfuegung/vf_220203_anhoerung_allgvfg_Futures.html); finanzmarktwelt.de (2022): [BaFin schützt Kleinanleger beim Future-Handel](https://finanzmarktwelt.de/bafin-kleinanleger-future-handel-meldung-247654/). Sekundärquelle.
- Eurex (2026): [Micro-DAX Futures](https://www.eurex.com/ex-en/markets/idx/dax/Micro-DAX-Futures-2615490).
