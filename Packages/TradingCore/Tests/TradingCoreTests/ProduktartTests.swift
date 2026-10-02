import Foundation
import Testing
@testable import TradingCore

/// Produktart aus den vorhandenen Testdateien. Sollwerte aus der Spalte `asset_class`
/// der synthetischen Trade-Republic-Dateien abgelesen (Python, 02.10.2026).
private func produktDatei(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func produktartBezeichnungenBleibenStabil() {
    // Rohwerte landen im Speicher und im Export; ändern heißt migrieren.
    let roh: [String] = Produktart.allCases.map(\.rawValue)
    #expect(roh == ["aktie", "fonds", "anleihe", "derivat", "cfd", "krypto", "sonstiges", "unbekannt"])
    #expect(Produktart(tradeRepublic: "STOCK") == .aktie)
    #expect(Produktart(tradeRepublic: "fund") == .fonds)
    #expect(Produktart(tradeRepublic: "BOND") == .anleihe)
    #expect(Produktart(tradeRepublic: "DERIVATIVE") == .derivat)
    #expect(Produktart(tradeRepublic: "CRYPTO") == .krypto)
    #expect(Produktart(tradeRepublic: "PRIVATE_EQUITY") == .sonstiges)
    #expect(Produktart(tradeRepublic: "") == .unbekannt)
}

@Test func tradeRepublicNenntProduktart() throws {
    let k = try TradeRepublicCSV.lies(produktDatei("R2/trade_republic_2026_komma.csv"))
    let arten: [Produktart] = k.ausfuehrungen.map(\.produktart)
    #expect(arten == [.aktie, .aktie, .krypto, .fonds])
    let ergebnis = Positionsbildung.bilde(k.ausfuehrungen)
    let gehandelt: [Produktart] = ergebnis.trades.map(\.produktart)
    #expect(gehandelt == [.aktie])
    let offen: [Produktart] = ergebnis.offen.map(\.produktart)
    #expect(offen == [.krypto, .fonds])
}

@Test func tradeRepublicSonderfaelleProduktart() throws {
    let k = try TradeRepublicCSV.lies(produktDatei("Sonderfaelle/trade_republic_sonderfaelle.csv"))
    let arten: [Produktart] = k.ausfuehrungen.map(\.produktart)
    #expect(arten == [.aktie, .aktie, .anleihe, .anleihe, .derivat, .derivat, .aktie, .fonds, .fonds])
}

@Test func scalableBleibtUnbekannt() throws {
    let k = try ScalableCSV.lies(produktDatei("R2/scalable_2026.csv"))
    #expect(!k.ausfuehrungen.isEmpty)
    let unbekannt = k.ausfuehrungen.filter { $0.produktart == .unbekannt }
    #expect(unbekannt.count == k.ausfuehrungen.count)
}

@Test func metaTraderIstCFD() throws {
    let a = try MT4Statement.parse(html: produktDatei("MT4/gbe-2025-05-14-daily.html"),
                                   serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    #expect(!a.closedPositions.isEmpty)
    let geschlossen = a.closedPositions.filter { $0.produktart == .cfd }
    #expect(geschlossen.count == a.closedPositions.count)
    let offen = a.openPositions.filter { $0.produktart == .cfd }
    #expect(offen.count == a.openPositions.count)
    let trades = a.closedPositions.map { Trade($0) }.filter { $0.produktart == .cfd }
    #expect(trades.count == a.closedPositions.count)
}

@Test func krakenIstKrypto() throws {
    let k = try KrakenCSV.lies(produktDatei("Krypto/Kraken/kraken_einfach.csv"))
    #expect(!k.ausfuehrungen.isEmpty)
    let krypto = k.ausfuehrungen.filter { $0.produktart == .krypto }
    #expect(krypto.count == k.ausfuehrungen.count)
    let trades = Positionsbildung.bilde(k.ausfuehrungen).trades
    #expect(!trades.isEmpty)
    let kryptoTrades = trades.filter { $0.produktart == .krypto }
    #expect(kryptoTrades.count == trades.count)
}

@Test func positionsbildungNimmtArtDesKaufsWennVerkaufSchweigt() {
    let start = Date(timeIntervalSince1970: 1_767_225_600)
    let kauf = Ausfuehrung(id: "k", zeit: start, kennung: "X", name: "X", seite: .buy, menge: 1, preis: 10,
                           betrag: -10, waehrung: "EUR", produktart: .fonds)
    let verkauf = Ausfuehrung(id: "v", zeit: start.addingTimeInterval(86_400), kennung: "X", name: "X", seite: .sell,
                              menge: 1, preis: 12, betrag: 12, waehrung: "EUR")
    let trade = Positionsbildung.bilde([kauf, verkauf]).trades.first
    #expect(trade?.produktart == .fonds)
    #expect(trade?.netProfit == 2)
}
