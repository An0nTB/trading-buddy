# Risiko und Positionsgröße

Die Prozentwerte in diesem Kapitel sind verbreitete Praxisregeln, keine Empfehlung für ein bestimmtes Konto.

## 1. Der Kern in drei Sätzen [G]

1. Vor dem Einstieg steht fest, wo der Trade falsch ist: der Stop.
2. Aus dem Abstand zum Stop folgt die Positionsgröße, nicht umgekehrt.
3. Das Risiko je Trade ist ein fester, kleiner Teil des Kontos.

## 2. Positionsgröße berechnen [G]

```
Risiko in €      = Kontostand × Risiko-% je Trade
Risiko je Stück  = |Einstieg − Stop| × Punktwert (bzw. × Bezugsverhältnis)
Positionsgröße   = Risiko in € ÷ Risiko je Stück
```

Beispiel (ausgedacht, ohne Kosten): Konto 10.000 €, Risiko 1 % = 100 €. DAX-CFD mit 1 € je Punkt, Stop 40 Punkte entfernt. Positionsgröße = 100 ÷ 40 = 2,5 Kontrakte.

Mit Kosten: Spread und Gebühr zum Risiko addieren, sonst ist der echte Verlust größer als geplant.

## 3. Warum kleine Prozente [G]

Zehn Verluste in Folge (eigene Rechnung, Zinseszins):

| Risiko je Trade | Kontoverlust nach 10 Verlusten |
|---|---|
| 1 % | −9,6 % |
| 2 % | −18,3 % |
| 5 % | −40,1 % |
| 10 % | −65,1 % |

Der Weg zurück wird schnell steil. Nötiger Gewinn = 1 ÷ (1 − Drawdown) − 1:

| Drawdown | Nötiger Gewinn bis zum alten Stand |
|---|---|
| −10 % | +11,1 % |
| −20 % | +25,0 % |
| −50 % | +100 % |
| −75 % | +300 % |

Wie lang Verlustserien werden (eigene Simulation, 20.000 Läufe je 100 Trades, unabhängige Trades):

| Trefferquote | Ø längste Verlustserie | Läufe mit Serie ≥ 8 |
|---|---|---|
| 50 % | rund 6 | rund 17 % |
| 40 % | rund 8 | rund 49 % |

Acht Verluste am Stück sind bei 40 % Trefferquote normal und kein Beweis, dass die Strategie kaputt ist. Das Risiko je Trade muss solche Serien aushalten.

Verbreitete Praxisregel: 0,5 bis 2 % Risiko je Trade, Anfänger eher am unteren Rand. Einschätzung, nicht wissenschaftlich hergeleitet.

## 4. Grenzen über den einzelnen Trade hinaus [F]

- **Tagesverlust-Grenze**: Nach zum Beispiel 3 R Verlust an einem Tag wird nicht mehr gehandelt. Schützt vor Revanche-Trades.
- **Wochen- und Monatsgrenze**: gleiche Idee auf längerer Ebene.
- **Gesamtrisiko offener Positionen**: Summe aller offenen Risiken, zum Beispiel höchstens 5 % des Kontos.
- **Korrelation**: DAX, Nasdaq und Dow gleichzeitig long ist weitgehend **eine** Wette auf steigende Aktien. Ebenso EUR/USD long und GBP/USD long, beide gegen den Dollar. Offene Positionen deshalb nach Basiswert-Gruppe zusammen betrachten.
- **Ereignisrisiko**: Über Zinsentscheid, Zahlen oder Wochenende gehaltene Positionen tragen Gap-Risiko, das der Stop nicht begrenzt.

## 5. Hebel richtig einordnen [G]

- Hebel bestimmt, **wie viel Kapital gebunden** ist. Das Risiko bestimmt der Stop-Abstand mal Größe.
- Gefährlich wird Hebel, wenn er zu großen Positionen verleitet oder die Margin so knapp ist, dass der Broker vor dem Stop zwangsschließt.
- Kennzahl: **effektiver Hebel** = Nominalwert aller offenen Positionen ÷ Kontostand.

## 6. Ausstiege planen [F]

- **Stop-Arten**: fester Preis (Chart-Marke), volatilitätsbasiert (zum Beispiel 1,5 × ATR), Zeit-Stop (nach X Stunden ohne Bewegung raus).
- **Ziele**: feste Marke, Vielfaches des Risikos (zum Beispiel 2 R), Trailing Stop, Teilverkauf.
- **Regel vorher, nicht während**: Änderungen am Plan während des Trades als eigene Information festhalten (Plan geändert, warum).

## 7. Kelly und Risiko des Ruins [P]

- **Kelly-Formel** (Kelly 1956): Anteil f* = p − (1 − p) ÷ b, mit p = Trefferquote und b = Ø Gewinn ÷ Ø Verlust. Beispiel: p = 50 %, b = 1,5 ergibt f* ≈ 16,7 % des Kontos je Trade.
- Kelly setzt voraus, dass p und b **bekannt und stabil** sind. Im Trading sind sie geschätzt und schwanken. Volles Kelly führt dann zu sehr großen Schwankungen. Praxis: wenn überhaupt, ein kleiner Bruchteil davon. Einschätzung, in der Fachliteratur verbreitet.
- **Risiko des Ruins**: Wahrscheinlichkeit, eine festgelegte Verlustschwelle zu erreichen. Hängt ab von Erwartungswert, Streuung und Risiko je Trade. Schätzen lässt es sich per Simulation über die eigenen R-Werte, nicht mit einer Formel.

## 8. Profi-Werkzeuge [P]

- **Monte-Carlo-Simulation**: Eigene Trade-Ergebnisse tausendfach neu mischen und die Verteilung von Drawdown und Endstand ansehen. Zeigt, wie viel Glück im bisherigen Verlauf steckt.
- **Volatilitäts-Positionsgröße**: Größe so wählen, dass jede Position ähnlich viel ATR-Risiko trägt.
- **Risikobudget je Strategie**: Jede Strategie bekommt einen Teil des Gesamtrisikos und pausiert an ihrer Drawdown-Grenze.

## Quellen

- Kelly, J. L. (1956): A New Interpretation of Information Rate. Bell System Technical Journal 35(4), 917–926.
- Tharp, V. K. (2008): Van Tharp's Definitive Guide to Position Sizing. IITM.
- Eigene Rechnungen und Simulation, Python 3, 01.10.2026. Verlusttabellen: 1 − (1 − r)^10; Bandbreiten und Serien per Monte-Carlo.
