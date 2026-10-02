import Foundation
import Testing
@testable import TradingCalendar

// Erwartete UTC-Zeiten mit Python zoneinfo gerechnet (Stand-Doc 25).
private func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private func datei(_ termine: String, jahr: Int = 2026) -> Data {
    Data("""
    {"format": 1, "jahr": \(jahr), "stand": "2026-10-02", "vollstaendig": ["zinsentscheid"], "termine": [\(termine)]}
    """.utf8)
}

@Test func mitgelieferteDateienVollstaendig() throws {
    let kalender = try Terminkalender.mitgeliefert()
    #expect(kalender.dateien.map(\.jahr) == [2025, 2026, 2027])
    #expect(kalender.dateien.map(\.termine.count) == [101, 102, 73])
    #expect(kalender.termine.count == 276)
    #expect(zip(kalender.termine, kalender.termine.dropFirst()).allSatisfy { $0.beginn <= $1.beginn })
    // Vorläufig: SNB aus Sekundärquelle und die nach Regel berechneten Feiertage EUR und JPY.
    #expect(kalender.termine.filter(\.vorlaeufig).count == 69)
    #expect(kalender.termine.filter { $0.vorlaeufig && $0.art != .feiertag }.map(\.id) == ["snb-2026-12-10"])
}

@Test func zeitenInOrtszeitMitSommerzeit() throws {
    let kalender = try Terminkalender.mitgeliefert()
    func termin(_ id: String) -> Termin? { kalender.termine.first { $0.id == id } }
    #expect(termin("fed-2026-10-28")?.beginn == utc("2026-10-28T18:00:00Z"))
    #expect(termin("fed-2026-03-18")?.beginn == utc("2026-03-18T18:00:00Z"))
    #expect(termin("ezb-2026-10-29")?.beginn == utc("2026-10-29T13:15:00Z"))
    #expect(termin("boe-2026-11-05")?.beginn == utc("2026-11-05T12:00:00Z"))
    #expect(termin("snb-2026-12-10")?.beginn == utc("2026-12-10T08:30:00Z"))
    let boj = try #require(termin("boj-2026-10-30"))
    #expect(boj.ganztaegig)
    #expect(boj.beginn == utc("2026-10-29T15:00:00Z"))
    #expect(boj.ende == utc("2026-10-30T15:00:00Z"))
}

@Test func ueberTerminGehalten() throws {
    let kalender = try Terminkalender.mitgeliefert()
    // EURUSD über die Fed-Sitzung
    let eurusd = kalender.termine(von: utc("2026-10-28T17:00:00Z"), bis: utc("2026-10-28T19:00:00Z"),
                                  waehrungen: Terminkalender.waehrungen(symbol: "EURUSD.m"))
    #expect(eurusd.map(\.id) == ["fed-2026-10-28"])
    // USDJPY über Nacht: BoJ ganztägig in Tokio, EZB um 13:15 UTC liegt davor und betrifft weder USD noch JPY.
    let usdjpy = kalender.termine(von: utc("2026-10-29T15:00:00Z"), bis: utc("2026-10-30T10:00:00Z"),
                                  waehrungen: Terminkalender.waehrungen(symbol: "USDJPY"))
    #expect(usdjpy.map(\.id) == ["boj-2026-10-30"])
    // Grenzen gehören dazu; ganztägig endet ausschließlich.
    #expect(kalender.termine(von: utc("2026-10-28T18:00:00Z"), bis: utc("2026-10-28T18:00:00Z")).map(\.id) == ["fed-2026-10-28"])
    #expect(kalender.termine(von: utc("2026-10-30T15:00:00Z"), bis: utc("2026-10-30T16:00:00Z"),
                             waehrungen: ["JPY"]).isEmpty)
    // Ohne Filter alles im Fenster, mit Art-Filter nur Zinsentscheide.
    let woche = kalender.termine(von: utc("2026-10-28T00:00:00Z"), bis: utc("2026-10-30T23:59:00Z"))
    #expect(woche.map(\.id) == ["fed-2026-10-28", "ezb-2026-10-29", "boj-2026-10-30"])
    let daten = kalender.termine(von: utc("2026-10-01T00:00:00Z"), bis: utc("2026-10-31T00:00:00Z"), arten: [.arbeitsmarkt, .inflation])
    #expect(daten.map(\.id) == ["bls-nfp-2026-10-02", "bls-cpi-2026-10-14"])
}

@Test func waehrungenAusSymbol() {
    #expect(Terminkalender.waehrungen(symbol: "EURUSD.m") == ["EUR", "USD"])
    #expect(Terminkalender.waehrungen(symbol: "gbpjpy") == ["GBP", "JPY"])
    #expect(Terminkalender.waehrungen(symbol: "GER40.cash") == ["EUR"])
    #expect(Terminkalender.waehrungen(symbol: "US500") == ["USD"])
    #expect(Terminkalender.waehrungen(symbol: "BTCUSDT") == ["USD"])
    #expect(Terminkalender.waehrungen(symbol: "AUDCAD").isEmpty)
}

@Test func abdeckungJeArtUndJahr() throws {
    let kalender = try Terminkalender.mitgeliefert()
    #expect(kalender.abgedeckt(jahr: 2026, art: .inflation))
    #expect(kalender.abgedeckt(jahr: 2027, art: .zinsentscheid))
    #expect(!kalender.abgedeckt(jahr: 2027, art: .arbeitsmarkt))
    #expect(!kalender.abgedeckt(jahr: 2024, art: .zinsentscheid))
    #expect(kalender.abgedeckt(von: utc("2025-12-30T00:00:00Z"), bis: utc("2026-01-05T00:00:00Z")))
    #expect(!kalender.abgedeckt(von: utc("2026-12-30T00:00:00Z"), bis: utc("2027-01-05T00:00:00Z")))
    #expect(kalender.abgedeckt(von: utc("2026-12-30T00:00:00Z"), bis: utc("2027-01-05T00:00:00Z"), arten: [.zinsentscheid]))
}

@Test func fehlerhafteDateienWerdenAbgelehnt() {
    let gut = #""id": "x", "art": "zinsentscheid", "institution": "fed", "titel": "T", "zeitzone": "America/New_York", "waehrungen": ["USD"]"#
    #expect(throws: TerminkalenderFehler.ungueltigesDatum(id: "x", text: "2026-02-30")) {
        try Jahresdatei.lade(json: datei("{\(gut), \"datum\": \"2026-02-30\"}"))
    }
    #expect(throws: TerminkalenderFehler.ungueltigeUhrzeit(id: "x", text: "24:00")) {
        try Jahresdatei.lade(json: datei("{\(gut), \"datum\": \"2026-02-03\", \"uhrzeit\": \"24:00\"}"))
    }
    #expect(throws: TerminkalenderFehler.falschesJahr(id: "x", jahr: 2027)) {
        try Jahresdatei.lade(json: datei("{\(gut), \"datum\": \"2026-02-03\"}", jahr: 2027))
    }
    #expect(throws: TerminkalenderFehler.doppelteID("x")) {
        try Jahresdatei.lade(json: datei("{\(gut), \"datum\": \"2026-02-03\"}, {\(gut), \"datum\": \"2026-02-04\"}"))
    }
    let zone = #"{"id": "y", "art": "inflation", "institution": "bls", "titel": "T", "datum": "2026-02-03", "zeitzone": "Mars/Olympus", "waehrungen": ["USD"]}"#
    #expect(throws: TerminkalenderFehler.unbekannteZeitzone(id: "y", text: "Mars/Olympus")) {
        try Jahresdatei.lade(json: datei(zone))
    }
}

@Test func feiertageJeWaehrung() throws {
    let kalender = try Terminkalender.mitgeliefert()
    let ids = Set(kalender.termine.filter { $0.art == .feiertag }.map(\.id))
    // Großbritannien: Boxing Day 2026 auf Montag verschoben (gov.uk).
    #expect(ids.contains("feiertag-gbp-2026-12-28"))
    // Fed: Samstag 04.07.2026 ohne Ersatz am Freitag, Sonntag 04.07.2027 auf Montag.
    #expect(!ids.contains("feiertag-usd-2026-07-03"))
    #expect(ids.contains("feiertag-usd-2027-07-05"))
    // Japan: Volksfeiertag zwischen zwei Feiertagen, ganztägig in Tokio.
    let volk = try #require(kalender.termine.first { $0.id == "feiertag-jpy-2026-09-22" })
    #expect(volk.ganztaegig && volk.vorlaeufig)
    #expect(volk.beginn == utc("2026-09-21T15:00:00Z"))
    // Keine Wochenenden.
    #expect(kalender.termine.filter { $0.art == .feiertag }.allSatisfy { t in
        let tag = Calendar(identifier: .gregorian).dateComponents(in: t.zeitzone, from: t.beginn).weekday!
        return tag != 1 && tag != 7
    })
    // GBPUSD über Weihnachten 2026 gehalten.
    let gehalten = kalender.termine(von: utc("2026-12-24T12:00:00Z"), bis: utc("2026-12-29T12:00:00Z"),
                                    waehrungen: Terminkalender.waehrungen(symbol: "GBPUSD"), arten: [.feiertag])
    #expect(gehalten.map(\.id) == ["feiertag-gbp-2026-12-25", "feiertag-usd-2026-12-25", "feiertag-gbp-2026-12-28"])
}
