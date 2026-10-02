import Foundation
import Testing
@testable import TradingCore

/// Synthetische Coinbase-Berichte (Köpfe v4, v3, v1 laut CoinTaxman src/book.py, 2026), keine echten Konten.
/// Sollwerte unabhängig vom Swift-Code mit Python aus den Dateien gerechnet (02.10.2026).
private func coinbase(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Krypto/Coinbase/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func zeitpunkt(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func coinbaseV4KaeufeVerkaeufeUndUmtausch() throws {
    let text = try coinbase("coinbase_v4")
    #expect(CoinbaseCSV.erkennt(text))
    #expect(!KrakenCSV.erkennt(text))
    #expect(!TradeRepublicCSV.erkennt(text))
    let k = try CoinbaseCSV.lies(text)

    let ids: [String] = k.ausfuehrungen.map { String($0.id.suffix(7)) }
    #expect(ids == ["0000001", "0000002", "0000003", "0000004", "0000005", "05-ziel",
                    "0000006", "06-ziel", "0000008", "0000009", "0000010"])
    let seiten: [Side] = k.ausfuehrungen.map(\.seite)
    #expect(seiten == [.buy, .sell, .buy, .sell, .sell, .buy, .sell, .buy, .buy, .buy, .buy])
    let kennungen: [String] = k.ausfuehrungen.map(\.kennung)
    #expect(kennungen == ["BTC/EUR", "BTC/EUR", "ETH/EUR", "ETH/EUR", "ETH/EUR", "USDC/EUR",
                          "SOL/EUR", "USDC/EUR", "ETH/EUR", "SOL/EUR", "GRT/EUR"])
    #expect(k.ausfuehrungen.allSatisfy { $0.waehrung == "EUR" && $0.menge > 0 })

    let kauf = k.ausfuehrungen[0]
    #expect(kauf.zeit == zeitpunkt("2026-03-02T09:00:00Z"))
    #expect(kauf.name == "BTC")
    #expect(kauf.menge == dez("0.008"))
    #expect(kauf.preis == 60000)
    #expect(kauf.betrag == -480)
    #expect(kauf.gebuehr == -9)
    #expect(kauf.rohzeile.count == 11)

    // v4 schreibt Verkäufe negativ; Richtung kommt aus der Vorgangsart.
    let verkauf = k.ausfuehrungen[1]
    #expect(verkauf.menge == dez("0.008"))
    #expect(verkauf.betrag == 496)
    #expect(verkauf.gebuehr == -9)
    #expect(k.ausfuehrungen[2].betrag == -1200)
    #expect(k.ausfuehrungen[2].preis == 2400)
    #expect(k.ausfuehrungen[3].betrag == 500)

    // Convert: Verkauf zum Subtotal, Kauf des Ziels zu Subtotal minus Gebühr, Kasse netto 0.
    #expect(k.ausfuehrungen[4].betrag == 250)
    #expect(k.ausfuehrungen[4].gebuehr == dez("-3.70"))
    let ziel = k.ausfuehrungen[5]
    #expect(ziel.name == "USDC")
    #expect(ziel.menge == dez("246.30"))
    #expect(ziel.betrag == dez("-246.30"))
    #expect(ziel.preis == 1)
    #expect(ziel.gebuehr == 0)
    #expect(k.ausfuehrungen[7].menge == dez("1481.5"))
    #expect(k.ausfuehrungen[7].betrag == dez("-1481.50"))
}

@Test func coinbaseV4ErtraegeGeldUndHinweise() throws {
    let k = try CoinbaseCSV.lies(try coinbase("coinbase_v4"))
    let arten: [Geldbewegung.Art] = k.geldbewegungen.map(\.art)
    #expect(arten == [.zinsen, .zinsen, .sonstiges, .einzahlung, .auszahlung])
    let betraege: [Decimal] = k.geldbewegungen.map(\.betrag)
    #expect(betraege == [1, dez("7.50"), 3, 1000, -200])
    #expect(k.geldbewegungen[0].kennung == "ETH/EUR")
    #expect(k.geldbewegungen[0].id.hasSuffix("0000008-ertrag"))
    #expect(k.geldbewegungen[4].gebuehr == dez("-1.50"))
    #expect(k.ausfuehrungen[8].betrag == -1)
    #expect(k.ausfuehrungen[10].preis == dez("0.15"))

    // Zeilen der Originaldatei: Vorspann aus Leerzeile, „Transactions“ und Nutzerzeile, Kopf in Zeile 4.
    #expect(k.hinweise == [
        Importhinweis(zeile: 11, vorgang: "Convert ADA", folge: .nichtVerbucht),
        Importhinweis(zeile: 17, vorgang: "Send BTC", folge: .nichtVerbucht),
        Importhinweis(zeile: 18, vorgang: "Receive ETH", folge: .nichtVerbucht),
        Importhinweis(zeile: 19, vorgang: "Retail Staking Transfer ETH", folge: .nichtVerbucht),
    ])
    #expect(k.kassenwirkung == dez("89.70"))
}

@Test func coinbaseAeltereKoepfe() throws {
    let v3 = try coinbase("coinbase_v3")
    #expect(CoinbaseCSV.erkennt(v3))
    let k3 = try CoinbaseCSV.lies(v3)
    #expect(k3.ausfuehrungen.count == 3)
    #expect(k3.ausfuehrungen[0].zeit == zeitpunkt("2022-01-10T08:00:00Z"))
    #expect(k3.ausfuehrungen[0].id == "coinbase-2022-01-10T08:00:00Z-Buy-BTC-0.01")
    #expect(k3.ausfuehrungen[1].betrag == 380)
    #expect(k3.ausfuehrungen[2].kennung == "XLM/EUR")
    let arten3: [Geldbewegung.Art] = k3.geldbewegungen.map(\.art)
    #expect(arten3 == [.sonstiges])
    #expect(k3.hinweise == [Importhinweis(zeile: 12, vorgang: "Send XLM", folge: .nichtVerbucht)])
    #expect(k3.kassenwirkung == dez("-31.65"))

    // v1: Währung nur im Spaltennamen, fehlendes Subtotal aus Menge mal Preis.
    let k1 = try CoinbaseCSV.lies(try coinbase("coinbase_v1"))
    let waehrungen1: [String] = k1.ausfuehrungen.map(\.waehrung)
    #expect(waehrungen1 == ["EUR", "EUR"])
    #expect(k1.ausfuehrungen[0].betrag == -750)
    #expect(k1.ausfuehrungen[0].gebuehr == -10)
    #expect(k1.ausfuehrungen[1].seite == .sell)
    #expect(k1.hinweise.isEmpty)
    #expect(k1.kassenwirkung == 425)
}

@Test func coinbaseNotizzahlenUndFehlerfaelle() throws {
    #expect(CoinbaseCSV.notizzahl("1,481.5") == dez("1481.5"))
    #expect(CoinbaseCSV.notizzahl("1,234,567") == 1_234_567)
    #expect(CoinbaseCSV.notizzahl("0,123") == nil)
    #expect(CoinbaseCSV.notizzahl("0,5") == dez("0.5"))
    #expect(CoinbaseCSV.notizzahl("24.63") == dez("24.63"))
    #expect(CoinbaseCSV.umtausch("Converted 0.1 ETH to 246.30 USDC", von: "BTC")?.menge == nil)
    #expect(CoinbaseCSV.umtausch("Converted 0.1 ETH into 246.30 USDC", von: "ETH")?.menge == nil)

    let ohneWaehrung = "Timestamp,Transaction Type,Asset,Quantity Transacted,Price at Transaction,Subtotal,Fees,Notes\n"
    #expect(!CoinbaseCSV.erkennt(ohneWaehrung))
    #expect(throws: CSVImportFehler.fehlendeSpalte("Price Currency")) { try CoinbaseCSV.lies(ohneWaehrung) }
    #expect(throws: CSVImportFehler.unbekanntesFormat(kopf: ["a", "b"])) { try CoinbaseCSV.lies("a,b\n1,2\n") }
}
