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

Eigene Feiertagskalender (0.3.0): `Feiertagskalender` als JSON (`format`, `id`, `name`, `land`,
`feiertage`, `verkuerzteTage`, `datenGueltigBis`, `stand`, `quellen`, `hinweise`), beliebig viele je Börse:

```swift
let schweiz = try Feiertagskalender.lade(json: daten)
var auswahl = Boersenauswahl(kalender: [schweiz], kalenderJeBoerse: ["xetra": ["ch"]])
let uhr = try Boersenuhr.mit(auswahl)   // Xetra schließt zusätzlich an Schweizer Feiertagen
```

Sitzungsarten (0.4.0, Entscheidung Tim 02.10.2026): Handelszeiten tragen `art` (`kern`, `vorboerslich`,
`nachboerslich`, `nacht`) und wahlweise `gueltigAb`. Die Uhr rechnet standardmäßig nur den Kernhandel;
weitere Arten schaltet die Auswahl je Börse zu. Nasdaq: vorbörslich 04:00 bis 09:30, nachbörslich 16:00 bis 20:00,
Nacht 21:00 bis 04:00 New York ab Sonntag 06.12.2026.

```swift
var auswahl = Boersenauswahl(sitzungsartenJeBoerse: ["nasdaq": [.kern, .nacht]])
let nasdaq = try Boersenuhr.mit(auswahl)["nasdaq"]!
nasdaq.verfuegbareSitzungsarten     // für die Schalter in den Einstellungen
nasdaq.sitzungsart(bei: Date())     // .nacht, .kern … oder nil
```

Weitere Börsen (0.5.0, Wunsch Tim 05.10.2026): Tokio (`xtks`), Hongkong (`xhkg`), Shanghai (`xshg`),
Singapur (`xses`), Seoul (`xkrx`), Taipeh (`xtai`), Mumbai BSE (`xbom`), Sydney ASX (`xasx`), Euronext Paris
(`xpar`), SIX Swiss Exchange (`xswx`), Toronto TSX (`xtse`) und São Paulo B3 (`bvmf`); Kennung ist der MIC
in Kleinbuchstaben, damit sie nicht mit eigenen Börsen („tokio“) zusammenstößt. Handelszeiten, Feiertage und
verkürzte Tage 2026 und 2027 aus exchange_calendars 4.13.2, nicht gegen die Börsenseiten nachgeprüft; Shanghai,
Singapur und Mumbai führt die Bibliothek nur bis Ende 2026 (`datenGueltigBis` 2026-12-31). Mittagspausen
(Tokio 11:30–12:30, Hongkong 12:00–13:00, Shanghai 11:30–13:00) stehen als zwei Handelszeiten am selben Tag;
ein verkürzter Tag, der mit dem Vormittag endet, streicht den Nachmittag und trägt seinen Namen am Vormittag.
Ohne eigene Auswahl zeigt die Uhr weiter nur `Boersenuhr.standardAngezeigt` (die sechs bisherigen) plus eigene
Börsen; die neuen wählt der Nutzer in der Börsenauswahl dazu (`Boersenuhr.verfuegbar`).

```swift
let auswahl = Boersenauswahl(angezeigt: ["xetra", "xtks", "xhkg"])
let tokio = try Boersenuhr.mit(auswahl)["xtks"]!
tokio.status(Date())   // in der Mittagspause: offen == false, naechsterWechsel == 12:30 Tokio
```
