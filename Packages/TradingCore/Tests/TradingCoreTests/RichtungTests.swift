import Foundation
import Testing
@testable import TradingCore

/// Long/Short nach Markterwartung: Ein gekaufter Short-Turbo zählt als Short (Auswertung-Thread, 05.10.2026).
/// Erfundene Trades, Sollwerte von Hand.

private func richtungTrade(_ id: String, minute: Double, side: Side, profit: Decimal,
                           markterwartung: Side? = nil) -> Trade {
    let eroeffnung = Date(timeIntervalSince1970: 1_760_000_000 + minute * 60)
    return Trade(id: id, symbol: "Musterwert", side: side, lots: 1, openTime: eroeffnung,
                 closeTime: eroeffnung.addingTimeInterval(600), openPrice: 10, closePrice: 11, profit: profit,
                 markterwartung: markterwartung)
}

private let richtungTrades = [
    richtungTrade("k", minute: 0, side: .buy, profit: 30),
    richtungTrade("v", minute: 20, side: .sell, profit: -10),
    // Short-Turbo: gekauft, Markterwartung fallend.
    richtungTrade("t", minute: 40, side: .buy, profit: 25, markterwartung: .sell),
    // Long-Turbo: gekauft, Markterwartung steigend.
    richtungTrade("l", minute: 60, side: .buy, profit: -5, markterwartung: .buy),
]

@Test func richtungFolgtMarkterwartung() {
    #expect(richtungTrades.map(\.richtung) == [.buy, .sell, .sell, .buy])
    #expect(richtungTrades[2].side == .buy)
}

@Test func richtungAnteileZaehlenShortTurboAlsShort() {
    let anteile = Tiefenanalyse.anteileRichtung(richtungTrades)
    #expect(anteile.map(\.schluessel) == ["buy", "sell"])
    #expect(anteile.map(\.wert) == [2, 2])
    #expect(anteile[0].tradeIDs == ["k", "l"] && anteile[1].tradeIDs == ["v", "t"])
}

@Test func richtungAufschluesselungZaehltShortTurboAlsShort() {
    let gruppen = Kennzahlen.aufschluesseln(richtungTrades, nach: .richtung, zeitzone: TimeZone(secondsFromGMT: 0)!)
    let netto = Dictionary(uniqueKeysWithValues: gruppen.map { ($0.schluessel, $0.kennzahlen.netto) })
    #expect(netto == ["buy": 25, "sell": 15])
}
