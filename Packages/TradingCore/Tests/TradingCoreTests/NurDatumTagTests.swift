import Foundation
import Testing
@testable import TradingCore

/// Trades nur mit Datum (00:00 UTC) westlich von UTC: Sie zählen an ihrem Datum, nicht am Vortag
/// (Zweiter Gegencheck, Doc 40). Sollwerte von Hand (02.10.2026).
private func nurDatumZeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

private func nurDatumTrade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, nurDatum: Bool,
                           symbol: String = "SAP") -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: nurDatumZeit(auf), closeTime: nurDatumZeit(zu),
          openPrice: 100, closePrice: 100, profit: netto, nurDatum: nurDatum)
}

private let newYork = TimeZone(identifier: "America/New_York")!

private func kalender(_ zone: TimeZone) -> Calendar {
    var k = Calendar(identifier: .gregorian)
    k.timeZone = zone
    return k
}

@Test func nurDatumZaehltAmEigenenTagAuchWestlichVonUTC() {
    let k = kalender(newYork)
    let tag3 = k.date(from: DateComponents(year: 2026, month: 3, day: 3))!
    // Nur Datum: 3. März, auch wenn 00:00 UTC in New York noch der 2. März ist.
    #expect(Trade.tagesbeginn(nurDatumZeit("2026-03-03T00:00:00Z"), nurDatum: true, kalender: k) == tag3)
    // Mit Uhrzeit bleibt es der Kalendertag in New York.
    let tag2 = k.date(from: DateComponents(year: 2026, month: 3, day: 2))!
    #expect(Trade.tagesbeginn(nurDatumZeit("2026-03-03T00:00:00Z"), nurDatum: false, kalender: k) == tag2)
    // Ein Trade mit Uhrzeit auf einer Seite: Diese Seite behält ihren Tag.
    #expect(Trade.tagesbeginn(nurDatumZeit("2026-03-03T03:00:00Z"), nurDatum: true, kalender: k) == tag2)
    // Östlich von UTC ändert sich nichts.
    let berlin = kalender(TimeZone(identifier: "Europe/Berlin")!)
    #expect(Trade.tagesbeginn(nurDatumZeit("2026-03-03T00:00:00Z"), nurDatum: true, kalender: berlin)
        == berlin.date(from: DateComponents(year: 2026, month: 3, day: 3))!)
}

@Test func nurDatumInPlanwirkungUndRegeln() {
    let trades = [
        nurDatumTrade("a", "2026-03-03T00:00:00Z", "2026-03-03T00:00:00Z", netto: -10, nurDatum: true),
        nurDatumTrade("b", "2026-03-03T00:00:00Z", "2026-03-03T00:00:00Z", netto: -10, nurDatum: true, symbol: "BAS"),
        // 2. März 20:00 in New York, mit Uhrzeit.
        nurDatumTrade("c", "2026-03-03T01:00:00Z", "2026-03-03T01:30:00Z", netto: 5, nurDatum: false),
    ]
    // Plan am Vorabend des 3. März (New York) gespeichert: gilt für den 3., der Trade c liegt am 2.
    let notiz = Tagesnotiz(tag: Journaltag(jahr: 2026, monat: 3, tag: 3)!, plan: "Nur Ausbrüche",
                           planErstellt: nurDatumZeit("2026-03-03T02:00:00Z"))
    let wirkung = Planwirkung(trades: trades, notizen: [notiz], zeitzone: newYork)
    #expect(wirkung.tageMitPlan == 1)
    #expect(wirkung.tradesMitPlan == 2)
    #expect(wirkung.tageOhnePlan == 1)
    #expect(wirkung.tradesOhnePlan == 1)

    let staende = Regelpruefung.tagesstaende(trades, regeln: Handelsregeln(maxTradesJeTag: 2), zeitzone: newYork)
    let k = kalender(newYork)
    #expect(staende.map(\.tag) == [k.date(from: DateComponents(year: 2026, month: 3, day: 2))!,
                                   k.date(from: DateComponents(year: 2026, month: 3, day: 3))!])
    #expect(staende.map(\.trades) == [1, 2])
    #expect(staende.map(\.netto) == [5, -20])
}
