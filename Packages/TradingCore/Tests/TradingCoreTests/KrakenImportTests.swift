import Foundation
import Testing
@testable import TradingCore

/// Synthetische Kraken-Exporte aus Fixtures/Krypto/Kraken/erzeuge.py, keine echten Konten.
/// Sollwerte unabhängig vom Swift-Code mit Python gerechnet (01.10.2026).
private func kraken(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Krypto/Kraken/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func kryptoWerteZahlen() throws {
    #expect(try KryptoWerte.zahl("€1,234.56", zeile: 1) == dez("1234.56"))
    #expect(try KryptoWerte.zahl("-€496.00", zeile: 1) == dez("-496"))
    #expect(try KryptoWerte.zahl("-", zeile: 1) == 0)
    #expect(try KryptoWerte.zahl("", zeile: 1) == 0)
    let binance = try KryptoWerte.zahlMitKuerzel("0.0100000000BTC", zeile: 1)
    #expect(binance.0 == dez("0.01"))
    #expect(binance.1 == "BTC")
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 3, text: "0.5")) {
        try KryptoWerte.zahlMitKuerzel("0.5", zeile: 3)
    }
}

@Test func kryptoWerteZeiten() throws {
    #expect(try KryptoWerte.utc("2026-03-02 09:05:00.1234", zeile: 1) == utc("2026-03-02T09:05:00Z"))
    #expect(try KryptoWerte.utc("2026-03-02 09:05:00 UTC", zeile: 1) == utc("2026-03-02T09:05:00Z"))
    // Sommerzeit: 10:00 in Wien mit +02:00 ist 08:00 UTC.
    #expect(try KryptoWerte.iso("2026-03-30T10:00:00+02:00", zeile: 1) == utc("2026-03-30T08:00:00Z"))
    #expect(try KryptoWerte.iso("2026-01-15T10:00:00.250+01:00", zeile: 1) == utc("2026-01-15T09:00:00Z"))
    #expect(try KryptoWerte.iso("2026-01-15T10:00:00Z", zeile: 1) == utc("2026-01-15T10:00:00Z"))
    #expect(try KryptoWerte.iso("2026-01-15T10:00:00-05:30", zeile: 1) == utc("2026-01-15T15:30:00Z"))
    #expect(throws: CSVImportFehler.ungueltigeZeit(zeile: 2, text: "2026-01-15T10:00:00 MEZ")) {
        try KryptoWerte.iso("2026-01-15T10:00:00 MEZ", zeile: 2)
    }
}

@Test func kryptoWerteKopfNachVorspann() throws {
    let text = "\u{FEFF}\"Transactions\"\r\n\"User\",\"x\"\r\n\"ID\",\"Timestamp\"\r\n\"1\",\"2\"\r\n"
    let ab = try #require(KryptoWerte.abKopf(text, erstesFeld: "ID"))
    #expect(ab.versatz == 2)
    #expect(CSVTabelle(text: ab.text).kopf == ["ID", "Timestamp"])
    #expect(KryptoWerte.abKopf("a,b\nc,d\n", erstesFeld: "ID") == nil)
}

@Test func krakenPaare() {
    let paare = ["XXBTZEUR", "SOL/EUR", "XETHZUSD", "XXDGZUSD", "ADAEUR", "XBTUSDT", "USDCEUR", "ETH.S/EUR"]
        .map { roh -> String in
            guard let p = KrakenCSV.paar(roh) else { return "-" }
            return "\(p.basis)/\(p.gegen)"
        }
    #expect(paare == ["BTC/EUR", "SOL/EUR", "ETH/USD", "DOGE/USD", "ADA/EUR", "BTC/USDT", "USDC/EUR", "ETH/EUR"])
    #expect(KrakenCSV.paar("FOOBAR") == nil)
}

@Test func krakenEinfach() throws {
    let text = try kraken("kraken_einfach")
    #expect(KrakenCSV.erkennt(text))
    #expect(!TradeRepublicCSV.erkennt(text))
    #expect(!ScalableCSV.erkennt(text))
    let k = try KrakenCSV.lies(text)
    #expect(k.hinweise.isEmpty)
    #expect(k.ausfuehrungen.map(\.kennung) == ["BTC/EUR", "SOL/EUR", "BTC/EUR", "SOL/EUR", "ETH/USD"])
    #expect(k.ausfuehrungen.map(\.seite) == [.buy, .buy, .sell, .sell, .buy])
    #expect(k.ausfuehrungen.map(\.betrag) == [dez("-600"), dez("-602.5"), dez("625"), dez("650"), dez("-1500")])
    #expect(k.ausfuehrungen.map(\.gebuehr) == [dez("-1.56"), dez("-1.5665"), dez("-1.625"), dez("-1.69"),
                                                dez("-3.9")])
    #expect(k.kassenwirkung == dez("-1437.8415"))
    let erste = try #require(k.ausfuehrungen.first)
    #expect(erste.id == "TKR001-AAAAA-000001")
    #expect(erste.name == "BTC")
    #expect(erste.waehrung == "EUR")
    #expect(erste.menge == dez("0.01"))
    #expect(erste.preis == 60000)
    #expect(erste.zeit == utc("2026-03-02T09:05:00Z"))
    #expect(erste.rohzeile.count == 24)
}

@Test func krakenFIFOJePaar() throws {
    let k = try KrakenCSV.lies(kraken("kraken_einfach"))
    let ergebnis = Positionsbildung.bilde(k.ausfuehrungen)
    #expect(ergebnis.trades.map(\.netProfit) == [dez("21.815"), dez("44.2435")])
    #expect(ergebnis.offen.map(\.kennung) == ["ETH/USD"])
}

@Test func krakenSonderfaelle() throws {
    let text = try kraken("kraken_sonderfaelle")
    #expect(KrakenCSV.erkennt(text))
    let k = try KrakenCSV.lies(text)
    #expect(k.ausfuehrungen.map(\.kennung) == ["DOGE/USD", "ADA/EUR", "BTC/USDT"])
    #expect(k.kassenwirkung == dez("297.4"))
    let hinweise = k.hinweise.map { "\($0.zeile) \($0.vorgang)" }
    #expect(hinweise == ["2 XETHXXBT buy", "3 XXBTZEUR buy", "7 XXBTZEUR settle"])
    #expect(k.hinweise.map(\.folge) == [.nichtVerbucht, .nichtVerbucht, .nichtVerbucht])
}

@Test func krakenFehlendeSpalte() {
    #expect(!KrakenCSV.erkennt("txid,pair,time\nT1,XXBTZEUR,2026-03-02 09:05:00\n"))
    #expect(throws: CSVImportFehler.fehlendeSpalte("ordertxid")) {
        try KrakenCSV.lies("txid,pair,time\nT1,XXBTZEUR,2026-03-02 09:05:00\n")
    }
}
