# TradingCalendar

Terminkalender ohne Oberfläche: Zinsentscheide (Fed, EZB, BoE, BoJ, SNB), wichtige US-Daten
(Arbeitsmarktbericht, Verbraucherpreise der BLS) und Bankfeiertage für USD, EUR, GBP und JPY
als JSON je Jahr in `Sources/TradingCalendar/Termine/`.
Eine frei nutzbare Kalender-API gibt es nicht (R1 Abschnitt 5), daher pflegt eine Datei je Jahr
die Termine aus den offiziellen Seiten nach. Prognose- und Ist-Werte gibt es hier nicht.

```swift
let kalender = try Terminkalender.mitgeliefert()
// „über Termin gehalten“ (Doc 18 F9): Termine zwischen Eröffnung und Schließung, nur betroffene Währungen
let termine = kalender.termine(von: eroeffnet, bis: geschlossen,
                               waehrungen: Terminkalender.waehrungen(symbol: "EURUSD"))
kalender.abgedeckt(von: eroeffnet, bis: geschlossen) // false: leeres Ergebnis heißt nichts
```

Dateiformat 1: `format`, `jahr`, `stand`, `vollstaendig` (Arten, die das Jahr ganz enthält),
`quellen`, `hinweise`, `termine`. Ein Termin hat `id`, `art` (zinsentscheid, arbeitsmarkt, inflation, feiertag),
`institution`, `titel`, `datum` ("JJJJ-MM-TT"), optional `uhrzeit` ("HH:MM" Ortszeit), `zeitzone` (IANA),
`waehrungen`, optional `vorlaeufig` und `hinweis`. Ohne `uhrzeit` gilt der ganze Tag in der Zeitzone.

Jährlich nachziehen: Fed, EZB, BoE, BoJ und SNB veröffentlichen das Folgejahr meist im Vorjahr,
die BLS ihren Jahresplan zum Jahreswechsel. Details und Quellen im Stand-Doc 25.
