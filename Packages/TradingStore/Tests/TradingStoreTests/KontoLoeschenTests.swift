import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

// Konto löschen (Beispieldaten für Beta-Tester, Doc 11, Entscheidung 49).

private func fixture(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let jetzt = ISO8601DateFormatter().date(from: "2026-10-03T16:00:00Z")!

/// Zeilen je Tabelle, die zum Konto gehören: über `kontoId` oder über den Importlauf des Kontos.
/// Ohne Konto: alle Zeilen der Tabelle.
private func zeilen(_ journal: Journal, konto: Int64? = nil) throws -> [String: Int] {
    try journal.db.read { db in
        var ergebnis: [String: Int] = [:]
        let tabellen = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
              AND name != 'grdb_migrations' ORDER BY name
            """)
        for tabelle in tabellen {
            let spalten = try db.columns(in: tabelle).map(\.name)
            let bedingung: String
            if let konto {
                if tabelle == "konto" {
                    bedingung = "WHERE id = \(konto)"
                } else if spalten.contains("kontoId") {
                    bedingung = "WHERE kontoId = \(konto)"
                } else if spalten.contains("importlaufId") {
                    bedingung = "WHERE importlaufId IN (SELECT id FROM importlauf WHERE kontoId = \(konto))"
                } else {
                    continue
                }
            } else {
                bedingung = ""
            }
            ergebnis[tabelle] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tabelle) \(bedingung)") ?? 0
        }
        return ergebnis
    }
}

/// Ein Konto mit Daten in jeder kontobezogenen Tabelle.
private func fuelle(_ journal: Journal, _ konto: Konto, ticket: String) throws {
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: ticket, setup: "Ausbruch",
                                                regeltreue: true, zustand: 4, grund: "Test"))
    try journal.setzeCheckliste(Checkliste(setup: "Ausbruch", erfuellt: ["k1"]), konto: konto, ticket: ticket,
                                jetzt: jetzt)
    try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 3), konto: konto, jetzt: jetzt)
    try journal.legeZielAn(Reviewziel(text: "Kein Trade ohne Stop", von: jetzt, bis: jetzt.addingTimeInterval(86_400)),
                           konto: konto)
    try journal.speichereBild(Bildverweis(datei: "2026-10/\(konto.id!).png", bezug: .trade(ticket), erstellt: jetzt),
                              konto: konto)
}

@Test func kontoLoeschenEntferntNurDiesesKonto() throws {
    let journal = try Journal.imSpeicher()
    let mt4 = try fixture("MT4/gbe-2025-05-14-daily.html")
    try journal.importiereMT4(datei: mt4, dateiname: "a.html", serverZeitzone: utc)
    try journal.importiereCSV(datei: fixture("R2/trade_republic_2026_komma.csv"), dateiname: "tr.csv",
                              kontonummer: "Depot")
    let konten = try journal.konten()
    let weg = try #require(konten.first { $0.broker != "Trade Republic" })
    let bleibt = try #require(konten.first { $0.broker == "Trade Republic" })
    let ticket = try #require(journal.geschlossenePositionen(konto: weg).first?.ticket)
    try fuelle(journal, weg, ticket: ticket)
    try fuelle(journal, bleibt, ticket: "tr-1")
    // Kontoübergreifendes bleibt.
    try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "m1", begriff: "EURUSD", erstellt: jetzt))
    _ = try journal.speichereTagesnotiz(Tagesnotiz(tag: Journaltag(jetzt, zeitzone: utc), plan: "Plan", erstellt: jetzt),
                                        jetzt: jetzt)
    try journal.speichereSetup(Setup(name: "Ausbruch"))

    let vorher = try zeilen(journal)
    let anteil = try zeilen(journal, konto: weg.id!)
    #expect(anteil["geschlossenePosition"] == 4 && anteil["haken"] == 1 && anteil["bild"] == 1)

    let bilder = try journal.loescheKonto(weg)
    #expect(bilder == ["2026-10/\(weg.id!).png"])

    let nachher = try zeilen(journal)
    for (tabelle, anzahl) in vorher {
        #expect(nachher[tabelle] == anzahl - (anteil[tabelle] ?? 0), "Tabelle \(tabelle)")
    }
    #expect(try zeilen(journal, konto: weg.id!).values.allSatisfy { $0 == 0 })
    #expect(try journal.konten() == [bleibt])
    #expect(try journal.journaleintraege(konto: bleibt)["tr-1"]?.setup == "Ausbruch")
    #expect(try journal.checklisten(konto: bleibt)["tr-1"] == Checkliste(setup: "Ausbruch", erfuellt: ["k1"]))
    #expect(try journal.handelsregeln(konto: bleibt) == Handelsregeln(maxTradesJeTag: 3))
    #expect(try journal.bilder(trade: "tr-1", konto: bleibt).count == 1)

    // Dieselbe Datei geht wieder hinein, als neues Konto mit allen Positionen.
    let neu = try journal.importiereMT4(datei: mt4, dateiname: "a.html", serverZeitzone: utc)
    #expect(neu.status != .dateiBereitsImportiert)
    let wieder = try #require(try journal.konten().first { $0.broker != "Trade Republic" })
    #expect(wieder.id != weg.id)
    #expect(try journal.geschlossenePositionen(konto: wieder).count == 4)
    #expect(try journal.journaleintraege(konto: wieder).isEmpty)

    // Das CSV-Konto (Ausführungen, Geldbewegungen) geht genauso; übrig bleibt das neue MT4-Konto.
    #expect(try zeilen(journal, konto: bleibt.id!)["ausfuehrung"] ?? 0 > 0)
    try journal.loescheKonto(bleibt)
    #expect(try zeilen(journal, konto: bleibt.id!).values.allSatisfy { $0 == 0 })
    #expect(try journal.konten() == [wieder])
    #expect(try journal.merkliste().count == 1)
    #expect(try journal.playbook().count == 1)
}

@Test func unbekanntesKontoLaesstSichNichtLoeschen() throws {
    let journal = try Journal.imSpeicher()
    let ohneId = Konto(id: nil, broker: "B", kontonummer: "1", kontoname: "", waehrung: "EUR")
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto ohne ID")) { try journal.loescheKonto(ohneId) }
    var fremd = ohneId
    fremd.id = 99
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 99 gibt es nicht")) { try journal.loescheKonto(fremd) }
}
