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

/// Tagesverlust-Balken (Antwort 12d, 02.10.2026). Sollwerte von Hand aus `propTrades`.
@Test func propFirmTagesstaende() throws {
    let e = PropFirmPruefung.pruefe(propTrades, regeln: topstepAehnlich)
    #expect(e.tage.map(\.tag) == [zeit("2026-04-05T22:00:00Z"), zeit("2026-04-06T22:00:00Z"),
                                  zeit("2026-04-12T22:00:00Z"), zeit("2026-04-13T22:00:00Z")])
    #expect(e.tage.map(\.saldoBeginn) == [50_000, 52_000, 50_800, 53_200])
    #expect(e.tage.map(\.saldoEnde) == [52_000, 50_800, 53_200, 51_900])
    #expect(e.tage.map(\.tiefsterSaldo) == [50_000, 50_800, 50_800, 51_900])
    #expect(e.tage.map(\.verbraucht) == [0, 1200, 0, 1300])
    #expect(e.tage.map(\.anteilTagesverlust) == [0, Decimal(string: "1.2")!, 0, Decimal(string: "1.3")!])
    #expect(e.tage.map(\.tagesverlustGrenze) == [49_000, 51_000, 49_800, 52_200])
    // Nachgezogen ab höchstem Tagesend-Saldo, eingefroren bei 50.000.
    #expect(e.tage.map(\.gesamtverlustGrenze) == [48_000, 50_000, 50_000, 50_000])
    let ohneRegeln = PropFirmPruefung.pruefe(propTrades, regeln: PropFirmRegeln(name: "leer", startkapital: 50_000))
    let erster = try #require(ohneRegeln.tage.first)
    #expect(erster.tagesverlustGrenze == nil && erster.anteilTagesverlust == nil && erster.gesamtverlustGrenze == nil)
}

@Test func propFirmVerstoesseInDisziplin() {
    let e = PropFirmPruefung.pruefe(propTrades, regeln: topstepAehnlich)
    let eigene = [Regelverstoss(art: .manuell, trade: "B", tag: zeit("2026-04-06T00:00:00Z"))]
    let d = Disziplin(trades: propTrades, verstoesse: eigene, propFirm: e.verstoesse)
    // B, C, D, E, F verletzt; B nur einmal, obwohl eigener und Prop-Firm-Verstoß.
    #expect(d.regeltreu == 1 && d.verletzt == 5)
    #expect(d.punkte.map(\.wert) == [1, 0, -1, -2, -3, -4])
    #expect(Disziplin(trades: propTrades, verstoesse: eigene).verletzt == 1)
}
