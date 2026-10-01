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

Freie Wahl (0.2.0): `Boersenauswahl` speichert angezeigte Börsen in eigener Reihenfolge,
eigene Handelszeiten je Börse (Feiertage bleiben) und eigene Börsen; die App legt sie als JSON ab.

```swift
var auswahl = Boersenauswahl(angezeigt: ["xetra", "nyse", "krypto"])
auswahl.angepassteZeiten["xetra"] = [Handelszeit(tage: [.montag, .dienstag, .mittwoch, .donnerstag, .freitag],
                                                 beginn: try Uhrzeit("08:00"), ende: try Uhrzeit("22:00"))]
let uhr = try Boersenuhr.mit(auswahl)          // was angezeigt wird
let liste = try Boersenuhr.verfuegbar(auswahl) // alles, was man hinzufügen kann
```
