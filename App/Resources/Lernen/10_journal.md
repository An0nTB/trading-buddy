# Journal und Review

Praxiswissen für die Hauptfunktion der App. Als Einschätzung gekennzeichnet, wo es keine Studie gibt.

## 1. Warum ein Journal [G]

- Der Broker-Export zeigt, **was** passiert ist. Das Journal zeigt, **warum**. Erst beides zusammen erlaubt Verbesserung.
- Ohne Aufzeichnung erinnert man sich verzerrt (Rückschaufehler, Kapitel 9).
- Je länger und gleichmäßiger der Datensatz, desto belastbarer die Aussagen (Stichprobengröße, Kapitel 8, Abschnitt 7).

## 2. Felder: was automatisch kommt, was man ergänzt [G]

| Herkunft | Feld | Pflicht für |
|---|---|---|
| Import | Instrument, Richtung, Größe, Einstieg, Ausstieg, Zeitstempel, Kosten, S/L, T/P (falls vorhanden) | Alle Grundkennzahlen |
| Import oder Journal | **Stop beim Einstieg** (ursprünglich) | R-Multiple, Regelbruch-Erkennung |
| Journal | Setup-Etikett | Auswertung je Setup |
| Journal | Geplantes Ziel | Ausstiegs-Disziplin |
| Journal | Grund für Einstieg (ein Satz) | Auswertung, Lernen |
| Journal | Grund für Ausstieg: Stop, Ziel, Zeit, manuell, Knock-out, Liquidation | Fehlermuster |
| Journal | Regeltreue ja/nein | Prozess statt Ergebnis bewerten |
| Journal | Zustand vor dem Trade (1 bis 5), optional Emotion-Stichwort | Psychologische Muster |
| Journal | Marktumfeld (Trend, Seitwärts, hohe Volatilität) | Setup im Kontext |
| Journal | Screenshot Chart vor und nach | Visuelle Review |
| Automatisch berechnet | Haltedauer, R, Trade-Nr. am Tag, vorheriges Ergebnis, Termin in Haltezeit | Dimensionen der Auswertung |

Einschätzung: Je weniger Pflichtfelder, desto eher wird das Journal geführt. Pflicht sind nur Setup, Stop beim Einstieg und Regeltreue; alles andere ist optional.

## 3. Setup-Katalog (Playbook) [F]

- Jedes Setup bekommt eine Karte: Name, Bedingungen für den Einstieg, Stop-Regel, Ziel-Regel, Marktumfeld, Beispielbilder.
- Neue Setups erst nach einer Testphase in den Katalog übernehmen.
- Kennzahlen je Setup: Anzahl, Erwartungswert in R, Trefferquote, Payoff, Drawdown.
- Setups mit negativem Erwartungswert nach ausreichender Stichprobe: pausieren oder ändern. Entscheidung mit Datum festhalten.

## 4. Review-Rhythmus [G/F]

| Rhythmus | Dauer (Einschätzung) | Inhalt |
|---|---|---|
| Nach jedem Trade | 1 bis 2 Min. | Felder ausfüllen, Screenshot |
| Täglich | 10 Min. | Regeltreue des Tages, ein Lernpunkt, Grenzen eingehalten? |
| Wöchentlich (Import) | 30 bis 60 Min. | Broker-Export laden, Kennzahlen, Fehlermuster, beste und schlechteste Trades ansehen, ein Ziel für die nächste Woche |
| Monatlich | 1 bis 2 Std. | Trends über Wochen, Setups bewerten, Regeln anpassen, Experimente starten oder beenden |
| Quartalsweise | 2 bis 3 Std. | Strategie insgesamt, Stilwahl, Lernplan |

## 5. Fragen für die Wochen- und Monatsauswertung [F]

Diese Fragen beantwortet die Auswertung strukturiert:

1. Wie lagen Netto-Ergebnis, Erwartungswert in R, Profitfaktor und Drawdown, im Vergleich zum Vorzeitraum?
2. Welche Setups trugen, welche kosteten? Mit Stichprobengröße.
3. Welche Fehlermuster aus Kapitel 9 traten auf, wie oft, was kosteten sie in R?
4. Wie hoch war der Kostenanteil? Hat ein Kostenblock (Swap, Spread) das Ergebnis gedreht?
5. Was wäre das Ergebnis ohne die Regelbrüche gewesen? (Trades mit Regeltreue = nein herausrechnen)
6. Wurde das Ziel aus dem letzten Review erreicht?
7. **Ein** konkretes Ziel für den nächsten Zeitraum, messbar.

Punkt 5 ist nach Praxiserfahrung (Einschätzung) die wirksamste Einzelzahl, weil sie zeigt, was Disziplin wert ist.

## 6. Experimente im Journal [F/P]

Jedes Experiment mit Hypothese, Kill-Kriterium und Termin:

```
Experiment:      Kein Trade nach zwei Verlusten am Tag
Hypothese:       Erwartungswert steigt um mindestens 0,1 R je Trade
Zeitraum:        4 Wochen, mindestens 40 Trades
Kill-Kriterium:  Erwartungswert sinkt oder Regel wird mehr als 3-mal gebrochen
Entscheidung am: <Datum>
```

Der Zeitraum vorher und nachher lässt sich dann direkt vergleichen.

## 7. Häufige Journal-Fehler [G]

- Nur Verlierer aufschreiben (oder nur Gewinner).
- Felder nachträglich ausfüllen und dabei „schönen“.
- Zu viele Etiketten, die keiner auswertet.
- Kein fester Termin für die Auswertung, daher keine Konsequenzen.
- Kennzahlen bei zu kleiner Stichprobe überdeuten.

## Quellen

- Steenbarger, B. (2009): The Daily Trading Coach. Wiley.
- Steenbarger, B. (2003): The Psychology of Trading. Wiley.
- Dass ein Journal die Ergebnisse verbessert, ist nicht durch eine belastbare Studie belegt; Einschätzung aus der Praxisliteratur.
