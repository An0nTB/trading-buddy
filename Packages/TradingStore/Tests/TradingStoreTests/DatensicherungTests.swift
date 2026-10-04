import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

/// Testdateien aus den TradingCore-Tests (erfunden oder synthetisch, nur gelesen).
private func kern(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

private func ordner() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func gefuellt() throws -> Journal {
    let journal = try Journal.imSpeicher()
    try journal.importiereMT4(datei: kern("MT4/beispiel-2026-05-13-daily.html"), dateiname: "a.html",
                              serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    try journal.importiereCSV(datei: kern("R2/trade_republic_2026_komma.csv"), dateiname: "tr.csv",
                              kontonummer: "Depot")
    return journal
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let zeit = ISO8601DateFormatter().date(from: "2026-10-02T18:30:15Z")!

@Test func sicherungLaesstSichWiederherstellen() throws {
    let quelle = try gefuellt()
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let datei = try quelle.sichereInOrdner(dir, jetzt: zeit, zeitzone: utc)
    #expect(datei.lastPathComponent == "Journal-Sicherung-2026-10-02-183015.sqlite")

    let pruefung = Journal.pruefeSicherung(datei)
    #expect(pruefung.zustand == .aktuell)
    #expect(pruefung.laesstSichWiederherstellen)
    #expect(pruefung.migrationen == Schema.migrator.migrations)
    #expect(pruefung.fehlendeMigrationen.isEmpty && pruefung.unbekannteMigrationen.isEmpty)
    #expect(pruefung.konten == 2)
    #expect(pruefung.geschlossenePositionen == 4)
    #expect(pruefung.ausfuehrungen > 0)
    #expect(pruefung.letzterImport != nil)
    #expect(pruefung.letzterTrade != nil)
    #expect(throws: SpeicherFehler.ungueltigerWert("\(datei.lastPathComponent) gibt es schon")) {
        try quelle.sichere(nach: datei)
    }

    // Wiederherstellen ersetzt den ganzen Inhalt, auch was nur im Ziel stand.
    let ziel = try Journal.imSpeicher()
    try ziel.speichereMerklisteneintrag(Merklisteneintrag(id: "x", begriff: "Nur im Ziel", erstellt: zeit))
    let ergebnis = try ziel.stelleWiederHer(aus: datei)
    #expect(ergebnis == pruefung)
    #expect(try ziel.merkliste().isEmpty)
    #expect(try ziel.konten() == quelle.konten())
    let konto = try #require(ziel.konten().first { $0.broker != "Trade Republic" })
    #expect(try ziel.geschlossenePositionen(konto: konto).count == 4)
}

@Test func sichereInOrdnerBehaeltNurDieNeuesten() throws {
    let journal = try gefuellt()
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let fremd = dir.appendingPathComponent("Journal-Sicherung-Notiz.txt")
    try Data("bleibt".utf8).write(to: fremd)
    for tag in 0..<3 {
        try journal.sichereInOrdner(dir, jetzt: zeit.addingTimeInterval(Double(tag) * 86_400), zeitzone: utc,
                                    behalte: 2)
    }
    #expect(try Journal.sicherungen(in: dir).map(\.lastPathComponent) == [
        "Journal-Sicherung-2026-10-04-183015.sqlite", "Journal-Sicherung-2026-10-03-183015.sqlite",
    ])
    #expect(FileManager.default.fileExists(atPath: fremd.path))
    // Keine halbfertigen Dateien bleiben liegen.
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 3)
    #expect(try Journal.sicherungen(in: dir.appendingPathComponent("fehlt")).isEmpty)
    #expect(throws: SpeicherFehler.ungueltigerWert("Mindestens eine Sicherung behalten")) {
        try journal.sichereInOrdner(dir, behalte: 0)
    }
}

@Test func aeltereSicherungWirdBeimWiederherstellenMigriert() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let datei = dir.appendingPathComponent("alt.sqlite")
    try gefuellt().sichere(nach: datei)
    // Stand vor v9: Tabelle und Eintrag der Migration fehlen.
    let alt = try DatabaseQueue(path: datei.path)
    try alt.write { db in
        try db.execute(sql: "DROP TABLE merkliste")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v9 Merkliste'")
    }
    try alt.close()

    let pruefung = Journal.pruefeSicherung(datei)
    #expect(pruefung.zustand == .aelter)
    #expect(pruefung.fehlendeMigrationen == ["v9 Merkliste"])
    let ziel = try Journal.imSpeicher()
    #expect(try ziel.stelleWiederHer(aus: datei).zustand == .aktuell)
    #expect(try ziel.angewandteMigrationen() == Schema.migrator.migrations)
    try ziel.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "AAPL", erstellt: zeit))
}

@Test func neuereSicherungWirdAbgelehnt() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let datei = dir.appendingPathComponent("neu.sqlite")
    try gefuellt().sichere(nach: datei)
    let neu = try DatabaseQueue(path: datei.path)
    try neu.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99 Zukunft')") }
    try neu.close()

    let pruefung = Journal.pruefeSicherung(datei)
    #expect(pruefung.zustand == .neuer)
    #expect(pruefung.unbekannteMigrationen == ["v99 Zukunft"])
    #expect(!pruefung.laesstSichWiederherstellen)
    let ziel = try Journal.imSpeicher()
    try ziel.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "bleibt", erstellt: zeit))
    #expect(throws: SpeicherFehler.ungueltigerWert("Sicherung stammt aus einer neueren App-Version")) {
        try ziel.stelleWiederHer(aus: datei)
    }
    #expect(try ziel.merkliste().map(\.begriff) == ["bleibt"])
}

@Test func kaputteSicherungWirdErkannt() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(Journal.pruefeSicherung(dir.appendingPathComponent("fehlt.sqlite")).hinweis == "Datei fehlt")

    let muell = dir.appendingPathComponent("muell.sqlite")
    try Data(repeating: 0x41, count: 4096).write(to: muell)
    #expect(Journal.pruefeSicherung(muell).zustand == .beschaedigt)

    let fremd = dir.appendingPathComponent("fremd.sqlite")
    let andere = try DatabaseQueue(path: fremd.path)
    try andere.write { try $0.execute(sql: "CREATE TABLE notiz (text TEXT)") }
    try andere.close()
    #expect(Journal.pruefeSicherung(fremd) == .beschaedigt("Keine Journal-Datenbank"))

    let ziel = try Journal.imSpeicher()
    #expect(throws: SpeicherFehler.ungueltigerWert("Sicherung ist beschädigt: Keine Journal-Datenbank")) {
        try ziel.stelleWiederHer(aus: fremd)
    }
}

@Test func sicherungsnamenFolgenEinemMuster() {
    #expect(Journal.sicherungsname(zeit, zeitzone: utc) == "Journal-Sicherung-2026-10-02-183015.sqlite")
    #expect(Journal.sicherungsname(zeit, zeitzone: TimeZone(identifier: "Europe/Berlin")!)
        == "Journal-Sicherung-2026-10-02-203015.sqlite")
    #expect(Journal.istSicherungsname("Journal-Sicherung-2026-10-02-183015.sqlite"))
    #expect(!Journal.istSicherungsname("Journal-Sicherung-2026-10-02.sqlite"))
    #expect(!Journal.istSicherungsname(".Journal-Sicherung-2026-10-02-183015.sqlite.teil"))
    #expect(!Journal.istSicherungsname("Journal-Sicherung-Notiz.txt"))
}
