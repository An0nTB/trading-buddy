# TradingCalendar

Terminkalender ohne Oberfläche: Zinsentscheide (Fed, EZB, BoE, BoJ, SNB, RBA, BoC, RBNZ, Norges Bank, Riksbank,
PBoC), Notenbank-Protokolle, Konjunkturdaten aus USA, Euroraum, Deutschland, Großbritannien, China und Japan,
US-Öllager und OPEC, Verfallstage, Index-Überprüfungen, Wahlen und Bankfeiertage
als JSON je Jahr in `Sources/TradingCalendar/Termine/`. Börsenfeiertage kommen nicht aus diesen Dateien, sondern
aus den Börsenkalendern von TradingClock (`Terminkalender.boersenfeiertag(...)`), damit sie nur einmal gepflegt werden.
Eine frei nutzbare Kalender-API gibt es nicht (R1 Abschnitt 5), daher pflegt eine Datei je Jahr
die Termine aus den offiziellen Seiten nach. Prognose- und Ist-Werte gibt es hier nicht.

```swift
let kalender = try Terminkalender.mitgeliefert()
// „über Termin gehalten“ (Doc 18 F9): Termine zwischen Eröffnung und Schließung, nur betroffene Währungen
let termine = kalender.termine(von: eroeffnet, bis: geschlossen,
                               waehrungen: Terminkalender.waehrungen(symbol: "EURUSD"))
kalender.abgedeckt(von: eroeffnet, bis: geschlossen) // false: leeres Ergebnis heißt nichts
```

Dateiformat 2 (1 wird weiter gelesen): `format`, `jahr`, `stand`, `vollstaendig` (Arten, die das Jahr ganz enthält),
`quellen`, `hinweise`, `termine`. Ein Termin hat `id`, `art` (zinsentscheid, arbeitsmarkt, inflation, feiertag, konjunktur, notenbank, rohstoffe, verfall,
index, politik; boersenfeiertag nur aus TradingClock),
`institution`, `titel`, `datum` ("JJJJ-MM-TT"), optional `uhrzeit` ("HH:MM" Ortszeit), `zeitzone` (IANA),
`waehrungen`, optional `vorlaeufig`, `hinweis`, `wichtigkeit` („hoch“, „mittel“; Standard: Zinsentscheid,
Arbeitsmarkt und Inflation hoch, sonst mittel) und `region` (Kürzel aus `Terminkalender.regionen`; Standard aus der
einzigen Währung, sonst „welt“). Ohne `uhrzeit` gilt der ganze Tag in der Zeitzone.

Filter für die Kalender-Seite: `termine(von:bis:waehrungen:arten:regionen:mindestens:)` oder `Termin.passt(...)`.

Jährlich nachziehen: Fed, EZB, BoE, BoJ und SNB veröffentlichen das Folgejahr meist im Vorjahr,
die BLS ihren Jahresplan zum Jahreswechsel; BEA, Census, ISM, EIA, Eurostat, Destatis, ONS und NBS ebenfalls
gegen Jahresende. Statistics Canada, ABS und das Statistics Bureau of Japan veröffentlichen nur einige Monate im
Voraus und müssen laufend nachgezogen werden. Termine nur von den Herausgebern, nie aus Kalendern wie Forex Factory oder Investing
(Nutzungsbedingungen). Details und Quellen in den Stand-Docs 25 und 63.
