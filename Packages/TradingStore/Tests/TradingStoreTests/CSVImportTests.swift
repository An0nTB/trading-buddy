import Foundation
import Testing
import TradingCore
@testable import TradingStore

/// CSV-Testdateien aus den TradingCore-Tests (synthetisch, nicht kopiert, nur gelesen).
private func datei(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad).csv")
    return try Data(contentsOf: url)
}

private func text(_ pfad: String) throws -> String { String(decoding: try datei(pfad), as: UTF8.self) }
private func d(_ text: String) -> Decimal { Decimal(string: text)! }

@discardableResult
private func importiere(_ journal: Journal, _ pfad: String, konto: String = "Depot") throws -> ImportErgebnis {
    try journal.importiereCSV(datei: datei(pfad), dateiname: "\(pfad).csv", kontonummer: konto)
}

private func nachId<T>(_ liste: [T], _ id: (T) -> String) -> [T] { liste.sorted { id($0) < id($1) } }

@Test func tradeRepublicWirdGespeichertUndKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let ergebnis = try importiere(journal, "R2/trade_republic_2026_komma")
    #expect(ergebnis.status == .gespeichert)
    // Sollwerte aus R2_Testdaten/00_LIESMICH.md: 4 Ausführungen, 4 Geldbewegungen, Kassenwirkung 921,12.
    #expect(ergebnis.csv.ausfuehrungenNeu == 4)
    #expect(ergebnis.csv.geldbewegungenNeu == 4)

    let konto = try #require(try journal.konten().first)
    #expect(konto.broker == "Trade Republic")
    #expect(konto.kontonummer == "Depot")
    let gespeichert = try journal.kontobewegungen(konto: konto)
    let original = try TradeRepublicCSV.lies(text("R2/trade_republic_2026_komma"))
    #expect(nachId(gespeichert.ausfuehrungen, \.id) == nachId(original.ausfuehrungen, \.id))
    #expect(nachId(gespeichert.geldbewegungen, \.id) == nachId(original.geldbewegungen, \.id))
    #expect(gespeichert.kassenwirkung == d("921.12"))

    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.importer == Journal.tradeRepublicImporter)
    #expect(lauf.art == "transaktionen")
}

@Test func gleicheCSVZweimalErgibtKeineDubletten() throws {
    let journal = try Journal.imSpeicher()
    let erster = try importiere(journal, "R2/scalable_2026")
    let zweiter = try importiere(journal, "R2/scalable_2026")
    #expect(zweiter.status == .dateiBereitsImportiert)
    #expect(zweiter.importlaufId == erster.importlaufId)

    let konto = try #require(try journal.konten().first)
    let k = try journal.kontobewegungen(konto: konto)
    // R2-Sollwerte Scalable: 7 Zeilen, 1 storniert; 3 Ausführungen, 3 Geldbewegungen.
    #expect(k.ausfuehrungen.count == 3)
    #expect(k.geldbewegungen.count == 3)
    #expect(k.verworfen == ["SCALSYN0003"])
    #expect(try journal.importe(konto: konto).count == 1)
}

@Test func zweiExportvariantenDesselbenKontosUeberschneidenSich() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "R2/trade_republic_2026_komma")
    // Ältere Semikolon-Variante mit tr-0001 bis tr-0003: gleiche Vorgänge, andere Rohzeile.
    let zweiter = try importiere(journal, "R2/trade_republic_alt_semikolon")
    #expect(zweiter.status == .gespeichert)
    #expect(zweiter.csv.ausfuehrungenNeu == 0)
    #expect(zweiter.csv.ausfuehrungenBekannt == 2)
    #expect(zweiter.csv.geldbewegungenNeu == 0)
    #expect(zweiter.csv.geldbewegungenBekannt == 1)

    let k = try journal.kontobewegungen(konto: try #require(try journal.konten().first))
    #expect(k.ausfuehrungen.count == 4)
    #expect(k.geldbewegungen.count == 4)
    #expect(k.kassenwirkung == d("921.12"))
}

@Test func abweichenderVorgangBrichtAbUndAendertNichts() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "R2/trade_republic_2026_komma")
    let geaendert = try text("R2/trade_republic_alt_semikolon")
        .replacingOccurrences(of: ";440.00;", with: ";441.00;")
    #expect(throws: SpeicherFehler.abweichenderDatensatz(tickets: ["tr-0003"])) {
        try journal.importiereCSV(datei: Data(geaendert.utf8), dateiname: "geaendert.csv", kontonummer: "Depot")
    }
    let konto = try #require(try journal.konten().first)
    #expect(try journal.importe(konto: konto).count == 1)
    #expect(try journal.kontobewegungen(konto: konto).kassenwirkung == d("921.12"))
}

@Test func sonderfaelleUeberstehenDieDatenbank() throws {
    let journal = try Journal.imSpeicher()
    let ergebnis = try importiere(journal, "Sonderfaelle/trade_republic_sonderfaelle")
    let original = try TradeRepublicCSV.lies(text("Sonderfaelle/trade_republic_sonderfaelle"))
    #expect(ergebnis.csv.kapitalmassnahmenNeu == original.kapitalmassnahmen.count)
    #expect(ergebnis.csv.hinweise == original.hinweise.count)

    let konto = try #require(try journal.konten().first)
    let gespeichert = try journal.kontobewegungen(konto: konto)
    #expect(nachId(gespeichert.kapitalmassnahmen, \.id) == nachId(original.kapitalmassnahmen, \.id))
    #expect(gespeichert.hinweise == original.hinweise)
    // Sollwert aus den TradingCore-Tests (CSVSonderfaelleTests): Kassenwirkung 1054,87.
    #expect(gespeichert.kassenwirkung == d("1054.87"))

    // Positionsbildung aus der Datenbank ergibt dasselbe wie direkt aus der Datei.
    let ausDatenbank = Positionsbildung.bilde(gespeichert.ausfuehrungen, kapitalmassnahmen: gespeichert.kapitalmassnahmen)
    let ausDatei = Positionsbildung.bilde(original.ausfuehrungen, kapitalmassnahmen: original.kapitalmassnahmen)
    #expect(ausDatenbank.trades == ausDatei.trades)
    #expect(ausDatenbank.trades.map(\.netProfit) == [36, -1, d("-20.8"), 0])

    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(try journal.importhinweise(importlauf: lauf) == original.hinweise)
}

@Test func scalableEnglischMitKapitalmassnahmeUndHinweisen() throws {
    let journal = try Journal.imSpeicher()
    let ergebnis = try importiere(journal, "Sonderfaelle/scalable_englisch")
    let original = try ScalableCSV.lies(text("Sonderfaelle/scalable_englisch"))
    #expect(ergebnis.csv.verworfen == 1)
    let konto = try #require(try journal.konten().first)
    #expect(konto.broker == "Scalable Capital")
    let gespeichert = try journal.kontobewegungen(konto: konto)
    #expect(nachId(gespeichert.ausfuehrungen, \.id) == nachId(original.ausfuehrungen, \.id))
    #expect(nachId(gespeichert.geldbewegungen, \.id) == nachId(original.geldbewegungen, \.id))
    #expect(gespeichert.kapitalmassnahmen.map(\.vorgang) == ["Security transfer"])
    #expect(gespeichert.kassenwirkung == d("-484.439475"))
    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(TimeZone(identifier: lauf.serverZeitzone)?.identifier == "Europe/Berlin")
}

@Test func zweiKontenBeimSelbenBrokerBleibenGetrennt() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "R2/trade_republic_2026_komma", konto: "Depot A")
    // Andere Datei, damit der Fingerabdruck nicht greift; gleiche Vorgangs-IDs, anderes Konto.
    try importiere(journal, "R2/trade_republic_alt_semikolon", konto: "Depot B")
    let konten = try journal.konten()
    #expect(konten.map(\.kontonummer) == ["Depot A", "Depot B"])
    #expect(try journal.kontobewegungen(konto: konten[1]).ausfuehrungen.count == 2)
}

@Test func unbekanntesFormatWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    #expect(throws: CSVImportFehler.self) {
        try journal.importiereCSV(datei: Data("a;b\n1;2\n".utf8), dateiname: "x.csv", kontonummer: "Depot")
    }
    #expect(try journal.konten().isEmpty)
}

@Test func vorgangOhneKennungWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let ohneId = try text("R2/trade_republic_alt_semikolon").replacingOccurrences(of: ";tr-0002;", with: ";;")
    #expect(throws: SpeicherFehler.self) {
        try journal.importiereCSV(datei: Data(ohneId.utf8), dateiname: "ohne.csv", kontonummer: "Depot")
    }
    #expect(try journal.konten().isEmpty)
}

@Test func mt4UndCSVKommenSichNichtInDieQuere() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "R2/scalable_2026")
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/gbe-2025-06-04-daily.html")
    try journal.importiereMT4(datei: Data(contentsOf: url), dateiname: "gbe.html", serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    let konten = try journal.konten()
    #expect(konten.count == 2)
    let mt4 = try #require(konten.first { $0.broker == "GBE brokers Ltd." })
    #expect(try journal.kontobewegungen(konto: mt4).ausfuehrungen.isEmpty)
    #expect(try journal.geschlossenePositionen(konto: mt4).count == 1)
}
