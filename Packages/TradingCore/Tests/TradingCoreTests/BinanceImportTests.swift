import Foundation
import Testing
@testable import TradingCore

/// Synthetische Binance-Exporte aus Fixtures/Krypto/Binance/erzeuge.py, keine echten Konten.
/// Sollwerte unabhängig vom Swift-Code mit Python gerechnet (02.10.2026).
private func binance(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Krypto/Binance/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func binanceEinfach() throws {
    let text = try binance("binance_einfach")
    #expect(BinanceCSV.erkennt(text))
    #expect(!BinanceCSV.istTransaktionsverlauf(text))
    #expect(!KrakenCSV.erkennt(text))
    #expect(!TradeRepublicCSV.erkennt(text))
    #expect(!ScalableCSV.erkennt(text))
    let b = try BinanceCSV.lies(text)
    #expect(b.hinweise.isEmpty)
    let kennungen: [String] = b.ausfuehrungen.map(\.kennung)
    #expect(kennungen == ["BTC/EUR", "ETH/USDT", "BTC/EUR", "ETH/USDT", "SOL/EUR", "SOL/EUR"])
    let seiten: [Side] = b.ausfuehrungen.map(\.seite)
    #expect(seiten == [.buy, .buy, .sell, .sell, .buy, .buy])
    let mengen: [Decimal] = b.ausfuehrungen.map(\.menge)
    #expect(mengen == [dez("0.00999"), dez("0.5"), dez("0.00999"), dez("0.5"), dez("2.5"), dez("2.5")])
    let betraege: [Decimal] = b.ausfuehrungen.map(\.betrag)
    #expect(betraege == [dez("-599.4"), dez("-1500"), dez("619.38"), dez("1600"), dez("-300"), dez("-300")])
    let gebuehren: [Decimal] = b.ausfuehrungen.map(\.gebuehr)
    #expect(gebuehren == [dez("-0.6"), dez("-1.5"), dez("-0.61938"), dez("-1.6"), dez("-0.3"), dez("-0.3")])
    #expect(b.kassenwirkung == dez("-484.93938"))
    let erste = try #require(b.ausfuehrungen.first)
    #expect(erste.name == "BTC")
    #expect(erste.waehrung == "EUR")
    #expect(erste.preis == 60000)
    #expect(erste.zeit == utc("2026-03-02T09:00:01Z"))
    #expect(erste.rohzeile.count == 7)
    // Teilausführungen in derselben Sekunde mit gleichen Werten bekommen eigene Kennungen.
    let ids: [String] = b.ausfuehrungen.map(\.id)
    #expect(Set(ids).count == 6)
    #expect(ids[5] == ids[4] + "#2")
}

@Test func binanceFIFOJePaar() throws {
    let b = try BinanceCSV.lies(binance("binance_einfach"))
    let ergebnis = Positionsbildung.bilde(b.ausfuehrungen)
    let netto: [Decimal] = ergebnis.trades.map(\.netProfit)
    #expect(netto == [dez("18.76062"), dez("96.9")])
    let offen: [String] = ergebnis.offen.map(\.kennung)
    #expect(offen == ["SOL/EUR", "SOL/EUR"])
}

@Test func binanceSonderfaelle() throws {
    let text = try binance("binance_sonderfaelle")
    #expect(BinanceCSV.erkennt(text))
    let b = try BinanceCSV.lies(text)
    let kennungen: [String] = b.ausfuehrungen.map(\.kennung)
    #expect(kennungen == ["BTC/EUR", "1INCH/USDT", "BNB/USDT", "XRP/EUR", "ETH/EUR"])
    let mengen: [Decimal] = b.ausfuehrungen.map(\.menge)
    #expect(mengen == [dez("0.00999"), dez("100"), dez("0.099925"), dez("100.1"), dez("0.1")])
    let betraege: [Decimal] = b.ausfuehrungen.map(\.betrag)
    #expect(betraege == [dez("619.38"), dez("-40"), dez("-59.955"), dez("50.05"), dez("-300")])
    let gebuehren: [Decimal] = b.ausfuehrungen.map(\.gebuehr)
    #expect(gebuehren == [0, dez("-0.04"), dez("-0.045"), dez("-0.05"), 0])
    #expect(b.kassenwirkung == dez("269.34"))
    let hinweise: [String] = b.hinweise.map { "\($0.zeile) \($0.vorgang)" }
    #expect(hinweise == ["2 ETHBTC BUY", "3 BTCEUR SELL Gebühr BNB", "7 BTCEUR BUY"])
    let folgen: [Importhinweis.Folge] = b.hinweise.map(\.folge)
    #expect(folgen == [.nichtVerbucht, .nichtVerbucht, .nichtVerbucht])
}

@Test func binanceGebuehrKuerzel() throws {
    #expect(try BinanceCSV.gebuehrLesen("0.04000000USDT", basis: "1INCH", gegen: "USDT", zeile: 1) == .gegen(dez("0.04")))
    #expect(try BinanceCSV.gebuehrLesen("0.1000000000INCH", basis: "1INCH", gegen: "USDT", zeile: 1) == .fremd("INCH"))
    #expect(try BinanceCSV.gebuehrLesen("0.5000000001INCH", basis: "1INCH", gegen: "USDT", zeile: 1) == .basis(dez("0.500000000")))
    #expect(try BinanceCSV.gebuehrLesen("0", basis: "BTC", gegen: "EUR", zeile: 1) == .keine)
    #expect(try BinanceCSV.gebuehrLesen("", basis: "BTC", gegen: "EUR", zeile: 1) == .keine)
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 4, text: "0.5")) {
        try BinanceCSV.gebuehrLesen("0.5", basis: "BTC", gegen: "EUR", zeile: 4)
    }
}

@Test func binanceTransaktionsverlaufAbgelehnt() throws {
    let text = try binance("binance_transaktionen")
    #expect(BinanceCSV.istTransaktionsverlauf(text))
    #expect(!BinanceCSV.erkennt(text))
    #expect(!BinanceCSV.erkennt(try binance("binance_einfach").replacingOccurrences(of: "Executed", with: "Filled")))
    let kopf = ["User ID", "Time", "Account", "Operation", "Coin", "Change", "Remark"]
    #expect(throws: CSVImportFehler.unbekanntesFormat(kopf: kopf)) { try BinanceCSV.lies(text) }
}

@Test func binanceFehlendeSpalte() {
    #expect(throws: CSVImportFehler.fehlendeSpalte("Executed")) {
        try BinanceCSV.lies("Date(UTC),Pair,Side,Price\n2026-03-02 09:00:01,BTCEUR,BUY,1\n")
    }
}
