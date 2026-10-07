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

// Die alten Spalten bleiben der Vergleichsmaßstab, auch wenn v10 bis v12 neue ergänzen.
private func vergleicheV9(_ db: Database, mit vorher: [String: [Row]]) throws {
    for (tabelle, zeilen) in vorher {
        let erste = try #require(zeilen.first)
        let spalten = erste.columnNames.map { "\"\($0)\"" }.joined(separator: ", ")
        let nachher = try Row.fetchAll(db, sql: "SELECT \(spalten) FROM \(tabelle) ORDER BY rowid")
        #expect(nachher == zeilen, "Werte und Beziehungen in \(tabelle)")
    }
    #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
    #expect(try String.fetchAll(db, sql: "PRAGMA integrity_check") == ["ok"])
}

private func befuelleV9(_ db: Database) throws {
    try db.execute(sql: """
        INSERT INTO konto (id, broker, kontonummer, kontoname, waehrung) VALUES
            (1, 'Beispiel Broker', '7', 'Alt', 'EUR'), (2, 'Muster Broker', '8', 'Depot', 'EUR');
        INSERT INTO importlauf (id, kontoId, importer, importerVersion, dateiname, dateiHash, datei, art,
                                stichtag, serverZeitzone, importiertAm) VALUES
            (11, 1, 'MT4-Auszug', '0.1.0', 'alt.html', 'abc', X'010203', 'daily',
             '2026-01-02 10:00:00.000', 'UTC', '2026-01-02 10:05:00.000'),
            (22, 2, 'Trade Republic', '0.1.0', 'alt.csv', 'def', X'040506', 'csv',
             '2026-01-03 10:00:00.000', 'UTC', '2026-01-03 10:05:00.000');
        INSERT INTO geschlossenePosition (id, kontoId, importlaufId, ticket, rohzeile, side, lots, symbol,
            openTime, openPrice, stopLoss, takeProfit, closeTime, closePrice, commission, swap, profit, produktart)
            VALUES (31, 1, 11, 'zu', '["zu", "1.10001"]', 'buy', '0.25', 'EURUSD', '2026-01-02 09:00:00.000',
                    '1.10001', '1.09', '1.12', '2026-01-02 09:30:00.000', '1.11002', '-1.25', '-0.15', '25.025', 'cfd');
        INSERT INTO offenePosition (id, importlaufId, ticket, rohzeile, side, lots, symbol, openTime, openPrice,
            stopLoss, takeProfit, currentPrice, commission, swap, profit, produktart)
            VALUES (41, 11, 'offen', '[]', 'sell', '0.5', 'GBPUSD', '2026-01-02 09:45:00.000',
                    '1.30001', '1.32', NULL, '1.29', '-2.5', '0', '50.05', 'cfd');
        INSERT INTO ausfuehrung (id, kontoId, importlaufId, vorgangId, zeit, nurDatum, kennung, name, seite,
            menge, preis, betrag, gebuehr, steuer, waehrung, sparplan, rohzeile, produktart) VALUES
            (51, 2, 22, 'kauf', '2026-01-02 08:00:00.000', 0, 'TEST123', 'Muster AG', 'buy',
             '2.5', '40.125', '-100.3125', '1', '0', 'EUR', 0, '[]', 'aktie'),
            (52, 2, 22, 'verkauf', '2026-01-03 09:00:00.000', 0, 'TEST123', 'Muster AG', 'sell',
             '1.5', '42.25', '63.375', '1', '0.25', 'EUR', 0, '[]', 'aktie');
        INSERT INTO setup (id, name, stopRegel, zielRegel, marktumfeld, notiz, status, statusSeit)
            VALUES (61, 'Ausbruch', 'Unter Tief', 'Zweifaches Risiko', 'Trend', 'Erfundene Karte',
                    'aktiv', '2026-01-01 10:00:00.000');
        INSERT INTO kriterium (setupId, kennung, text, position) VALUES (61, 'trend', 'Trend passt', 0);
        INSERT INTO journal (kontoId, ticket, setup, regeltreue, zustand, marktumfeld, grund,
                             stopEinstieg, geaendertAm) VALUES
            (1, 'zu', 'Ausbruch', 1, 4, 'Trend', 'Plan eingehalten', '1.085', '2026-01-02 10:10:00.000'),
            (1, 'offen', 'Ausbruch', 0, 2, 'Seitwaerts', 'Zu frueh', '1.325', '2026-01-02 10:11:00.000');
        INSERT INTO haken (kontoId, ticket, kennung) VALUES (1, 'zu', 'trend'), (1, 'offen', 'trend');
        """)
}

private func pruefeV12(_ journal: Journal, vorher: [String: [Row]], migrationen: [String]) throws {
    #expect(try journal.angewandteMigrationen() == migrationen + [
        "v10 Risiko und Tags", "v11 Ausstiegszeit und Markterwartung", "v12 Offene Trades von Hand",
    ])
    try journal.db.read { db in
        try vergleicheV9(db, mit: vorher)
        #expect(try String.fetchAll(db, sql: "SELECT standardRisiko FROM konto WHERE standardRisiko IS NOT NULL").isEmpty)
        #expect(try String.fetchAll(db, sql: "SELECT standardRisiko FROM setup WHERE standardRisiko IS NOT NULL").isEmpty)
        #expect(try Row.fetchAll(db, sql: "SELECT * FROM tradetag").isEmpty)
        for tabelle in ["geschlossenePosition", "offenePosition"] {
            #expect(try Bool.fetchAll(db, sql: "SELECT markterwartung IS NULL AND schein = 0 FROM \(tabelle)") == [true])
        }
    }
    let konten = try journal.konten()
    #expect(konten.count == 2)
    let konto = try #require(konten.first { $0.id == 1 })
    let depot = try #require(konten.first { $0.id == 2 })
    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.id == 11)
    let geschlossen = try #require(try journal.geschlossenePositionen(konto: konto).first)
    #expect(geschlossen.ticket == "zu" && geschlossen.ausstiegszeitBekannt)
    #expect(geschlossen.closeTime == ISO8601DateFormatter().date(from: "2026-01-02T09:30:00Z"))
    #expect(geschlossen.profit == d("25.025") && geschlossen.produktart == .cfd)
    let offen = try #require(try journal.offenePositionen(importlauf: lauf).first)
    #expect(offen.ticket == "offen" && offen.lots == d("0.5") && offen.produktart == .cfd)
    let ausfuehrungen = try journal.kontobewegungen(konto: depot).ausfuehrungen
    #expect(ausfuehrungen.map(\.id) == ["kauf", "verkauf"])
    #expect(ausfuehrungen.map(\.betrag) == [d("-100.3125"), d("63.375")])
    #expect(try journal.kontobewegungen(konto: konto).ausfuehrungen.isEmpty)
    #expect(try journal.geschlossenePositionen(konto: depot).isEmpty)
    let eintraege = try journal.journaleintraege(konto: konto)
    #expect(Set(eintraege.keys) == [geschlossen.ticket, offen.ticket])
    #expect(eintraege.values.allSatisfy { $0.risikoEinstieg == nil && $0.zeiteinheit == nil })
    #expect(try journal.playbook().map(\.name) == ["Ausbruch"])
    #expect(try journal.checklisten(konto: konto) == [
        "zu": Checkliste(setup: "Ausbruch", erfuellt: ["trend"]),
        "offen": Checkliste(setup: "Ausbruch", erfuellt: ["trend"]),
    ])
    #expect(try journal.risikoquellen(konto: konto).wirksam(ticket: "zu") == nil)
    #expect(try journal.tags(konto: konto).isEmpty)
    #expect(try journal.manuelleTickets(konto: konto).isEmpty)
    #expect(try journal.offeneManuelleTrades(konto: konto).isEmpty)
}

@Test func journalAusV9MigriertVollstaendigUndBleibtNachErneutemOeffnenErhalten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Risiko-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v9 Merkliste")
    try alt.write { try befuelleV9($0) }
    let migrationen = try alt.read { try Schema.migrator.appliedMigrations($0) }
    #expect(migrationen.last == "v9 Merkliste")
    let vorher = try alt.read { db in
        try Dictionary(uniqueKeysWithValues: ["konto", "importlauf", "geschlossenePosition", "offenePosition",
            "ausfuehrung", "setup", "kriterium", "journal", "haken"].map {
                (tabelle: $0, zeilen: try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY rowid"))
            })
    }
    try alt.close()

    let journal = try Journal(pfad: pfad, jetzt: zeit, zeitzone: utc)
    try pruefeV12(journal, vorher: vorher, migrationen: migrationen)
    try journal.db.close()
    let kopien = Journal.kopienVorMigration(pfad: pfad)
    #expect(kopien.map(\.lastPathComponent) == ["journal.vor-v10-2026-10-05-210000.sqlite"])
    let kopie = try #require(kopien.first)
    let gesichert = try Data(contentsOf: kopie)
    let pruefung = Journal.pruefeSicherung(kopie)
    #expect(pruefung.zustand == .aelter && pruefung.migrationen == migrationen)
    #expect(pruefung.konten == 2 && pruefung.geschlossenePositionen == 1 && pruefung.ausfuehrungen == 2)
    var konfiguration = Configuration()
    konfiguration.readonly = true
    let sicherung = try DatabaseQueue(path: kopie.path, configuration: konfiguration)
    try sicherung.read { db in
        try vergleicheV9(db, mit: vorher)
        #expect(try Schema.migrator.appliedMigrations(db) == migrationen)
        #expect(try !db.columns(in: "konto").contains { $0.name == "standardRisiko" })
        #expect(try !db.columns(in: "geschlossenePosition").contains { $0.name == "ausstiegszeitBekannt" })
        #expect(try !db.columns(in: "offenePosition").contains { $0.name == "schein" })
        #expect(try !db.tableExists("tradetag"))
    }
    try sicherung.close()

    // Ein neuer Start mit anderem Zeitstempel darf weder Daten noch Sicherung ändern.
    let nochmal = try Journal(pfad: pfad, jetzt: zeit.addingTimeInterval(60), zeitzone: utc)
    try pruefeV12(nochmal, vorher: vorher, migrationen: migrationen)
    try nochmal.db.close()
    #expect(Journal.kopienVorMigration(pfad: pfad) == kopien)
    #expect(try Data(contentsOf: kopie) == gesichert)
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
