# Psychologie und Fehlermuster

Ziel: Fehler nicht nur kennen, sondern im eigenen Datensatz erkennen.

## 1. Belegte Verzerrungen [G/F]

| Verzerrung | Was sie ist | Befund |
|---|---|---|
| Dispositionseffekt | Gewinner zu früh verkaufen, Verlierer zu lange halten | Odean 1998: Gewinne wurden rund 1,5-mal so häufig realisiert wie Verluste (10.000 Konten, 1987 bis 1993). Verkaufte Gewinner liefen im Folgejahr 2,35 % über dem Markt, gehaltene Verlierer 1,06 % darunter |
| Selbstüberschätzung | Eigene Fähigkeit und Informationen überschätzen | Barber, Odean 2001: Männer handelten 45 % mehr als Frauen; das kostete sie 2,65 Prozentpunkte Rendite pro Jahr, Frauen 1,72 (35.000 Haushalte, 1991 bis 1997) |
| Überhandeln | Zu viele Trades | Barber, Odean 2000: aktivste Haushalte 11,4 % pro Jahr gegen Markt 17,9 %. BaFin 2025: über 1.000 Turbo-Transaktionen 91 % Verlustquote |
| Verlustaversion | Verluste wiegen schwerer als gleich große Gewinne | Tversky, Kahneman 1992 schätzten den Faktor auf 2,25. Eine Meta-Analyse (2024, 17 Artikel) kommt bei riskanten Entscheidungen nur auf 1,31. Die Richtung ist belegt, die Stärke umstritten |
| Ankereffekt | Am Einstiegskurs oder einer runden Zahl festhalten | Kahneman, Tversky 1974 (allgemein, nicht trading-spezifisch) |
| Bestätigungsfehler | Nur Informationen suchen, die die eigene Position stützen | Allgemeine Psychologie; Einschätzung für Trading |
| Spielerfehlschluss | „Nach fünf Verlusten muss jetzt ein Gewinn kommen“ | Allgemeine Psychologie; bei unabhängigen Trades falsch |
| Rückschaufehler | „Das war doch klar“ nach dem Ereignis | Allgemeine Psychologie |

## 2. Typische Fehlermuster und ihr Datensignal [F]

Kernidee: Jede Verzerrung hinterlässt Spuren in den Daten. Die App prüft feste Regeln, Henry erklärt die Treffer und fragt nach.

| Muster | Datensignal | Benötigte Felder |
|---|---|---|
| Revanche-Trade | Neuer Trade innerhalb von zum Beispiel 15 Min. nach Verlust, Größe oder Risiko höher als Median | Zeitstempel, Größe, Ergebnis |
| Überhandeln | Trades pro Tag über persönlichem Median plus Schwelle; Erwartungswert ab Trade Nr. X am Tag schlechter | Zeitstempel, R |
| Stop nicht eingehalten | Verluste kleiner als −1,2 R (Schwelle wählbar) | Stop beim Einstieg, Ergebnis |
| Gewinne zu früh | Ø Gewinn in R deutlich unter geplantem Ziel; Haltedauer Gewinner kürzer als Verlierer | Ziel, Haltedauer, R |
| Verlierer laufen lassen | Haltedauer Verlierer deutlich länger als Gewinner (Dispositionseffekt) | Haltedauer |
| Verbilligen | Mehrere Käufe desselben Basiswerts in gleicher Richtung bei fallendem Kurs | Einstiege, Kurse |
| Ohne Stop | S/L = 0 oder leer | S/L-Feld |
| Schwankende Größe | Risiko je Trade stark gestreut (zum Beispiel Variationskoeffizient über 0,5) | 1 R je Trade |
| Größe nach Gewinnserie | Risiko steigt nach Gewinnen überproportional | R, Reihenfolge |
| FOMO-Einstieg | Einstieg nach starker Bewegung ohne Setup-Etikett, Ergebnis schwächer | Setup, Kursbewegung vor Einstieg |
| Müdigkeit, Randzeiten | Schlechtere Kennzahlen zu bestimmten Uhrzeiten | Uhrzeit |
| Nachrichten-Glücksspiel | Trades kurz vor Terminen mit hoher Streuung | Terminkalender |
| Ständiges Umplanen | Hohe Stornoquote bei Pending-Orders | Order-Historie |

Die Schwellen sind Vorschläge aus der Recherche und noch nicht am echten Datensatz kalibriert. Alle Muster brauchen eine Mindestzahl an Fällen (Kapitel 8, Abschnitt 7), bevor sie als Befund gelten.

## 3. Gegenmittel aus der Praxis [G/F]

Einschätzungen aus der Trading-Psychologie-Literatur (Douglas 2000, Steenbarger 2009), nicht als Studienergebnis:

- **Regeln vor dem Trade schriftlich** (Checkliste). Was vorher feststeht, muss im Moment nicht entschieden werden.
- **Feste Grenzen**: Tagesverlust, maximale Trades pro Tag, Pause nach zwei Verlusten in Folge.
- **Gleiches Risiko je Trade**: nimmt dem Einzeltrade das Gewicht.
- **Denken in Serien**: Ein Trade ist ein Ereignis aus einer Verteilung; bewertet wird die Serie von 20 bis 50 Trades.
- **Prozess bewerten, nicht Ergebnis**: Ein Trade nach Regeln mit Verlust ist ein guter Trade; ein Regelbruch mit Gewinn ein schlechter. Im Journal getrennt bewerten.
- **Zustand erfassen**: Schlaf, Stress, Stimmung vor dem Handeln (Skala 1 bis 5). Erst damit wird sichtbar, ob schlechte Tage an Zuständen hängen.

## 4. Ehrlich mit sich bleiben [P]

- **Vorab festgelegte Hypothesen**: „Ich vermute, Trades nach 15 Uhr sind schlechter“ zuerst aufschreiben, dann prüfen. Sonst findet man im Nachhinein immer irgendein Muster.
- **Glück vom Können trennen**: Eine Monte-Carlo-Simulation der eigenen Trades zeigt, wie stark das Ergebnis vom Zufall abhängt.
- **Externer Blick**: Die Auswertung durch Henry ist als kritischer Coach angelegt, der Regelbrüche benennt, statt Ergebnisse zu loben.

## Quellen

- Odean, T. (1998): [Are Investors Reluctant to Realize Their Losses?](https://faculty.haas.berkeley.edu/odean/papers%20current%20versions/areinvestorsreluctant.pdf) Journal of Finance 53(5).
- Barber, B., Odean, T. (2001): [Boys Will Be Boys](https://faculty.haas.berkeley.edu/odean/papers/gender/boyswillbeboys.pdf). Quarterly Journal of Economics 116(1).
- Barber, B., Odean, T. (2000): [Trading Is Hazardous to Your Wealth](https://faculty.haas.berkeley.edu/odean/papers%20current%20versions/individual_investor_performance_final.pdf). Journal of Finance 55(2).
- Meta-Analyse Verlustaversion (2024): [Journal of Economic Psychology](https://www.sciencedirect.com/science/article/pii/S0167487024000485).
- Tversky, A., Kahneman, D. (1992): Advances in Prospect Theory. Journal of Risk and Uncertainty 5, 297–323.
- Kahneman, D., Tversky, A. (1974): Judgment under Uncertainty. Science 185, 1124–1131. Standardliteratur, nicht eingesehen.
- Douglas, M. (2000): Trading in the Zone. Prentice Hall. Steenbarger, B. (2009): The Daily Trading Coach. Wiley.
- BaFin (2025): [Studie Turbo-Zertifikate](https://www.bafin.de/SharedDocs/Veroeffentlichungen/DE/Fachartikel/2025/Studie_250521_Turbo_Zertifikate.html), 21.05.2025.
