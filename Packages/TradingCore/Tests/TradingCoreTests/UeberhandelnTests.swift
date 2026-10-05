import Foundation
import Testing
@testable import TradingCore

/// „Überhandeln“ nur ab dem üblichen Maß und erst ab 10 Tagen (Tim 05.10.2026); Revanche bei Scheinen nach Einsatz.
/// Erfundene Trades, Sollwerte von Hand.
private let uebUTC = TimeZone(secondsFromGMT: 0)!

/// 02.03.2026 00:00 UTC.
private let uebStart = Date(timeIntervalSince1970: 1_772_409_600)

/// Position `nummer` an Tag `tag` (0 = 02.03.2026), eröffnet 08:00 plus 10 Minuten je Nummer.
/// Mit `teil` ein Teilverkauf: gleiche Eröffnung, eigener Schluss.
private func uebTrade(tag: Int, nummer: Int, teil: Int? = nil) -> Trade {
    let auf = uebStart.addingTimeInterval(Double(tag) * 86_400 + 8 * 3_600 + Double(nummer) * 600)
    let zu = auf.addingTimeInterval(Double(60 + (teil ?? 0) * 60))
    let id = teil.map { "T\(tag)-\(nummer)-\($0)" } ?? "T\(tag)-\(nummer)"
    return Trade(id: id, symbol: "de40", side: .buy, lots: 1, openTime: auf, closeTime: zu,
                 openPrice: 100, closePrice: 101, profit: 1, produktart: .cfd)
}

/// Je Tag so viele Positionen wie angegeben, Tag für Tag ab dem 02.03.2026.
private func uebTage(_ anzahlen: [Int]) -> [Trade] {
    var trades: [Trade] = []
    for (tag, anzahl) in anzahlen.enumerated() {
        for nummer in 1...anzahl {
            trades.append(uebTrade(tag: tag, nummer: nummer))
        }
    }
    return trades
}

private func uebBefund(_ trades: [Trade], _ s: Fehlermuster.Schwellen = Fehlermuster.Schwellen()) -> Befund? {
    Fehlermuster.pruefe(trades, zeitzone: uebUTC, schwellen: s).first { $0.muster == .ueberhandeln }
}

@Test func ueberhandelnDreiTageOhneLimitKeinBefund() {
    // Tims Export: 22, 3 und 10 Positionen. Median 10, früher Grenze 12 und alle 22 Trades des ersten Tags.
    let trades = uebTage([22, 3, 10])
    #expect(uebBefund(trades) == nil)
    #expect(Fehlermuster.ueberhandelnGrenze(trades, zeitzone: uebUTC) == nil)
    let jeTag = Fehlermuster.tradesJeTag(trades, zeitzone: uebUTC)
    #expect(jeTag == [uebStart: 22, uebStart.addingTimeInterval(86_400): 3,
                      uebStart.addingTimeInterval(2 * 86_400): 10])
}

@Test func ueberhandelnDreiTageMitEigenemLimit() throws {
    var s = Fehlermuster.Schwellen()
    s.maxTradesProTag = 12
    let trades = uebTage([22, 3, 10])
    let befund = try #require(uebBefund(trades, s))
    // Nur die Positionen 13 bis 22 des ersten Tags, nicht die ersten zwölf.
    #expect(befund.trades == (13...22).map { "T0-\($0)" })
    #expect(befund.wert == 12)
    #expect(befund.stichprobe == 3)
    #expect(befund.netto == 10)
    #expect(Fehlermuster.ueberhandelnGrenze(trades, zeitzone: uebUTC, schwellen: s) == 12)
}

@Test func ueberhandelnZwoelfTageMitMedian() throws {
    // Elf Tage mit 5 Positionen, der fünfte Tag mit 9: Median 5, Grenze 7, nur Positionen 8 und 9.
    let anzahlen = [5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 5, 5]
    let trades = uebTage(anzahlen)
    let befund = try #require(uebBefund(trades))
    #expect(befund.trades == ["T4-8", "T4-9"])
    #expect(befund.wert == 7)
    #expect(befund.stichprobe == 12)
    #expect(Fehlermuster.ueberhandelnGrenze(trades, zeitzone: uebUTC) == 7)
}

@Test func ueberhandelnEigenesLimitVorMedian() throws {
    // Auch ab 10 Tagen hat ein eigenes Limit Vorrang: Grenze 4 statt 7, je Tag die 5. Position,
    // am fünften Tag die Positionen 5 bis 9: 11 + 5 = 16 Trades.
    var s = Fehlermuster.Schwellen()
    s.maxTradesProTag = 4
    let befund = try #require(uebBefund(uebTage([5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 5, 5]), s))
    #expect(befund.trades.count == 16)
    #expect(befund.trades.contains("T0-5") && !befund.trades.contains("T0-4"))
    #expect(befund.wert == 4)
}

@Test func ueberhandelnHalberMedianWirdAbgerundet() throws {
    // Zehn Tage 4, 4, 4, 4, 4, 5, 5, 5, 5, 7: Median 4,5, plus 2 ergibt 6,5; ab der 7. Position zu viel.
    let trades = uebTage([4, 4, 4, 4, 4, 5, 5, 5, 5, 7])
    let befund = try #require(uebBefund(trades))
    #expect(befund.trades == ["T9-7"])
    #expect(befund.wert == 6)
}

@Test func ueberhandelnTeilverkaufZaehltAlsEinePosition() throws {
    // Position 3 in zwei Teilen: vier Positionen, fünf Trades. Bei Limit 2 sind beide Teile von 3 und die 4 zu viel.
    let trades = [uebTrade(tag: 0, nummer: 1), uebTrade(tag: 0, nummer: 2),
                  uebTrade(tag: 0, nummer: 3, teil: 1), uebTrade(tag: 0, nummer: 3, teil: 2),
                  uebTrade(tag: 0, nummer: 4)]
    #expect(Fehlermuster.tradesJeTag(trades, zeitzone: uebUTC) == [uebStart: 4])
    var s = Fehlermuster.Schwellen()
    s.maxTradesProTag = 2
    let befund = try #require(uebBefund(trades, s))
    #expect(befund.trades == ["T0-3-1", "T0-3-2", "T0-4"])
    #expect(befund.wert == 2)
    s.maxTradesProTag = 4
    #expect(uebBefund(trades, s) == nil)
}

@Test func revancheBeiScheinenNachEinsatz() throws {
    func schein(_ id: String, _ symbol: String, kurs: Decimal, stueck: Decimal, _ auf: Double, _ zu: Double,
                ergebnis: Decimal) -> Trade {
        Trade(id: id, symbol: symbol, side: .buy, lots: stueck,
              openTime: uebStart.addingTimeInterval(9 * 3_600 + auf * 60),
              closeTime: uebStart.addingTimeInterval(9 * 3_600 + zu * 60),
              openPrice: kurs, closePrice: kurs, profit: ergebnis, produktart: .derivat)
    }
    // Schein A zu 3 € (700 Stück, Einsatz 2100), Schein B zu 47 € (45 Stück, Einsatz 2115).
    let trades = [
        schein("V1", "SCHEIN-B", kurs: 47, stueck: 45, 0, 30, ergebnis: -50),
        // 5 Min. nach dem Verlust, gleicher Einsatz wie sonst: keine Revanche, obwohl 700 Stück.
        schein("A1", "SCHEIN-A", kurs: 3, stueck: 700, 35, 60, ergebnis: 20),
        schein("V2", "SCHEIN-A", kurs: 3, stueck: 700, 120, 150, ergebnis: -30),
        // 10 Min. nach dem Verlust mit doppeltem Einsatz (4230): Revanche, obwohl nur 90 Stück.
        schein("B2", "SCHEIN-B", kurs: 47, stueck: 90, 160, 180, ergebnis: 5),
        schein("B3", "SCHEIN-B", kurs: 47, stueck: 45, 240, 270, ergebnis: 5),
    ]
    // Einsätze 2115, 2100, 2100, 4230, 2115: Median 2115. Nach Stück (Median 90) wäre es A1 statt B2.
    let befunde = Fehlermuster.pruefe(trades, zeitzone: uebUTC)
    let revanche = try #require(befunde.first { $0.muster == .revancheTrade })
    #expect(revanche.trades == ["B2"])
    #expect(Fehlermuster.groessenmass(trades[1]) == 2100)
    let cfd = Trade(id: "C", symbol: "de40", side: .buy, lots: 2, openTime: uebStart, closeTime: uebStart,
                    openPrice: 24_000, closePrice: 24_000, profit: 0, produktart: .cfd)
    #expect(Fehlermuster.groessenmass(cfd) == 2)
}
