import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

/// Testdateien aus den TradingCore-Tests (pseudonymisiert oder synthetisch, nur gelesen).
private func kern(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

@discardableResult
private func mt4(_ journal: Journal, _ name: String) throws -> ImportErgebnis {
    try journal.importiereMT4(datei: kern("MT4/\(name).html"), dateiname: "\(name).html",
                              serverZeitzone: TimeZone(secondsFromGMT: 0)!)
}

@discardableResult
private func tr(_ journal: Journal, _ name: String) throws -> ImportErgebnis {
    try journal.importiereCSV(datei: kern("R2/\(name).csv"), dateiname: "\(name).csv", kontonummer: "Depot")
}

private func alleOffenen(_ journal: Journal, _ konto: Konto) throws -> [OpenPosition] {
    try journal.importe(konto: konto).flatMap { try journal.offenePositionen(importlauf: $0) }
}

private func nurKonto(_ journal: Journal) throws -> Konto {
    let konten = try journal.konten()
    try #require(konten.count == 1)
    return konten[0]
}

@Test func produktartKommtAusDerDatenbankZurueck() throws {
    let journal = try Journal.imSpeicher()
    try mt4(journal, "gbe-2025-05-14-daily")
    try mt4(journal, "gbe-2025-05-25-daily")
    let konto = try nurKonto(journal)
    let geschlossen = try journal.geschlossenePositionen(konto: konto)
    #expect(geschlossen.count == 4)
    #expect(geschlossen.allSatisfy { $0.produktart == .cfd })
    let offen = try alleOffenen(journal, konto)
    #expect(!offen.isEmpty)
    #expect(offen.allSatisfy { $0.produktart == .cfd })

    let depot = try Journal.imSpeicher()
    try tr(depot, "trade_republic_2026_komma")
    let gespeichert = try depot.kontobewegungen(konto: nurKonto(depot)).ausfuehrungen
    let original = try TradeRepublicCSV.lies(String(decoding: kern("R2/trade_republic_2026_komma.csv"),
                                                    as: UTF8.self)).ausfuehrungen
    let arten: [String: Produktart] = Dictionary(uniqueKeysWithValues: gespeichert.map { ($0.id, $0.produktart) })
    let soll: [String: Produktart] = Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0.produktart) })
    #expect(arten == soll)
    #expect(arten["tr-0002"] == .aktie)
}

@Test func unbekannteProduktartErgaenztDerNaechsteImport() throws {
    // Stand nach der Migration: alte Zeilen ohne Art.
    let journal = try Journal.imSpeicher()
    try tr(journal, "trade_republic_2026_komma")
    try journal.schreibe { try $0.execute(sql: "UPDATE ausfuehrung SET produktart = 'unbekannt'") }
    let zweiter = try tr(journal, "trade_republic_alt_semikolon")
    #expect(zweiter.csv.ausfuehrungenBekannt == 2)
    let arten = try journal.kontobewegungen(konto: nurKonto(journal)).ausfuehrungen.map(\.produktart)
    // tr-0002 und tr-0003 stehen in beiden Dateien und sind jetzt bekannt; die anderen bleiben offen.
    #expect(arten.filter { $0 != .unbekannt }.count == 2)
}

@Test func unbekannteProduktartBeiMT4ErgaenztDerMonatsauszug() throws {
    // Tagesauszug ohne Art gespeichert, danach der Monatsauszug mit denselben vier Trades als CFD.
    let journal = try Journal.imSpeicher()
    try mt4(journal, "gbe-2025-05-14-daily")
    try journal.schreibe { try $0.execute(sql: "UPDATE geschlossenePosition SET produktart = 'unbekannt'") }
    let monat = try mt4(journal, "gbe-2025-05-31-monthly")
    #expect(monat.geschlosseneBekannt == 4)
    #expect(try journal.geschlossenePositionen(konto: nurKonto(journal)).allSatisfy { $0.produktart == .cfd })
}

@Test func widersprechendeProduktartIstEineAbweichung() throws {
    let journal = try Journal.imSpeicher()
    try tr(journal, "trade_republic_2026_komma")
    try journal.schreibe {
        try $0.execute(sql: "UPDATE ausfuehrung SET produktart = 'krypto' WHERE vorgangId = 'tr-0002'")
    }
    #expect(throws: SpeicherFehler.abweichenderDatensatz(tickets: ["tr-0002"])) {
        try tr(journal, "trade_republic_alt_semikolon")
    }
    #expect(try journal.importe(konto: nurKonto(journal)).count == 1)
}

@Test func migrationSetztNurMT4AufCFD() throws {
    let ordner = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path

    do {
        let journal = try Journal(pfad: pfad)
        try mt4(journal, "gbe-2025-05-14-daily")
        try mt4(journal, "gbe-2025-05-25-daily")
        try journal.importiereXTB(datei: kern("XTB/xtb_einfach.xlsx"), dateiname: "xtb.xlsx")
        try tr(journal, "trade_republic_2026_komma")
        // Zurück auf den Stand vor v6: Spalte weg, Migration als nicht gelaufen markiert.
        try journal.schreibe { db in
            for tabelle in ["ausfuehrung", "geschlossenePosition", "offenePosition"] {
                try db.execute(sql: "ALTER TABLE \(tabelle) DROP COLUMN produktart")
            }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v6 Produktart'")
        }
    }

    let journal = try Journal(pfad: pfad)
    #expect(try journal.angewandteMigrationen().last == "v6 Produktart")
    let konten = try journal.konten()
    let gbe = try #require(konten.first { $0.broker == "GBE brokers Ltd." })
    let xtb = try #require(konten.first { $0.broker == "XTB" })
    let depot = try #require(konten.first { $0.broker == "Trade Republic" })
    let geschlossen = try journal.geschlossenePositionen(konto: gbe)
    #expect(geschlossen.count == 4)
    #expect(geschlossen.allSatisfy { $0.produktart == .cfd })
    let offen = try alleOffenen(journal, gbe)
    #expect(!offen.isEmpty)
    #expect(offen.allSatisfy { $0.produktart == .cfd })
    let xtbPositionen = try journal.geschlossenePositionen(konto: xtb)
    #expect(xtbPositionen.count == 2)
    #expect(xtbPositionen.allSatisfy { $0.produktart == .unbekannt })
    #expect(try journal.kontobewegungen(konto: depot).ausfuehrungen.allSatisfy { $0.produktart == .unbekannt })
}
