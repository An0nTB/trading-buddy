import Foundation
import Testing
@testable import TradingCore

/// Synthetische Dateien, deren Zeilen echten Exporten nachgebaut sind (Fixtures/Sonderfaelle/00_LIESMICH.md).
/// Sollwerte von Hand und mit Python gerechnet (01.10.2026).
private func datei(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Sonderfaelle/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func tradeRepublicSonderfaelleBrechenNichtAb() throws {
    let k = try TradeRepublicCSV.lies(datei("trade_republic_sonderfaelle"))
    #expect(k.ausfuehrungen.map(\.id) == ["syn-0002", "syn-0004", "syn-0005", "syn-0007", "syn-0008", "syn-0010",
                                          "syn-0019", "syn-0020", "syn-0021"])
    #expect(k.geldbewegungen.map(\.art) == [.einzahlung, .dividende, .dividende, .dividende, .auszahlung,
                                            .sonstiges, .sonstiges, .sonstiges])
    #expect(k.kapitalmassnahmen.map(\.art) == [.split, .ausbuchung, .ausbuchung, .unbekannt])
    #expect(k.hinweise == [
        Importhinweis(zeile: 17, vorgang: "CASH NEUE_ART", folge: .alsSonstiges),
        Importhinweis(zeile: 18, vorgang: "CORPORATE_ACTION SPINOFF", folge: .nichtVerbucht),
        Importhinweis(zeile: 19, vorgang: "TRADING TRANSFER_IN", folge: .nichtVerbucht),
        Importhinweis(zeile: 23, vorgang: "MARGIN INTEREST", folge: .alsSonstiges),
    ])
    // Nichts geht verloren: Summe aus amount, fee und tax aller verbuchten Zeilen.
    #expect(k.kassenwirkung == dez("1054.87"))
    // Einzahlung per Karte: Gebühr getrennt vom Betrag.
    #expect(k.geldbewegungen[0].betrag == dez("1002.45"))
    #expect(k.geldbewegungen[0].gebuehr == dez("-2.45"))
    // Dividenden-Korrektur bleibt als negative Dividende stehen.
    #expect(k.geldbewegungen[2].betrag == -2)
    #expect(k.kapitalmassnahmen[0].menge == 9)
    // Fälligkeit aus einer Geldzeile wird zum Verkauf.
    let faelligkeit = k.ausfuehrungen[3]
    #expect(faelligkeit.seite == .sell)
    #expect(faelligkeit.menge == 20)
    #expect(faelligkeit.preis == 1)
}

@Test func positionsbildungMitSplitAusbuchungUndAltbestand() throws {
    let k = try TradeRepublicCSV.lies(datei("trade_republic_sonderfaelle"))
    let ergebnis = Positionsbildung.bilde(k.ausfuehrungen, kapitalmassnahmen: k.kapitalmassnahmen)
    #expect(ergebnis.trades.map(\.id) == ["syn-0004", "syn-0007", "syn-0010", "syn-0020"])
    #expect(ergebnis.trades.map(\.netProfit) == [36, -1, dez("-20.8"), 0])

    // Split 10:1: ein Kauf zu 900 wird zu zehn Stück zu 90, Einstand bleibt 900.
    let split = ergebnis.trades[0]
    #expect(split.lots == 10)
    #expect(split.openPrice == 90)
    #expect(split.closePrice == 95)
    #expect(split.profit == 50)
    #expect(split.taxes == -12)
    #expect(split.openTime == utc("2026-01-06T09:00:00Z"))

    // Optionsschein: Ausübung bucht aus, TILG bringt 0,20 € Erlös.
    #expect(ergebnis.trades[2].profit == dez("-19.8"))
    // Verkauf und Kauf am selben Tag ohne Uhrzeit: erst Kauf, dann Verkauf.
    #expect(ergebnis.trades[3].profit == 2)
    // Verkauf ohne Kauf im Export: kein Trade, aber sichtbar.
    #expect(ergebnis.ohneBestand.map(\.id) == ["syn-0019"])
    #expect(ergebnis.ohneBestand[0].menge == 5)
    #expect(ergebnis.offen.isEmpty)
}

@Test func teilweiserAltbestand() throws {
    func ausfuehrung(_ id: String, tag: Double, _ seite: Side, _ menge: Decimal, _ betrag: Decimal) -> Ausfuehrung {
        Ausfuehrung(id: id, zeit: Date(timeIntervalSince1970: tag * 86_400), kennung: "X", name: "X", seite: seite,
                    menge: menge, preis: abs(betrag / menge), betrag: betrag, waehrung: "EUR")
    }
    let ergebnis = Positionsbildung.bilde([
        ausfuehrung("k1", tag: 0, .buy, 2, -20),
        ausfuehrung("v1", tag: 1, .sell, 5, 60),
    ])
    let trade = try #require(ergebnis.trades.first)
    #expect(trade.lots == 2)
    #expect(trade.profit == 4)
    #expect(ergebnis.ohneBestand.first?.menge == 3)
    #expect(ergebnis.ohneBestand.first?.betrag == 36)
}

@Test func scalableEnglischeVorgangsarten() throws {
    let text = try datei("scalable_englisch")
    #expect(ScalableCSV.erkennt(text))
    let k = try ScalableCSV.lies(text)
    #expect(k.verworfen == ["SCALSYN1005"])
    #expect(k.ausfuehrungen.map(\.id) == ["SCALSYN1004", "SCALSYN1003", "SCALSYN1002"])
    #expect(k.ausfuehrungen.map(\.seite) == [.sell, .buy, .buy])
    #expect(k.ausfuehrungen[2].sparplan)
    #expect(k.geldbewegungen.map(\.art) == [.sonstiges, .dividende, .auszahlung, .einzahlung, .steuer])
    #expect(k.geldbewegungen[1].kennung == "IE000SYN0011")
    #expect(k.kapitalmassnahmen.map(\.vorgang) == ["Security transfer"])
    #expect(k.hinweise == [
        Importhinweis(zeile: 2, vorgang: "Cash Bonus", folge: .alsSonstiges),
        Importhinweis(zeile: 3, vorgang: "Security transfer", folge: .nichtVerbucht),
    ])
    #expect(k.kassenwirkung == dez("-484.439475"))
    // Gebühr ohne Minus in der Datei ist trotzdem ein Abzug.
    #expect(k.ausfuehrungen[0].gebuehr == dez("-0.99"))
    // 02:00 Sommerzeit und 01:00 Winterzeit sind Mitternacht UTC: nur Datum.
    #expect(k.geldbewegungen.allSatisfy(\.nurDatum))
    #expect(k.geldbewegungen[4].zeit == utc("2024-01-19T00:00:00Z"))
    #expect(!k.ausfuehrungen[0].nurDatum)
    #expect(k.ausfuehrungen[0].zeit == utc("2025-09-03T13:45:10Z"))

    let trade = try #require(Positionsbildung.bilde(k.ausfuehrungen).trades.first)
    #expect(trade.profit == dez("60.8"))
    #expect(trade.commission == dez("-1.98"))
    #expect(trade.taxes == dez("-15.82"))
    #expect(trade.netProfit == 43)
}
