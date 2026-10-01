# TradingClock

Börsenuhr ohne Oberfläche: Handelszeiten und Feiertage je Börse als JSON-Datei in
`Sources/TradingClock/Boersen/`, daraus „ist offen?“ und „nächste Öffnung oder Schließung“.

```swift
let uhr = try Boersenuhr.mitgeliefert()
let status = uhr["xetra"]!.status(Date())
// status.offen, status.naechsterWechsel, status.feiertag, status.verkuerzt, status.datenGueltig
```

Dateiformat 1: `id`, `name`, `mic`, `zeitzone` (IANA), `handelszeiten` (Tage "Mo" bis "So",
`beginn`, `ende` als "HH:MM" Ortszeit, `endeNachTagen` für Sitzungen über Mitternacht),
`feiertage`, `verkuerzteTage`, `datenGueltigBis`, `stand`, `quellen`, `hinweise`;
`durchgehend: true` für Märkte rund um die Uhr. Details im Stand-Doc 15.
