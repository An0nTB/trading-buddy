import Foundation
import Testing
@testable import TradingCore

/// Bekanntes Stop-Risiko von Hand-Trades bleibt auch ohne Kursergebnis erhalten. Erfundene Werte.
@Test(arguments: [Side.buy, .sell], [false, true])
func handtradeOhneKursbewegungBehaeltStopRisiko(richtung: Side, schein: Bool) throws {
    let stop: Decimal = richtung == .sell && !schein ? 105 : 95
    let hand = ManuellerTrade(symbol: "Testwert", einstieg: Date(timeIntervalSince1970: 1_780_000_000),
                              markterwartung: richtung, schein: schein, groesse: 10, einstiegskurs: 100,
                              ausstiegskurs: 100, stopKurs: stop, gebuehren: 2)
    let trade = Trade(hand.position(ticket: "hand-test")).mitGeplantemRisiko(100)
    #expect(trade.stopRisiko == 50)
    #expect(trade.risk == 50)
    #expect(trade.rMultiple == Decimal(string: "-0.04")!)
    #expect(!trade.risikoAngenommen)

    let daten = try JSONEncoder().encode(trade)
    let gelesen = try JSONDecoder().decode(Trade.self, from: daten)
    #expect(gelesen == trade)
    #expect(gelesen.stopRisiko == 50)
    #expect(gelesen.rMultiple == Decimal(string: "-0.04")!)
}

@Test func handtradeMitGerundetemNullgewinnBehaeltStopRisiko() {
    let hand = ManuellerTrade(symbol: "Testwert", einstieg: Date(timeIntervalSince1970: 1_780_000_000),
                              markterwartung: .buy, groesse: 10, einstiegskurs: 100,
                              ausstiegskurs: Decimal(string: "100.0001")!, stopKurs: 95, gebuehren: 2)
    let trade = Trade(hand.position(ticket: "hand-test"))
    #expect(trade.profit == 0)
    #expect(trade.stopRisiko == 50)
    #expect(trade.rMultiple == Decimal(string: "-0.04")!)
}

@Test func handtradeRisikoFolgtStopUndWaehrungsangleich() throws {
    let zeit = ISO8601DateFormatter().date(from: "2026-03-02T12:00:00Z")!
    let hand = ManuellerTrade(symbol: "Testwert", einstieg: zeit, markterwartung: .buy,
                              groesse: 10, einstiegskurs: 100, ausstiegskurs: 100, stopKurs: 95, gebuehren: 2)
    var trade = Trade(hand.position(ticket: "hand-test"))
    trade.stopLoss = 80
    trade.waehrung = "USD"
    let kurse = Referenzkurse(kurse: [Journaltag("2026-03-02")!: ["USD": Decimal(string: "1.25")!]])
    let angleich = Waehrungsangleich([trade], kontowaehrung: "EUR", kurse: kurse)
    let umgerechnet = try #require(angleich.trades.first)
    #expect(umgerechnet.stopRisiko == 160)
    #expect(umgerechnet.rMultiple == Decimal(string: "-0.01")!)
    trade.stopLoss = nil
    #expect(trade.stopRisiko == nil)
    trade.stopLoss = 101
    #expect(trade.stopRisiko == nil)
}
