# Orderarten und Ausführung

## 1. Die Grund-Orderarten [G]

| Order | Was passiert | Vorteil | Nachteil |
|---|---|---|---|
| Market (Bestens, Billigst) | Sofort zum nächsten verfügbaren Preis | Ausführung sicher | Preis nicht sicher, Slippage |
| Limit | Nur zum Limit oder besser | Preis sicher | Ausführung nicht sicher |
| Stop (Stop-Market, Stop-Loss) | Wird bei Erreichen des Stop-Preises zur Market-Order | Begrenzt Verlust im Normalfall | Bei Gap oder schnellem Markt deutlich schlechter ausgeführt |
| Stop-Limit | Wird bei Erreichen zur Limit-Order | Kein Ausreißer-Preis | Kann gar nicht ausgeführt werden, Verlust läuft weiter |
| Take-Profit | Limit-Order zum Gewinnmitnehmen | Plan wird umgesetzt | Schneidet große Bewegungen ab |
| Trailing Stop | Stop wandert mit dem Kurs nach | Sichert Gewinne | Wird in Schwankungen früh ausgelöst |

## 2. MetaTrader-Begriffe [G]

| Typ im Auszug | Bedeutung |
|---|---|
| buy, sell | Ausgeführte Market-Order, Position eröffnet |
| buy limit | Kaufen, wenn der Kurs **fällt** auf X |
| sell limit | Verkaufen, wenn der Kurs **steigt** auf X |
| buy stop | Kaufen, wenn der Kurs **steigt** auf X (Ausbruch) |
| sell stop | Verkaufen, wenn der Kurs **fällt** auf X |
| S/L, T/P | Stop-Loss und Take-Profit zur Position |
| cancelled | Pending-Order gelöscht, nie ausgeführt |

Stornierte Pending-Orders sind keine Trades. Ihre Anzahl kann aber ein Signal für Unruhe oder ständiges Umplanen sein. Einschätzung, als Kennzahl „Stornoquote“ prüfbar.

## 3. Kombinierte Orders [F]

- **OCO (One Cancels Other)**: Zwei Orders, die erste ausgeführte löscht die andere. Typisch: Stop und Take-Profit gemeinsam.
- **Bracket-Order**: Einstieg plus Stop plus Ziel in einem Auftrag. Erzwingt einen Plan vor dem Trade.
- **Gültigkeit**: Tagesorder (verfällt zum Handelsschluss) oder GTC (bis auf Widerruf). Bei GTC bleiben vergessene Orders gefährlich im Markt.

## 4. Ausführungsqualität [F]

- **Slippage**: Differenz zwischen erwartetem und tatsächlichem Ausführungspreis. Besonders bei Nachrichten, Eröffnung und dünnen Märkten.
- **Spread** (Kapitel 1): Bei Scalping kann der Spread den Großteil des Ergebnisses ausmachen.
- **Requotes und Ablehnungen**: Bei Market-Maker-Modellen kann eine Order zu neuem Preis angeboten oder abgelehnt werden.
- **Garantierter Stop**: Manche CFD-Broker bieten Stops mit garantiertem Preis gegen Aufpreis. Einziger Schutz gegen Gaps bei CFDs.
- **Handelsplatzwahl** bei Aktien: Börse (Xetra, Regionalbörse) oder außerbörslicher Market Maker. Unterschied bei Spread, Handelszeiten und Ausführungsregeln.

## 5. Was der Stop-Loss leistet und was nicht [G]

- Er legt **vorher** fest, wo der Trade falsch ist. Ohne diesen Punkt gibt es kein Risiko in Euro und kein R-Multiple (Kapitel 8).
- Er ist kein garantierter Preis (außer garantierter Stop). Über Nacht, am Wochenende und bei Nachrichten kann der Kurs darüber springen.
- Ein **mentaler Stop** (nur im Kopf) wird in der Praxis häufig nicht eingehalten. Einschätzung aus der Journal-Praxis; in Daten sichtbar, wenn Verluste regelmäßig größer sind als das geplante Risiko.
- **Stop verschieben**: nach hinten (mehr Risiko) gilt als klassischer Fehler, nach vorne (Gewinn sichern) ist eine bewusste Entscheidung. Der MetaTrader-Auszug zeigt nur den letzten S/L-Wert; deshalb den Stop beim Einstieg zusätzlich im Journal festhalten.

## 6. Ausführung und Auswertung zusammen denken [P]

- **Geplanter Einstieg gegen tatsächlichen Einstieg**: Die Abweichung misst Ausführungsdisziplin und Slippage.
- **Teilausführungen und Teilschließungen**: Eine Position mit drei Teilverkäufen ist ein Trade mit mehreren Ausstiegen. Teilgeschäfte gehören zu einer Position zusammengeführt, sonst stimmen Trefferquote und Durchschnitte nicht.
- **Skalieren**: Nachkaufen im Gewinn (Pyramidisieren) oder im Verlust (Verbilligen). Verbilligen ohne Plan ist ein häufiges Fehlermuster (Kapitel 9).

## Quellen

- Orderarten und ihre Mechanik: fachlicher Standard aus Börsen- und Broker-Dokumentation (Definitionen, kein Einzelbeleg).
- MetaTrader-Typen: MetaTrader-Konvention, bestätigt am Beispielauszug der Recherche (2026).
- Mentale Stops werden häufig nicht eingehalten: Praxisberichte, Einschätzung ohne Studie.
