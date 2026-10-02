import Foundation
import Testing
@testable import TradingCore

/// Sechs Hand-Trades auf einem Topstep-ähnlichen 50K-Konto (Handelstag ab 17:00 Chicago, CDT = UTC−5).
/// Sollwerte unabhängig mit Python aus den Regeltexten gerechnet (02.10.2026).
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func trade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, lots: Decimal = 1,
                   stop: Bool = true) -> Trade {
    Trade(id: id, symbol: "MES", side: .buy, lots: lots, openTime: zeit(auf), closeTime: zeit(zu),
          openPrice: 100, closePrice: 100, stopLoss: stop ? Decimal(99) : nil, profit: netto)
}

private let propTrades = [
    trade("A", "2026-04-06T14:00:00Z", "2026-04-06T15:00:00Z", netto: 1500, lots: 2),
    trade("B", "2026-04-06T16:00:00Z", "2026-04-06T17:00:00Z", netto: 500, lots: 6),
    trade("C", "2026-04-06T21:00:00Z", "2026-04-06T23:00:00Z", netto: -300, stop: false),
    trade("D", "2026-04-07T14:00:00Z", "2026-04-07T15:00:00Z", netto: -900),
    trade("E", "2026-04-10T15:00:00Z", "2026-04-13T15:00:00Z", netto: 2400),
    trade("F", "2026-04-14T14:00:00Z", "2026-04-14T15:00:00Z", netto: -1300),
]

private let topstepAehnlich = PropFirmRegeln(
    name: "Test 50K", startkapital: 50_000, zeitzone: "America/Chicago", tageswechselMinuten: 17 * 60,
    maxTagesverlust: 1000, maxGesamtverlust: 2000, gesamtverlustart: .nachgezogenTagesende,
    einfrierenBeiSaldo: 50_000, gewinnziel: 3000, mindestHandelstage: 2, handelstagzaehlung: .ergebnis,
    konsistenzMaxAnteil: Decimal(string: "0.5")!, keinHaltenUeberTageswechsel: true,
    keinHaltenUeberWochenende: true, maxLotsJeTrade: 5, stopPflicht: true)

@Test func propFirmVerstoesse() {
    let e = PropFirmPruefung.pruefe(propTrades, regeln: topstepAehnlich)
    let kurz = e.verstoesse.map { "\($0.trade) \($0.art.rawValue)" }
    #expect(kurz == ["B lotsJeTrade", "C haltenUeberTageswechsel", "C ohneStop", "D tagesverlust",
                     "E haltenUeberTageswechsel", "E haltenUeberWochenende", "F tagesverlust"])
    // Handelstage beginnen 17:00 Chicago = 22:00 UTC am Vortag.
    #expect(e.verstoesse.map(\.tag).first == zeit("2026-04-05T22:00:00Z"))
    #expect(e.verstoesse.last?.tag == zeit("2026-04-13T22:00:00Z"))
}

@Test func propFirmFortschritt() {
    let e = PropFirmPruefung.pruefe(propTrades, regeln: topstepAehnlich)
    #expect(e.saldo == 51_900)
    // Höchster Tagesend-Saldo 53.200 minus 2.000 wäre 51.200; eingefroren beim Startkapital.
    #expect(e.gesamtverlustGrenze == 50_000)
    #expect(e.gewinnzielErreicht == zeit("2026-04-13T15:00:00Z"))
    #expect(e.handelstage == 4)
    // Bester Tag 2.400 bei 1.900 Nettogewinn.
    #expect(e.konsistenzAnteil == Decimal(2400) / Decimal(1900))
    #expect(e.bestanden == false)
    var r = topstepAehnlich
    r.konsistenzbezug = .summeGewinntage
    #expect(PropFirmPruefung.pruefe(propTrades, regeln: r).konsistenzAnteil == Decimal(2400) / Decimal(4400))
}

@Test func propFirmStatischeGesamtgrenze() {
    let r = PropFirmRegeln(name: "statisch", startkapital: 10_000, zeitzone: "UTC", maxGesamtverlust: 500)
    let t = [trade("1", "2026-04-06T10:00:00Z", "2026-04-06T11:00:00Z", netto: -300),
             trade("2", "2026-04-07T10:00:00Z", "2026-04-07T11:00:00Z", netto: -300)]
    let e = PropFirmPruefung.pruefe(t, regeln: r)
    #expect(e.verstoesse.map(\.trade) == ["2"])
    #expect(e.verstoesse.map(\.art) == [.gesamtverlust])
    #expect(e.gesamtverlustGrenze == 9500)
    #expect(e.bestanden == nil)
    #expect(PropFirmPruefung.nurNaeherung.contains(.gesamtverlust))
}

@Test func propFirmAlsTeilDerHandelsregeln() throws {
    let regeln = Handelsregeln(propFirm: topstepAehnlich)
    #expect(!regeln.leer)
    let daten = try JSONEncoder().encode(regeln)
    #expect(try JSONDecoder().decode(Handelsregeln.self, from: daten) == regeln)
}
