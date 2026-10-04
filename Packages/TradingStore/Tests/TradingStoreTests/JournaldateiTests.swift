import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

// Robustheit der Journal-Datei für Beta-Tester (Doc 11, Entscheidungen 46 bis 48): ältere Sicherungen,
// beschädigte Datei beim Start, Datenträger voll oder schreibgeschützt.

private func ordner() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Journaldatei-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// MT4-Testauszug aus den TradingCore-Tests (erfundener Beispielauszug, nur gelesen).
private func mt4Auszug() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-05-13-daily.html")
    return try Data(contentsOf: url)
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let zeit = ISO8601DateFormatter().date(from: "2026-10-03T15:30:00Z")!

/// Legt ein Journal mit einem MT4-Auszug an und schließt es wieder.
private func gefuelltesJournal(_ pfad: String) throws {
    let journal = try Journal(pfad: pfad)
    try journal.importiereMT4(datei: mt4Auszug(), dateiname: "a.html", serverZeitzone: utc)
}

@Test(arguments: ["v5 Handelsregeln je Konto", "v6 Produktart", "v7 Playbook",
                  "v8 Tagesnotiz, verpasste Trades, Bilder"])
func sicherungAusAelteremStandWirdMigriert(stand: String) throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    // Sicherung, wie sie eine App-Version mit Stand `stand` geschrieben hätte: Konto mit Journaleintrag.
    let datei = dir.appendingPathComponent("alt.sqlite")
    let alt = try DatabaseQueue(path: datei.path)
    try Schema.migrator.migrate(alt, upTo: stand)
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (broker, kontonummer, kontoname, waehrung) VALUES ('Beispiel Broker Ltd.', '12345678', 'Test', 'EUR');
            INSERT INTO journal (kontoId, ticket, setup, zustand, geaendertAm)
                VALUES (1, '4711', 'Ausbruch', 4, '2026-05-13 10:00:00.000');
            """)
    }
    try alt.close()

    let pruefung = Journal.pruefeSicherung(datei)
    #expect(pruefung.zustand == .aelter)
    let fehlend = Array(Schema.migrator.migrations.drop { $0 != stand }.dropFirst())
    #expect(pruefung.fehlendeMigrationen == fehlend)
    #expect(pruefung.konten == 1)

    let ziel = try Journal(pfad: dir.appendingPathComponent("journal.sqlite").path)
    #expect(try ziel.stelleWiederHer(aus: datei).zustand == .aktuell)
    #expect(try ziel.angewandteMigrationen() == Schema.migrator.migrations)
    let konto = try #require(try ziel.konten().first)
    #expect(try ziel.journaleintraege(konto: konto)["4711"]?.setup == "Ausbruch")
    // Was erst die neueren Stände kennen, geht danach.
    try ziel.importiereMT4(datei: mt4Auszug(), dateiname: "a.html", serverZeitzone: utc)
    #expect(try ziel.geschlossenePositionen(konto: konto).count == 4)
    try ziel.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "EURUSD", erstellt: zeit))
}

@Test func journalAusNeuererVersionBleibtUnangetastet() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    try gefuelltesJournal(pfad)
    let neu = try DatabaseQueue(path: pfad)
    try neu.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99 Zukunft')") }
    try neu.close()
    let vorher = try Data(contentsOf: URL(fileURLWithPath: pfad))

    #expect(throws: JournalFehler.ausNeuererVersion(["v99 Zukunft"])) { try Journal(pfad: pfad) }
    #expect(try Data(contentsOf: URL(fileURLWithPath: pfad)) == vorher)
    #expect(JournalFehler.ausNeuererVersion(["v99 Zukunft"]).errorDescription?.contains("neueren Version") == true)
}

@Test func beschaedigteJournaldateiBleibtErhaltenUndSicherungHilft() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    let sicherungen = dir.appendingPathComponent("Sicherung")
    do {
        let journal = try Journal(pfad: pfad)
        try journal.importiereMT4(datei: mt4Auszug(), dateiname: "a.html", serverZeitzone: utc)
        try journal.sichereInOrdner(sicherungen, jetzt: zeit, zeitzone: utc)
    }
    // Alles nach der ersten Seite überschreiben: Kopf lesbar, Tabellen zerstört.
    var inhalt = try Data(contentsOf: URL(fileURLWithPath: pfad))
    #expect(inhalt.count > 8_192)
    inhalt.replaceSubrange(4_096..<inhalt.count, with: Data(repeating: 0, count: inhalt.count - 4_096))
    try inhalt.write(to: URL(fileURLWithPath: pfad))

    // Jeder Versuch scheitert gleich und ändert nichts.
    for _ in 0..<2 {
        do {
            _ = try Journal(pfad: pfad)
            Issue.record("Beschädigte Datei ließ sich öffnen")
        } catch JournalFehler.beschaedigt(let grund) {
            #expect(!grund.isEmpty)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: pfad)) == inhalt)
    }

    let letzte = try #require(Journal.letzteBrauchbareSicherung(in: sicherungen))
    #expect(letzte.datei.lastPathComponent == "Journal-Sicherung-2026-10-03-153000.sqlite")
    let (journal, beiseite) = try Journal.oeffneAusSicherung(pfad: pfad, sicherung: letzte.datei, jetzt: zeit,
                                                             zeitzone: utc)
    let weg = try #require(beiseite)
    #expect(weg.lastPathComponent == "journal.sqlite.beschaedigt-2026-10-03-153000")
    #expect(try Data(contentsOf: weg) == inhalt)
    let konto = try #require(try journal.konten().first)
    #expect(try journal.geschlossenePositionen(konto: konto).count == 4)
}

@Test func keineDateiWirdBeimBeiseitelegenUeberschrieben() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    try Data(repeating: 0x41, count: 4_096).write(to: URL(fileURLWithPath: pfad))
    #expect(throws: JournalFehler.self) { try Journal(pfad: pfad) }
    // Begleitdatei erst danach anlegen, sonst räumt SQLite sie beim Öffnen womöglich weg.
    try Data("rest".utf8).write(to: URL(fileURLWithPath: pfad + "-journal"))

    let beiseite = try Journal.legeBeiseite(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(!FileManager.default.fileExists(atPath: pfad))
    #expect(FileManager.default.fileExists(atPath: beiseite.path + "-journal"))
    // Gleicher Zeitpunkt noch einmal: abgelehnt statt überschrieben.
    try Data("neu".utf8).write(to: URL(fileURLWithPath: pfad))
    #expect(throws: SpeicherFehler.ungueltigerWert("journal.sqlite.beschaedigt-2026-10-03-153000 gibt es schon")) {
        try Journal.legeBeiseite(pfad: pfad, jetzt: zeit, zeitzone: utc)
    }
    #expect(try Data(contentsOf: beiseite) == Data(repeating: 0x41, count: 4_096))
    // Kaputte Sicherung: nichts wird beiseitegelegt.
    #expect(throws: SpeicherFehler.self) {
        try Journal.oeffneAusSicherung(pfad: pfad, sicherung: beiseite)
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: pfad)) == Data("neu".utf8))
    #expect(Journal.letzteBrauchbareSicherung(in: dir) == nil)
}

@Test func vollerDatentraegerMeldetTypisiertenFehler() throws {
    let journal = try Journal.imSpeicher()
    // Datei darf nicht weiter wachsen: wie eine volle Platte (SQLITE_FULL).
    try journal.db.writeWithoutTransaction { db in
        let seiten = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
        try db.execute(sql: "PRAGMA max_page_count = \(seiten)")
    }
    // Eine lange Notiz braucht neue Seiten; kleine Zeilen passten womöglich noch in die leeren Tabellenseiten.
    let tag = Journaltag(zeit, zeitzone: utc)
    #expect(throws: JournalFehler.platteVoll) {
        try journal.speichereTagesnotiz(Tagesnotiz(tag: tag, plan: String(repeating: "Plan ", count: 40_000),
                                                   rueckblick: "", verfassung: 3, erstellt: zeit), jetzt: zeit)
    }
    // Die Transaktion ist zurückgenommen, Lesen geht weiter.
    #expect(try journal.tagesnotizen(von: tag, bis: tag).isEmpty)
    #expect(JournalFehler.platteVoll.errorDescription?.contains("kein Platz") == true)
}

@Test func schreibgeschuetztesJournalMeldetTypisiertenFehler() throws {
    let journal = try Journal.imSpeicher()
    try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "AAPL", erstellt: zeit))
    try journal.db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA query_only = 1") }
    #expect(throws: JournalFehler.nurLesbar) {
        try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "2", begriff: "MSFT", erstellt: zeit))
    }
    #expect(try journal.merkliste().map(\.begriff) == ["AAPL"])
}

@Test func andereDatenbankfehlerBleibenUnveraendert() {
    #expect(JournalFehler(DatabaseError(resultCode: .SQLITE_CONSTRAINT)) == nil)
    #expect(JournalFehler(DatabaseError(resultCode: .SQLITE_FULL)) == .platteVoll)
    #expect(JournalFehler(DatabaseError(resultCode: .SQLITE_NOTADB, message: "file is not a database"))
        == .beschaedigt("file is not a database"))
}
