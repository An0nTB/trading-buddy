import Foundation
import Testing
import TradingCore
@testable import TradingStore

/// Krypto-Testdateien aus den TradingCore-Tests (synthetisch, nicht kopiert, nur gelesen).
private func datei(_ boerse: String, _ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/Krypto/\(boerse)/\(name).csv")
    return try Data(contentsOf: url)
}

private func d(_ text: String) -> Decimal { Decimal(string: text)! }
private func nachId<T>(_ liste: [T], _ id: (T) -> String) -> [T] { liste.sorted { id($0) < id($1) } }

/// Sollwerte der Kassenwirkung aus Stand-Doc 19 (unabhängig in Python gerechnet) und den TradingCore-Tests.
private let faelle: [(boerse: String, name: String, broker: String, importer: String, kasse: String)] = [
    ("Kraken", "kraken_einfach", "Kraken", Journal.krakenImporter, "-1437.8415"),
    ("Kraken", "kraken_sonderfaelle", "Kraken", Journal.krakenImporter, "297.4"),
    ("Binance", "binance_einfach", "Binance", Journal.binanceImporter, "-484.93938"),
    ("Binance", "binance_sonderfaelle", "Binance", Journal.binanceImporter, "269.34"),
    ("Coinbase", "coinbase_v4", "Coinbase", Journal.coinbaseImporter, "89.70"),
    ("Coinbase", "coinbase_v3", "Coinbase", Journal.coinbaseImporter, "-31.65"),
    ("Coinbase", "coinbase_v1", "Coinbase", Journal.coinbaseImporter, "425"),
    ("Bitpanda", "bitpanda_neu", "Bitpanda", Journal.bitpandaImporter, "587.65"),
    ("Bitpanda", "bitpanda_alt", "Bitpanda", Journal.bitpandaImporter, "1014.65"),
]

private func gelesen(_ boerse: String, _ text: String) throws -> Kontobewegungen {
    switch boerse {
    case "Kraken": return try KrakenCSV.lies(text)
    case "Binance": return try BinanceCSV.lies(text)
    case "Coinbase": return try CoinbaseCSV.lies(text)
    default: return try BitpandaCSV.lies(text)
    }
}

@Test(arguments: faelle.indices)
func kryptoexportWirdGespeichertUndKommtGleichZurueck(_ i: Int) throws {
    let fall = faelle[i]
    let journal = try Journal.imSpeicher()
    let inhalt = try datei(fall.boerse, fall.name)
    let ergebnis = try journal.importiereCSV(datei: inhalt, dateiname: "\(fall.name).csv", kontonummer: "Krypto")
    let original = try gelesen(fall.boerse, String(decoding: inhalt, as: UTF8.self))
    #expect(ergebnis.status == .gespeichert)
    #expect(ergebnis.csv.ausfuehrungenNeu == original.ausfuehrungen.count)
    #expect(ergebnis.csv.geldbewegungenNeu == original.geldbewegungen.count)
    #expect(ergebnis.csv.hinweise == original.hinweise.count)

    let konten = try journal.konten()
    try #require(konten.count == 1)
    #expect(konten[0].broker == fall.broker)
    let gespeichert = try journal.kontobewegungen(konto: konten[0])
    #expect(nachId(gespeichert.ausfuehrungen, \.id) == nachId(original.ausfuehrungen, \.id))
    #expect(nachId(gespeichert.geldbewegungen, \.id) == nachId(original.geldbewegungen, \.id))
    #expect(gespeichert.ausfuehrungen.allSatisfy { $0.produktart == .krypto })
    #expect(gespeichert.kassenwirkung == d(fall.kasse))

    let lauf = try #require(try journal.importe(konto: konten[0]).first)
    #expect(lauf.importer == fall.importer)
    #expect(try journal.importhinweise(importlauf: lauf) == original.hinweise)
}

@Test func gleicherKryptoexportZweimalErgibtKeineDubletten() throws {
    let journal = try Journal.imSpeicher()
    let inhalt = try datei("Binance", "binance_einfach")
    let erster = try journal.importiereCSV(datei: inhalt, dateiname: "a.csv", kontonummer: "Krypto")
    #expect(try journal.importiereCSV(datei: inhalt, dateiname: "b.csv", kontonummer: "Krypto").status
            == .dateiBereitsImportiert)
    // Andere Datei, gleiche Vorgänge (Leerzeile am Ende ändert nur den Fingerabdruck).
    let kopie = Data((String(decoding: inhalt, as: UTF8.self) + "\n\n").utf8)
    let zweiter = try journal.importiereCSV(datei: kopie, dateiname: "c.csv", kontonummer: "Krypto")
    #expect(zweiter.status == .gespeichert)
    #expect(zweiter.csv.ausfuehrungenNeu == 0)
    #expect(zweiter.csv.ausfuehrungenBekannt == erster.csv.ausfuehrungenNeu)
    let konto = try #require(try journal.konten().first)
    #expect(try journal.kontobewegungen(konto: konto).kassenwirkung == d("-484.93938"))
}

@Test func binanceTransaktionsverlaufWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let inhalt = try datei("Binance", "binance_transaktionen")
    #expect(throws: CSVImportFehler.self) {
        try journal.importiereCSV(datei: inhalt, dateiname: "t.csv", kontonummer: "Krypto")
    }
    #expect(try journal.konten().isEmpty)
}
