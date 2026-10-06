import Foundation
import Testing
@testable import TradingCore

/// Offene Hand-Trades (Kern 0.27.0), erfundene Werte.
private let offenStart = Date(timeIntervalSince1970: 1_780_000_000)

private func offenerSchein() -> ManuellerTrade {
    ManuellerTrade(symbol: " DE40 Turbo Short ", einstieg: offenStart, ausstieg: offenStart.addingTimeInterval(-60),
                   markterwartung: .sell, schein: true, groesse: 200, einstiegskurs: Decimal(string: "4.5")!,
                   ausstiegskurs: nil, risiko: 100, ziel: 6, gebuehren: Decimal(string: "1.5")!, produktart: .derivat)
}

@Test func offenerHandTradeOhneAusstiegskurs() {
    let t = offenerSchein()
    #expect(t.offen)
    #expect(t.ergebnis == 0)
    // Ausstiegszeit vor dem Einstieg zählt bei offenen Trades nicht.
    #expect(t.pruefe().isEmpty)
    var geschlossen = t
    geschlossen.ausstiegskurs = 5
    #expect(!geschlossen.offen)
    #expect(geschlossen.ergebnis == 100)
    #expect(geschlossen.pruefe() == [.ausstiegVorEinstieg])
}

@Test func offenerHandTradeAlsOffenePosition() {
    let p = offenerSchein().offenePosition(ticket: "hand-offen-1")
    #expect(p.ticket == "hand-offen-1")
    #expect(p.rohzeile.isEmpty)
    #expect(p.side == .buy)
    #expect(p.symbol == "DE40 Turbo Short")
    #expect(p.lots == 200)
    #expect(p.openTime == offenStart)
    #expect(p.openPrice == Decimal(string: "4.5")!)
    // Stop aus dem Risiko: 100 ÷ 200 = 0,5 unter dem Einstieg.
    #expect(p.stopLoss == 4)
    #expect(p.takeProfit == 6)
    #expect(p.currentPrice == Decimal(string: "4.5")!)
    #expect(p.commission == Decimal(string: "-1.5")!)
    #expect(p.swap == 0)
    #expect(p.profit == 0)
    #expect(p.produktart == .derivat)
}

@Test func offenerHandTradeSchliessenErgibtGeschlossenePosition() {
    var t = offenerSchein()
    t.ausstieg = offenStart.addingTimeInterval(3_600)
    t.ausstiegskurs = 0
    // Ausgeknockter Schein schließt mit 0: (0 − 4,5) × 200 = −900.
    #expect(t.pruefe().isEmpty)
    let p = t.position(ticket: "hand-offen-1")
    #expect(p.closePrice == 0)
    #expect(p.profit == -900)
    #expect(p.ausstiegszeitBekannt)
}

@Test func offenerHandTradeNegativerEinstiegBleibtFehler() {
    var t = offenerSchein()
    t.einstiegskurs = 0
    #expect(t.pruefe().contains(.kursNichtPositiv))
}
