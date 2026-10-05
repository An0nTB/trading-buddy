import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

// Geplantes Risiko und freie Tags je Trade (Migration v10, Doc 11 Entscheidung 52). Erfundene Daten.

private let utc = TimeZone(secondsFromGMT: 0)!
private let zeit = ISO8601DateFormatter().date(from: "2026-10-05T21:00:00Z")!

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

private func neuesKonto(_ journal: Journal, _ nummer: String) throws -> Konto {
    try journal.db.write { db in
        var konto = Konto(id: nil, broker: "Beispiel Broker", kontonummer: nummer, kontoname: "Test", waehrung: "EUR")
        try konto.insert(db)
        return konto
    }
}

@Test func journalAusV9BleibtLesbarUndBekommtV10() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Risiko-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v9 Merkliste")
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (broker, kontonummer, kontoname, waehrung) VALUES ('Beispiel Broker', '7', 'Alt', 'EUR');
            INSERT INTO setup (name, status, statusSeit) VALUES ('Ausbruch', 'aktiv', '2026-01-01 10:00:00.000');
            INSERT INTO journal (kontoId, ticket, setup, stopEinstieg, geaendertAm)
                VALUES (1, 't1', 'Ausbruch', '1.2345', '2026-01-02 10:00:00.000');
            """)
    }
    try alt.close()

    let journal = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    #expect(try journal.angewandteMigrationen().last == "v10 Risiko und Tags")
    #expect(Journal.kopienVorMigration(pfad: pfad).map(\.lastPathComponent)
        == ["journal.vor-v10-2026-10-05-210000.sqlite"])
    let konto = try #require(try journal.konten().first)
    let eintrag = try #require(try journal.journaleintraege(konto: konto)["t1"])
    #expect(eintrag.stopEinstieg == d("1.2345") && eintrag.risikoEinstieg == nil)
    #expect(try journal.playbook().map(\.name) == ["Ausbruch"])
    #expect(try journal.risikoquellen(konto: konto).wirksam(ticket: "t1") == nil)
    #expect(try journal.tags(konto: konto).isEmpty)
    #expect(try journal.alleTags(konto: konto).isEmpty)
}

@Test func wirksamesRisikoGehtVomTradeUeberSetupZumKonto() throws {
    let journal = try Journal.imSpeicher()
    let konto = try neuesKonto(journal, "1")
    let anderes = try neuesKonto(journal, "2")
    let ausbruch = try journal.speichereSetup(Setup(name: "Ausbruch"))
    try journal.speichereSetup(Setup(name: "Pullback"))
    try journal.setzeStandardRisiko(d("100"), konto: konto)
    try journal.setzeStandardRisiko(d("50.5"), setupId: ausbruch.id!)
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "a", setup: "Ausbruch",
                                                risikoEinstieg: d("25.125"), geaendertAm: zeit))
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "b", setup: "Ausbruch", geaendertAm: zeit))
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "c", setup: "Pullback", geaendertAm: zeit))

    let quellen = try journal.risikoquellen(konto: konto)
    #expect(quellen.wirksam(ticket: "a") == WirksamesRisiko(betrag: d("25.125"), herkunft: .trade))
    #expect(quellen.wirksam(ticket: "b") == WirksamesRisiko(betrag: d("50.5"), herkunft: .setup))
    #expect(quellen.wirksam(ticket: "c") == WirksamesRisiko(betrag: d("100"), herkunft: .konto))
    #expect(quellen.wirksam(ticket: "ohne Journal") == WirksamesRisiko(betrag: d("100"), herkunft: .konto))
    // Das andere Konto hat keinen eigenen Standard; das Setup gilt dort genauso.
    try journal.speichereJournal(Journaleintrag(kontoId: anderes.id!, ticket: "a", setup: "Ausbruch",
                                                geaendertAm: zeit))
    let dort = try journal.risikoquellen(konto: anderes)
    #expect(dort.wirksam(ticket: "a")?.herkunft == .setup)
    #expect(dort.wirksam(ticket: "x") == nil)

    // Umbenennen der Karte behält ihr Risiko und zieht die Trades mit.
    var umbenannt = ausbruch
    umbenannt.name = "Ausbruch Morgen"
    try journal.speichereSetup(umbenannt)
    #expect(try journal.standardRisikoJeSetup() == ["Ausbruch Morgen": d("50.5")])
    #expect(try journal.risikoquellen(konto: konto).wirksam(ticket: "b")?.herkunft == .setup)

    // Entfernen und falsche Werte.
    try journal.setzeStandardRisiko(nil, konto: konto)
    #expect(try journal.standardRisiko(konto: konto) == nil)
    #expect(try journal.risikoquellen(konto: konto).wirksam(ticket: "c") == nil)
    #expect(throws: SpeicherFehler.ungueltigerWert("Risiko 0 muss größer als 0 sein")) {
        try journal.setzeStandardRisiko(0, konto: konto)
    }
    #expect(throws: SpeicherFehler.self) { try journal.setzeStandardRisiko(d("-1"), setupId: ausbruch.id!) }
    #expect(throws: SpeicherFehler.self) { try journal.setzeStandardRisiko(d("1"), setupId: 999) }
    #expect(throws: SpeicherFehler.self) {
        try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "d", risikoEinstieg: d("-5")))
    }
}

@Test func tagsBehaltenSchreibweiseUndKommenAlsVorschlag() throws {
    let journal = try Journal.imSpeicher()
    let konto = try neuesKonto(journal, "1")
    let anderes = try neuesKonto(journal, "2")
    try journal.setzeTags(["FOMO", " fomo ", "Zu früh raus", ""], konto: konto, ticket: "1", jetzt: zeit)
    try journal.setzeTags(["Revenge", "fomo"], konto: konto, ticket: "2", jetzt: zeit)
    try journal.setzeTags(["Nur dort"], konto: anderes, ticket: "1", jetzt: zeit)

    #expect(try journal.tags(konto: konto) == ["1": ["FOMO", "Zu früh raus"], "2": ["Revenge", "fomo"]])
    // Häufigste zuerst, in der zuletzt gesetzten Schreibweise, dann alphabetisch.
    #expect(try journal.alleTags(konto: konto) == ["fomo", "Revenge", "Zu früh raus"])
    #expect(try journal.alleTags(konto: anderes) == ["Nur dort"])

    // Ersetzen und Leeren.
    try journal.setzeTags(["Geduldig"], konto: konto, ticket: "1", jetzt: zeit)
    #expect(try journal.tags(konto: konto)["1"] == ["Geduldig"])
    try journal.setzeTags([], konto: konto, ticket: "1", jetzt: zeit)
    #expect(try journal.tags(konto: konto)["1"] == nil)
    #expect(try journal.alleTags(konto: konto) == ["fomo", "Revenge"])

    // Mit dem Konto gehen auch seine Tags.
    try journal.loescheKonto(konto)
    #expect(try journal.alleTags(konto: anderes) == ["Nur dort"])
    let rest = try journal.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM tradetag") }
    #expect(rest == 1)
    var fremd = konto
    fremd.id = 99
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 99 gibt es nicht")) {
        try journal.setzeTags(["x"], konto: fremd, ticket: "1")
    }
}
