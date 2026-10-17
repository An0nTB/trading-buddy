import Foundation
import Testing
@testable import TradingCore

/// Befunde des Codex-Reviews vom 17.10.2026 zu E1 bis E8, als Tests. Erfundene Trades.
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private let newYork = TimeZone(identifier: "America/New_York")!
private func kurz(_ v: [Regelverstoss]) -> [String] { v.map { "\($0.trade) \($0.art.rawValue)" } }

private func kalender(_ zone: TimeZone) -> Calendar {
    var k = Calendar(identifier: .gregorian)
    k.timeZone = zone
    return k
}

private func kauf(_ id: String, _ iso: String, menge: Decimal, preis: Decimal) -> Ausfuehrung {
    Ausfuehrung(id: id, zeit: zeit(iso), kennung: "DE0007164600", name: "SAP", seite: .buy, menge: menge,
                preis: preis, betrag: -menge * preis, waehrung: "EUR")
}

private func verkauf(_ id: String, _ iso: String, menge: Decimal, preis: Decimal) -> Ausfuehrung {
    Ausfuehrung(id: id, zeit: zeit(iso), kennung: "DE0007164600", name: "SAP", seite: .sell, menge: menge,
                preis: preis, betrag: menge * preis, waehrung: "EUR")
}

// MARK: Teilverkauf mit offenem Rest ist eine Position (Befund 4)

@Test func teilverkaufMitOffenemRestIstEinePosition() {
    // 10 SAP gekauft, 4 am Folgetag verkauft: Der verkaufte Teil und der offene Rest sind eine Position.
    let bildung = Positionsbildung.bilde([kauf("K1", "2026-10-15T08:00:00Z", menge: 10, preis: 100),
                                          verkauf("S1", "2026-10-16T08:00:00Z", menge: 4, preis: 105)])
    let offen = OffenerTrade.sammle(auszug: [], kaeufe: bildung.offen, hand: [], geschlossen: [], geplant: { _ in nil })
    #expect(offen.count == 1)
    let regeln = Handelsregeln(maxOffenePositionen: 1)
    #expect(Regelpruefung.pruefe(bildung.trades, regeln: regeln, zeitzone: berlin, offene: offen,
                                 jetzt: zeit("2026-10-17T08:00:00Z")).isEmpty)
    // Ein zweiter Kauf, während der Rest noch offen ist, ist die zweite Position.
    let zweiter = OffenerTrade(id: "K2", openTime: zeit("2026-10-16T09:00:00Z"))
    #expect(kurz(Regelpruefung.pruefe(bildung.trades, regeln: regeln, zeitzone: berlin, offene: offen + [zweiter],
                                      jetzt: zeit("2026-10-17T08:00:00Z"))) == ["K2 offenePositionen"])
}

@Test func offenesRisikoEinerTeilsVerkauftenPositionZaehltEinmal() {
    let bildung = Positionsbildung.bilde([kauf("K1", "2026-10-15T08:00:00Z", menge: 10, preis: 100),
                                          verkauf("S1", "2026-10-16T08:00:00Z", menge: 4, preis: 105)])
    let offen = OffenerTrade.sammle(auszug: [], kaeufe: bildung.offen, hand: [], geschlossen: [],
                                    geplant: { _ in 30 })
    // Ohne Zusammenführen zählten verkaufter Teil und Rest einander: 30 + 30 über der Grenze von 40.
    let regeln = Handelsregeln(maxOffenesRisiko: 40)
    let trades = bildung.trades.map { $0.mitGeplantemRisiko(30) }
    #expect(Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin, offene: offen,
                                 jetzt: zeit("2026-10-17T08:00:00Z")).filter { $0.art == .offenesRisiko }.count == 2)
    let ohneGeplant = OffenerTrade.sammle(auszug: [], kaeufe: bildung.offen, hand: [], geschlossen: [],
                                          geplant: { _ in nil })
    #expect(Regelpruefung.pruefe(bildung.trades, regeln: regeln, zeitzone: berlin, offene: ohneGeplant,
                                 jetzt: zeit("2026-10-17T08:00:00Z")).isEmpty)
}

// MARK: Buchungen nur mit Datum westlich von UTC (Befund 5)

@Test func kontostandZaehltBuchungNurMitDatumAnIhremTag() {
    let bezug = Kontostandbezug(betrag: 1000, seit: zeit("2026-10-01T04:00:00Z"))
    let verlust = Trade(id: "D1", symbol: "SAP", side: .buy, lots: 1, openTime: zeit("2026-10-15T00:00:00Z"),
                        closeTime: zeit("2026-10-15T00:00:00Z"), openPrice: 100, closePrice: 0, profit: -100,
                        nurDatum: true)
    let ny = kalender(newYork)
    let beginn15 = ny.startOfDay(for: zeit("2026-10-15T12:00:00Z"))
    let beginn16 = ny.startOfDay(for: zeit("2026-10-16T12:00:00Z"))
    // Am 15.10. in New York steht der Verlust desselben Tags noch nicht im Stand zu Tagesbeginn.
    #expect(bezug.stand(bei: beginn15, trades: [verlust], kalender: ny) == 1000)
    #expect(bezug.stand(bei: beginn16, trades: [verlust], kalender: ny) == 900)
    // Berlin war schon richtig und bleibt es.
    let b = kalender(berlin)
    #expect(bezug.stand(bei: b.startOfDay(for: zeit("2026-10-15T12:00:00Z")), trades: [verlust], kalender: b) == 1000)
}

@Test func risikoGrenzeInProzentWestlichVonUTCOhneFalschenVerstoss() {
    // 10 % von 1.000 = 100; der Verlust am selben Tag senkt den Stand zu Tagesbeginn nicht.
    let regeln = Handelsregeln(maxRisikoJeTradeProzent: 10,
                               kontostand: Kontostandbezug(betrag: 1000, seit: zeit("2026-10-01T04:00:00Z")))
    let verlust = Trade(id: "D1", symbol: "SAP", side: .buy, lots: 1, openTime: zeit("2026-10-15T00:00:00Z"),
                        closeTime: zeit("2026-10-15T00:00:00Z"), openPrice: 100, closePrice: 0, profit: -100,
                        nurDatum: true)
    let mitStop = Trade(id: "R1", symbol: "DE40", side: .buy, lots: 1, openTime: zeit("2026-10-15T15:00:00Z"),
                        closeTime: zeit("2026-10-15T16:00:00Z"), openPrice: 100, closePrice: 101, stopLoss: 5,
                        profit: 1)
    #expect(Regelpruefung.pruefe([verlust, mitStop], regeln: regeln, zeitzone: newYork).isEmpty)
}

// MARK: Kill-Kriterium in App und Export gleich (Befund 3)

@Test func kontotradesRechnenFremdwaehrungUm() {
    let usd = Trade(id: "U1", symbol: "AAPL", side: .buy, lots: 1, openTime: zeit("2026-10-15T14:00:00Z"),
                    closeTime: zeit("2026-10-15T15:00:00Z"), openPrice: 100, closePrice: 110, profit: 10,
                    waehrung: "USD").mitGeplantemRisiko(20)
    let kurse = Referenzkurse(kurse: [Journaltag(jahr: 2026, monat: 10, tag: 15)!: ["USD": 2]])
    let mitKurs = Setuppruefung.kontotrades([usd], kontowaehrung: "EUR", kurse: kurse)
    #expect(mitKurs.first?.netProfit == 5)
    #expect(mitKurs.first?.rMultiple == Decimal(string: "0.25"))
    // Ohne Kurs zählt der Trade, aber ohne R aus dem geplanten Risiko in Kontowährung.
    let ohneKurs = Setuppruefung.kontotrades([usd], kontowaehrung: "EUR", kurse: nil)
    #expect(ohneKurs.count == 1 && ohneKurs.first?.rMultiple == nil)
}

// MARK: Offene Positionen im Export (Befund 8)

@Test func offenePositionenGehenMitDemExportMit() throws {
    let offen = [OffenerTrade(id: "O1", openTime: zeit("2026-10-16T08:00:00Z"), risiko: 25,
                              positionsschluessel: "SAP|buy|1")]
    let konto = JournalExport.Kontodaten(broker: "Test", kontonummer: "0000", waehrung: "EUR", trades: [],
                                         offen: offen)
    let daten = try JSONEncoder().encode(konto)
    let gelesen = try JSONDecoder().decode(JournalExport.Kontodaten.self, from: daten)
    #expect(gelesen.offen == offen)
    let leer = JournalExport.Kontodaten(broker: "Test", kontonummer: "0000", waehrung: "EUR", trades: [])
    #expect(leer.offen == nil)
}
