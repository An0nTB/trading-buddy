import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

// Geprüfte Kopie vor einer Migration (App-Update beim Tester, Doc 11, Entscheidung 51).

private func ordner() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("VorMigration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let zeit = ISO8601DateFormatter().date(from: "2026-10-05T15:30:00Z")!
private let v8 = "v8 Tagesnotiz, verpasste Trades, Bilder"

/// Journal-Datei, wie sie eine App-Version mit Stand `stand` hinterlassen hätte, mit einem Konto.
private func alteDatei(_ pfad: String, stand: String = v8) throws {
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: stand)
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (broker, kontonummer, kontoname, waehrung) VALUES ('Beispiel Broker', '1', 'Test', 'EUR')
            """)
    }
    try alt.close()
}

/// Migrationen in der Datei, ohne sie über `Journal` zu öffnen.
private func migrationen(_ pfad: String) throws -> [String] {
    var konfiguration = Configuration()
    konfiguration.readonly = true
    let queue = try DatabaseQueue(path: pfad, configuration: konfiguration)
    defer { try? queue.close() }
    return try queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
}

private func nachV8() -> [String] {
    Array(Schema.migrator.migrations.drop { $0 != v8 }.dropFirst())
}

@Test func alteDateiWirdVorDerMigrationKopiert() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    try alteDatei(pfad)

    let journal = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(try journal.angewandteMigrationen() == Schema.migrator.migrations)
    #expect(try journal.konten().count == 1)

    let kopien = Journal.kopienVorMigration(pfad: pfad)
    #expect(kopien.map(\.lastPathComponent) == ["journal.vor-v9-2026-10-05-153000.sqlite"])
    let kopie = try #require(kopien.first)
    let pruefung = Journal.pruefeSicherung(kopie)
    #expect(pruefung.zustand == .aelter)
    #expect(pruefung.fehlendeMigrationen == nachV8())
    #expect(pruefung.konten == 1)
    #expect(try migrationen(kopie.path).last == v8)
    // Keine Reste der Zwischendatei.
    let namen = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(!namen.contains { $0.hasSuffix(".teil") })
}

@Test func aktuelleUndNeueDateiBrauchenKeineKopie() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    // Neue Datei: angelegt und migriert, nichts zu sichern.
    _ = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(Journal.kopienVorMigration(pfad: pfad).isEmpty)
    // Aktuelle Datei erneut geöffnet: nichts fehlt, keine Kopie.
    _ = try Journal(pfad: pfad, jetzt: zeit.addingTimeInterval(60), zeitzone: utc)
    #expect(Journal.kopienVorMigration(pfad: pfad).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["journal.sqlite"])
}

@Test func nurDieLetztenDreiKopienBleiben() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    try alteDatei(pfad)
    let alt = ["journal.vor-v7-2026-01-01-100000.sqlite", "journal.vor-v8-2026-02-01-100000.sqlite",
               "journal.vor-v8-2026-03-01-100000.sqlite"]
    for name in alt + ["journal.vor-notiz.txt", "anderes.vor-v1-2025-01-01-100000.sqlite"] {
        try Data("alt".utf8).write(to: dir.appendingPathComponent(name))
    }

    _ = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(Journal.kopienVorMigration(pfad: pfad).map(\.lastPathComponent) == [
        "journal.vor-v9-2026-10-05-153000.sqlite", "journal.vor-v8-2026-03-01-100000.sqlite",
        "journal.vor-v8-2026-02-01-100000.sqlite",
    ])
    let namen = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
    #expect(!namen.contains("journal.vor-v7-2026-01-01-100000.sqlite"))
    // Fremde Dateien bleiben.
    #expect(namen.contains("journal.vor-notiz.txt") && namen.contains("anderes.vor-v1-2025-01-01-100000.sqlite"))
}

@Test func ohneKopieWirdNichtMigriert() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    try alteDatei(pfad)
    // Am Ziel der Kopie liegt schon etwas: Die Kopie misslingt, die Datei bleibt auf v8.
    let belegt = dir.appendingPathComponent("journal.vor-v9-2026-10-05-153000.sqlite")
    try Data("belegt".utf8).write(to: belegt)

    do {
        _ = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
        Issue.record("Journal ohne Kopie migriert")
    } catch JournalFehler.datentraeger(let grund) {
        #expect(grund.contains("Sicherung vor der Aktualisierung"))
        #expect(JournalFehler.datentraeger(grund).errorDescription?.isEmpty == false)
    }
    #expect(try migrationen(pfad).last == v8)
    #expect(try Data(contentsOf: belegt) == Data("belegt".utf8))

    // Ist der Weg frei, klappt es beim nächsten Start.
    try FileManager.default.removeItem(at: belegt)
    let journal = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(try journal.angewandteMigrationen() == Schema.migrator.migrations)
}

@Test func kopienameNimmtDenStandDerErstenFehlendenMigration() {
    #expect(Journal.kopiename("/x/journal.sqlite", vor: "v10 Etwas Neues", jetzt: zeit, zeitzone: utc)
        == "journal.vor-v10-2026-10-05-153000.sqlite")
    #expect(Journal.kopiename("/x/daten", vor: "", jetzt: zeit, zeitzone: utc) == "daten.vor-2026-10-05-153000.sqlite")
}
