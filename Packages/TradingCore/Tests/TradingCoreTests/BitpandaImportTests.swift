import Foundation
import Testing
@testable import TradingCore

/// Synthetische Bitpanda-Verläufe aus Fixtures/Krypto/Bitpanda/erzeuge.py, keine echten Konten.
/// Sollwerte unabhängig vom Swift-Code mit Python gerechnet (02.10.2026).
private func bitpanda(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Krypto/Bitpanda/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func bitpandaErkennung() throws {
    let neu = try bitpanda("bitpanda_neu")
    let alt = try bitpanda("bitpanda_alt")
    #expect(BitpandaCSV.erkennt(neu))
    #expect(BitpandaCSV.erkennt(alt))
    #expect(!KrakenCSV.erkennt(neu))
    #expect(!TradeRepublicCSV.erkennt(neu))
    #expect(!ScalableCSV.erkennt(neu))
    #expect(!BitpandaCSV.erkennt("txid,pair,time\nT1,XXBTZEUR,2026-03-02 09:05:00\n"))
}

@Test func bitpandaNeuMitSteuerspalte() throws {
    let k = try BitpandaCSV.lies(bitpanda("bitpanda_neu"))
    #expect(k.ausfuehrungen.map(\.id) == ["SYN-BP-0002", "SYN-BP-0003", "SYN-BP-0004", "SYN-BP-0005",
                                          "SYN-BP-0008"])
    #expect(k.ausfuehrungen.map(\.kennung) == ["BTC/EUR", "ETH/EUR", "ETH/EUR", "BTC/EUR", "ETH/EUR"])
    #expect(k.ausfuehrungen.map(\.seite) == [.buy, .buy, .buy, .sell, .sell])
    let betraege: [Decimal] = [dez("-495.05"), dez("-300"), dez("-2.1"), dez("519.8"), dez("75")]
    #expect(k.ausfuehrungen.map(\.betrag) == betraege)
    let gebuehren: [Decimal] = [dez("-4.95"), 0, 0, dez("-5.15"), dez("-1")]
    #expect(k.ausfuehrungen.map(\.gebuehr) == gebuehren)
    #expect(k.geldbewegungen.map(\.art) == [.einzahlung, .zinsen, .auszahlung])
    let geld: [Decimal] = [dez("1000"), dez("2.1"), dez("-200")]
    #expect(k.geldbewegungen.map(\.betrag) == geld)
    #expect(k.geldbewegungen[2].gebuehr == dez("-1"))
    #expect(k.kassenwirkung == dez("587.65"))

    let kauf = try #require(k.ausfuehrungen.first)
    #expect(kauf.name == "BTC")
    #expect(kauf.waehrung == "EUR")
    #expect(kauf.menge == dez("0.00825083"))
    #expect(kauf.preis == 60000)
    #expect(kauf.zeit == utc("2026-03-02T09:00:00Z"))
    #expect(kauf.rohzeile.count == 17)
    // Sommerzeit seit 29.03.2026: 10:00 mit +02:00 ist 08:00 UTC.
    #expect(k.ausfuehrungen[3].zeit == utc("2026-03-30T08:00:00Z"))
}

@Test func bitpandaHinweiseMitZeilenDerDatei() throws {
    let k = try BitpandaCSV.lies(bitpanda("bitpanda_neu"))
    let hinweise = k.hinweise.map { "\($0.zeile) \($0.vorgang)" }
    #expect(hinweise == ["10 ETH/EUR buy Gebühr BEST", "13 transfer(stake) ETH", "14 withdrawal ETH",
                         "15 ETH/EUR sell Steuer 0.20 EUR", "17 transfer SNX", "18 BTC/TRY buy"])
    #expect(k.hinweise.allSatisfy { $0.folge == .nichtVerbucht })
}

@Test func bitpandaFIFO() throws {
    let k = try BitpandaCSV.lies(bitpanda("bitpanda_neu"))
    let ergebnis = Positionsbildung.bilde(k.ausfuehrungen)
    #expect(ergebnis.trades.map(\.symbol) == ["BTC", "ETH"])
    #expect(ergebnis.trades.map(\.netProfit) == [dez("14.65"), dez("14")])
    #expect(ergebnis.offen.map(\.id) == ["SYN-BP-0003", "SYN-BP-0004"])
    #expect(ergebnis.ohneBestand.isEmpty)
}

@Test func bitpandaAltOhneSteuerspalte() throws {
    let k = try BitpandaCSV.lies(bitpanda("bitpanda_alt"))
    #expect(k.hinweise.isEmpty)
    #expect(k.ausfuehrungen.map(\.id) == ["SYN-BP-0002", "SYN-BP-0102"])
    #expect(k.ausfuehrungen.first?.rohzeile.count == 16)
    #expect(k.kassenwirkung == dez("1014.65"))
}

@Test func bitpandaFehlendeSpalte() {
    let text = "Hinweis\nTransaction ID,Timestamp,Transaction Type\nX,2026-03-02T09:00:00+01:00,buy\n"
    #expect(!BitpandaCSV.erkennt(text))
    #expect(throws: CSVImportFehler.fehlendeSpalte("In/Out")) { try BitpandaCSV.lies(text) }
    #expect(throws: CSVImportFehler.fehlendeSpalte("Transaction ID")) { try BitpandaCSV.lies("a,b\n1,2\n") }
}
