# Kennzahlen

Diese Kennzahlen rechnet die App selbst, deterministisch und nachprüfbar. Henry ordnet sie nur ein.

## 1. Grundbegriffe [G]

- **Trade** = eine Position von Eröffnung bis vollständiger Schließung, Teilausführungen zusammengefasst.
- **Netto-Ergebnis** = Brutto-Ergebnis − Kommission − Swap, Finanzierung oder Funding − sonstige Gebühren. Alle Kennzahlen auf **netto** rechnen, brutto nur zum Vergleich.
- **Breakeven-Trades**: Vorher festlegen, ab welchem Betrag ein Trade als ±0 gilt (zum Beispiel |Ergebnis| < 0,1 R), sonst verzerren sie die Trefferquote.

## 2. Basiskennzahlen [G]

| Kennzahl | Formel | Lesart |
|---|---|---|
| Trefferquote | Gewinner ÷ alle Trades | Allein ohne Aussage |
| Ø Gewinn, Ø Verlust | Summe Gewinne ÷ Anzahl Gewinner; analog Verluste | Grundlage für alles Weitere |
| Payoff-Verhältnis | Ø Gewinn ÷ \|Ø Verlust\| | Über 1: Gewinner größer als Verlierer |
| Erwartungswert je Trade | Trefferquote × Ø Gewinn − Verlustquote × \|Ø Verlust\| | Über 0 nötig, sonst verliert der Ansatz auf Dauer |
| Profitfaktor | Summe Gewinne ÷ \|Summe Verluste\| | Über 1 profitabel; 1,0 bis 1,2 dünn (Einschätzung) |
| Breakeven-Trefferquote | 1 ÷ (1 + Payoff) | Bei Payoff 2 reichen 33,3 % |

Beispiel (ausgedacht): 40 % Treffer, Ø Gewinn 300 €, Ø Verlust 150 €. Erwartungswert = 0,4 × 300 − 0,6 × 150 = 30 € je Trade. Payoff 2, Breakeven-Trefferquote 33,3 %.

## 3. R-Multiple [G/F]

- **1 R** = geplantes Risiko beim Einstieg = |Einstieg − Stop| × Größe × Punktwert (+ erwartete Kosten).
- **R-Multiple** eines Trades = Netto-Ergebnis ÷ 1 R. Ein Trade mit 100 € Risiko und 250 € Gewinn = +2,5 R.
- **Erwartungswert in R** = Mittelwert aller R-Multiples. Vorteil: Trades mit verschiedenen Größen und Instrumenten werden vergleichbar.
- Bekannt gemacht durch Van K. Tharp (Tharp 1998/2007).
- **Voraussetzung**: Der Stop beim Einstieg muss bekannt sein. Fehlt er, gibt es kein R. Kein R zu schätzen ist besser als ein falsches.
- Diagnose-Werte: **Verluste größer als −1 R** zeigen Stop nicht eingehalten, Gap oder Slippage. **Viele Gewinne unter +1 R** bei geplantem Ziel 2 R zeigen zu frühe Gewinnmitnahme.

## 4. Kapitalkurve und Drawdown [G/F]

- **Kapitalkurve**: Kontostand nach jedem Trade (oder täglich).
- **Maximaler Drawdown**: größter Rückgang vom bisherigen Hoch zum folgenden Tief, in € und %.
- **Drawdown-Dauer**: Zeit vom Hoch bis zum neuen Hoch (Erholungszeit).
- **Längste Verlustserie** und **längste Gewinnserie**. Einordnung der Serienlänge: Kapitel 7, Abschnitt 3.

## 5. Kennzahlen zur Ausführung [F]

| Kennzahl | Bedeutung | Datenbedarf |
|---|---|---|
| MAE (Maximum Adverse Excursion) | Wie weit lief der Trade maximal gegen die Position | Kursverlauf während des Trades |
| MFE (Maximum Favorable Excursion) | Wie weit lief er maximal für die Position | Kursverlauf während des Trades |
| Ausstiegs-Effizienz | Realisierter Gewinn ÷ MFE | MFE |
| Haltedauer Gewinner gegen Verlierer | Mittelwert getrennt | Zeitstempel |
| Kostenquote | Summe Kosten ÷ Summe Brutto-Gewinne | Kostenfelder |
| Stornoquote | Stornierte Pending-Orders ÷ alle Orders | Order-Historie (MetaTrader hat sie) |
| Plan-Treue | Anteil Trades mit Stop, Ziel und Setup erfasst | Journal-Felder |

MAE und MFE gehen auf John Sweeney zurück (Sweeney 1997). Sie brauchen Kursdaten pro Minute oder Tick während des Trades.

## 6. Risikoadjustierte Kennzahlen [P]

| Kennzahl | Formel | Hinweis |
|---|---|---|
| Sharpe Ratio | (Ø Periodenrendite − risikofreier Zins) ÷ Standardabweichung | Sharpe 1966; sinnvoll auf Tages- oder Monatsrenditen, nicht auf einzelnen Trades |
| Sortino Ratio | wie Sharpe, aber nur Abwärts-Schwankung | Sortino, Price 1994 |
| Calmar bzw. Rendite/Drawdown | Jahresrendite ÷ max. Drawdown | Einfach, anschaulich |
| SQN (System Quality Number) | √n × Ø R ÷ Standardabweichung R | Tharp; n wird in seiner Fassung oft auf 100 gedeckelt (Sekundärquellen) |

Einschätzung: Für ein privates Journal mit wenigen Dutzend Trades im Monat reichen Erwartungswert in R, Profitfaktor und Drawdown. Sharpe und SQN erst ab größerer Datenmenge.

## 7. Wie viele Trades braucht eine Aussage [F]

Die Trefferquote schwankt zufällig. 95-%-Bandbreite bei echter Trefferquote 50 % (Normalnäherung, eigene Rechnung):

| Trades | Bandbreite ± Prozentpunkte |
|---|---|
| 20 | ± 21,9 |
| 30 | ± 17,9 |
| 50 | ± 13,9 |
| 100 | ± 9,8 |
| 200 | ± 6,9 |

Folgen:

- Unter 30 Trades in einer Gruppe (Setup, Wochentag, Instrument) zeigt die App **keine Schlussfolgerung**, nur die Zahl mit dem Hinweis „zu wenig Daten“.
- Vergleiche zwischen Gruppen (Montag gegen Freitag) erst ab ausreichender Menge je Gruppe, sonst findet man Zufallsmuster. Bei vielen Vergleichen gleichzeitig steigt die Chance auf Zufallsfunde.
- Jede Auswertung nennt die Stichprobengröße mit.

## 8. Aufschlüsselungen (Dimensionen) [G]

Jede Kennzahl lässt sich aufteilen nach: Instrument bzw. Basiswert, Produkttyp, Richtung (long, short), Setup, Wochentag, Uhrzeit (Stunde der Eröffnung), Haltedauer-Klasse (Stil), Marktumfeld, Positionsgröße, Ergebnis des vorherigen Trades (nach Gewinn, nach Verlust), Trade-Nummer am Tag, Stimmung vor dem Trade (Journal), Termine (über Nachricht gehalten ja/nein).

Die drei aufschlussreichsten für Fehlermuster (Einschätzung): **Ergebnis nach vorherigem Verlust**, **Trade-Nummer am Tag**, **Uhrzeit**.

## Quellen

- Tharp, V. K. (2007): Trade Your Way to Financial Freedom, 2. Aufl. McGraw-Hill. Standardliteratur, Original nicht eingesehen.
- Sweeney, J. (1997): Maximum Adverse Excursion. Wiley.
- Sharpe, W. F. (1966): Mutual Fund Performance. Journal of Business 39(1), 119–138.
- Sortino, F., Price, L. (1994): Performance Measurement in a Downside Risk Framework. Journal of Investing 3(3), 59–64.
- TradesViz (o. J.): [System Quality Number](https://www.tradesviz.com/glossary/system-quality-number/). Sekundärquelle für die SQN-Formel.
- Bandbreiten: 1,96 × √(0,25 ÷ n), eigene Rechnung, Python, 01.10.2026.
