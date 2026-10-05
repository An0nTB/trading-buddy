import Foundation
import Testing
@testable import TradingCore

/// Ergebnis-Kalender (Tim 05.10.2026). Sollwerte von Hand gerechnet: Oktober 2026 beginnt an einem Donnerstag.
private func zeitpunkt(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func kalender(_ zone: String) -> Calendar {
    var k = Calendar(identifier: .gregorian)
    k.timeZone = TimeZone(identifier: zone)!
    return k
}

private func trade(_ id: String, geschlossen: String, gewinn: Decimal, kommission: Decimal = 0,
                   nurDatum: Bool = false) -> Trade {
    let schluss = zeitpunkt(geschlossen)
    return Trade(id: id, symbol: "DAX", side: .buy, lots: 1, openTime: schluss.addingTimeInterval(nurDatum ? 0 : -600),
                 closeTime: schluss, openPrice: 100, closePrice: 101, commission: kommission, profit: gewinn,
                 nurDatum: nurDatum)
}

@Test func monatskalenderOrdnetTageWochenUndSummen() throws {
    let trades = [
        trade("a", geschlossen: "2026-10-01T08:00:00Z", gewinn: 100, kommission: -5),
        trade("b", geschlossen: "2026-10-01T13:00:00Z", gewinn: -20),
        trade("c", geschlossen: "2026-10-05T09:00:00Z", gewinn: -50),
        trade("d", geschlossen: "2026-10-06T09:00:00Z", gewinn: 20),
        trade("e", geschlossen: "2026-10-06T10:00:00Z", gewinn: -20),
        // 23:30 Berlin am 31.10. (Winterzeit, UTC+1) gehört noch zum Oktober.
        trade("f", geschlossen: "2026-10-31T22:30:00Z", gewinn: 10),
        // 00:30 Berlin am 1.11. gehört zum November, der 30.09. zum September.
        trade("g", geschlossen: "2026-10-31T23:30:00Z", gewinn: 999),
        trade("h", geschlossen: "2026-09-30T12:00:00Z", gewinn: 999),
    ]
    let monat = Monatskalender(trades: trades, jahr: 2026, monat: 10, kalender: kalender("Europe/Berlin"))

    #expect(monat.wochen.count == 5)
    #expect(monat.wochen.allSatisfy { $0.tage.count == 7 })
    // Montag bis Mittwoch der ersten Woche liegen im September.
    #expect(monat.wochen[0].tage[0...2].allSatisfy { $0 == nil })
    let erster = try #require(monat.wochen[0].tage[3])
    #expect(erster.tag == 1)
    #expect(erster.netto == 75)
    #expect(erster.anzahl == 2)
    #expect(erster.trades == ["a", "b"])
    #expect(monat.tage.count == 31)
    #expect(monat.tage.last?.netto == 10)
    #expect(monat.anzahl == 6)
    #expect(monat.netto == 35)
    // Der 6.10. mit +20 und -20 zählt weder als Gewinn- noch als Verlusttag.
    #expect(monat.gewinnTage == 2)
    #expect(monat.verlustTage == 1)
    #expect(monat.besterTag?.tag == 1)
    #expect(monat.schlechtesterTag?.tag == 5)
    #expect(monat.groessterBetrag == 75)
    #expect(monat.wochen[0].netto == 75)
    #expect(monat.wochen[1].netto == -50)
    #expect(monat.wochen[1].anzahl == 3)
    #expect(monat.wochen[4].netto == 10)
    // Sonntag, 1.11., ist in der letzten Woche leer.
    #expect(monat.wochen[4].tage[6] == nil)
}

@Test func monatskalenderBuchungNurMitDatumBleibtAmTag() {
    // Trade Republic bucht auf 00:00 UTC; in New York läge das sonst am Vortag (Trade.schlusstag).
    let buchung = trade("t", geschlossen: "2026-10-02T00:00:00Z", gewinn: 40, nurDatum: true)
    let monat = Monatskalender(trades: [buchung], jahr: 2026, monat: 10, kalender: kalender("America/New_York"))
    #expect(monat.tage.first { $0.anzahl > 0 }?.tag == 2)
}

@Test func monatskalenderOhneTradesUndFebruar() {
    let leer = Monatskalender(trades: [], jahr: 2027, monat: 2, kalender: kalender("Europe/Berlin"))
    // Februar 2027 beginnt an einem Montag und hat 28 Tage: genau vier Wochen.
    #expect(leer.wochen.count == 4)
    #expect(leer.wochen[0].tage[0]?.tag == 1)
    #expect(leer.netto == 0)
    #expect(leer.gewinnTage == 0)
    #expect(leer.verlustTage == 0)
    #expect(leer.besterTag == nil)
    #expect(leer.schlechtesterTag == nil)
    #expect(leer.groessterBetrag == 0)
}
