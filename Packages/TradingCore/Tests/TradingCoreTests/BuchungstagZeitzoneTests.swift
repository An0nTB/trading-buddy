import Foundation
import Testing
@testable import TradingCore

/// Buchungen nur mit Datum stehen auf 00:00 UTC. In New York zählen sie trotzdem zu ihrem Buchungstag,
/// nicht zum Vortag (Codex 04.10.2026, M3).
private let newYork = TimeZone(identifier: "America/New_York")!

private func buchung(_ id: String, _ iso: String) -> Trade {
    let zeit = ISO8601DateFormatter().date(from: iso)!
    return Trade(id: id, symbol: "ETF", side: .buy, lots: 1, openTime: zeit, closeTime: zeit,
                 openPrice: 100, closePrice: 110, profit: 10, nurDatum: true)
}

@Test func buchungOhneUhrzeitBleibtImMonat() throws {
    let maerz = try #require(Zeitspanne.monat(jahr: 2026, monat: 3, zeitzone: newYork))
    let auswertung = Auswertung(trades: [buchung("1", "2026-03-01T00:00:00Z")], zeitraum: maerz, zeitzone: newYork)
    #expect(auswertung.trades.map(\.id) == ["1"])
    #expect(auswertung.kennzahlenVorzeitraum.anzahl == 0)
}

@Test func buchungOhneUhrzeitBehaeltWochentag() {
    // 01.03.2026 ist ein Sonntag (ISO 7), nicht Samstag (6).
    let gruppen = Kennzahlen.aufschluesseln([buchung("1", "2026-03-01T00:00:00Z")], nach: .wochentag, zeitzone: newYork)
    #expect(gruppen.map(\.schluessel) == ["7"])
}
