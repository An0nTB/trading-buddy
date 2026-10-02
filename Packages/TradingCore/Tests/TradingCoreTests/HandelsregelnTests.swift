import Foundation
import Testing
@testable import TradingCore

/// Sieben Hand-Trades; Sollwerte unabhängig mit Python aus den Regeltexten gerechnet (02.10.2026).
/// Tag 1 (Mo 02.03.2026): Verluste −50, −60, −20, dann +100 und −10. T6 öffnet 23:30 UTC,
/// in Berlin also schon am 03.03. T6 und T7 haben einen Stop: Risiko 20 und 60.
private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso)!
}

private func trade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, kurs: (Decimal, Decimal) = (100, 100),
                   stop: Decimal? = nil) -> Trade {
    Trade(id: id, symbol: "DAX", side: .buy, lots: 1, openTime: zeit(auf), closeTime: zeit(zu),
          openPrice: kurs.0, closePrice: kurs.1, stopLoss: stop, profit: netto)
}

private let regelTrades = [
    trade("T1", "2026-03-02T09:00:00Z", "2026-03-02T09:30:00Z", netto: -50),
    trade("T2", "2026-03-02T09:40:00Z", "2026-03-02T10:00:00Z", netto: -60),
    trade("T3", "2026-03-02T10:10:00Z", "2026-03-02T10:30:00Z", netto: -20),
    trade("T4", "2026-03-02T10:40:00Z", "2026-03-02T11:00:00Z", netto: 100),
    trade("T5", "2026-03-02T11:10:00Z", "2026-03-02T11:20:00Z", netto: -10),
    trade("T6", "2026-03-02T23:30:00Z", "2026-03-03T00:10:00Z", netto: 30, kurs: (100, 103), stop: 98),
    trade("T7", "2026-03-03T08:00:00Z", "2026-03-03T09:00:00Z", netto: -40, kurs: (100, 96), stop: 94),
]

private let regeln = Handelsregeln(maxTagesverlust: 100, maxTradesJeTag: 3, stoppNachVerlusten: 2,
                                   maxRisikoJeTrade: 55)
private let berlin = TimeZone(identifier: "Europe/Berlin")!
private let utcZone = TimeZone(secondsFromGMT: 0)!

private func kurz(_ v: [Regelverstoss]) -> [String] { v.map { "\($0.trade) \($0.art.rawValue)" } }

@Test func risikoAusDemStop() {
    #expect(regelTrades[5].risk == 20)
    #expect(regelTrades[6].risk == 60)
}

@Test func regelnInBerlin() {
    let v = Regelpruefung.pruefe(regelTrades, regeln: regeln, zeitzone: berlin)
    #expect(kurz(v) == ["T2 risikoJeTrade", "T3 tagesverlust", "T3 stoppNachVerlusten", "T4 tradesJeTag",
                        "T4 tagesverlust", "T4 stoppNachVerlusten", "T5 tradesJeTag", "T7 risikoJeTrade"])
    // T7 liegt am 03.03. Berliner Zeit; Tagesbeginn dort ist 23:00 UTC des Vortags.
    #expect(v.last?.tag == zeit("2026-03-02T23:00:00Z"))
}

@Test func tagesgrenzeHaengtAnDerZeitzone() {
    // In UTC gehört T6 noch zum 02.03. und ist dort der sechste Trade.
    let v = Regelpruefung.pruefe(regelTrades, regeln: regeln, zeitzone: utcZone)
    #expect(kurz(v).contains("T6 tradesJeTag"))
    #expect(v.count == 9)
}

@Test func leereRegelnOhneVerstoss() {
    #expect(Handelsregeln().leer)
    #expect(!regeln.leer)
    #expect(Regelpruefung.pruefe(regelTrades, regeln: Handelsregeln(), zeitzone: berlin).isEmpty)
    let manuell = Regelpruefung.pruefe(regelTrades, regeln: Handelsregeln(), zeitzone: berlin, manuell: ["T6"])
    #expect(kurz(manuell) == ["T6 manuell"])
}

@Test func disziplinKurve() {
    let v = Regelpruefung.pruefe(regelTrades, regeln: regeln, zeitzone: berlin)
    let d = Disziplin(trades: regelTrades, verstoesse: v)
    #expect(d.punkte.map(\.trade) == ["T1", "T2", "T3", "T4", "T5", "T6", "T7"])
    #expect(d.punkte.map(\.wert) == [1, 0, -1, -2, -3, -2, -3])
    #expect(d.punkte.map(\.kapital) == [-50, -110, -130, -30, -40, -10, -50])
    #expect(d.regeltreu == 2)
    #expect(d.verletzt == 5)
    #expect(d.quote == Decimal(2) / Decimal(7))
    #expect(d.nettoRegeltreu == -20)
    #expect(d.nettoVerletzt == -30)
    #expect(!d.genugDaten)
}

@Test func disziplinMitJournalMarkierung() {
    let v = Regelpruefung.pruefe(regelTrades, regeln: regeln, zeitzone: berlin, manuell: ["T6"])
    let d = Disziplin(trades: regelTrades, verstoesse: v)
    #expect(d.punkte.map(\.wert) == [1, 0, -1, -2, -3, -4, -5])
    #expect(d.regeltreu == 1)
    #expect(d.nettoRegeltreu == -50)
    #expect(d.nettoVerletzt == 0)
}

@Test func tagesstandFuerDieAmpel() {
    let s = Regelpruefung.tagesstaende(regelTrades, regeln: regeln, zeitzone: berlin)
    #expect(s.map(\.trades) == [5, 2])
    #expect(s.map(\.netto) == [-40, -10])
    #expect(s.map(\.verlusteInFolge) == [1, 1])
    #expect(s.map(\.verstoesse) == [4, 1])
    #expect(s.first?.tag == zeit("2026-03-01T23:00:00Z"))
}

@Test func regelnUeberstehenJSON() throws {
    let daten = try JSONEncoder().encode(regeln)
    #expect(try JSONDecoder().decode(Handelsregeln.self, from: daten) == regeln)
}
