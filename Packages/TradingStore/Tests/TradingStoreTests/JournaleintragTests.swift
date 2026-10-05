import Foundation
import GRDB
import Testing
@testable import TradingStore

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

/// Journal mit einem importierten Tagesauszug (Ticket 51756927 ist eine geschlossene Position).
private func journalMitKonto() throws -> (Journal, Konto) {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-05-13-daily.html")
    let journal = try Journal.imSpeicher()
    try journal.importiereMT4(datei: Data(contentsOf: url), dateiname: "beispiel-2026-05-13-daily.html",
                              serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    return (journal, try journal.konten()[0])
}

private let zeit = Date(timeIntervalSince1970: 1_759_350_000)

@Test func journalEintragKommtUnveraendertZurueck() throws {
    let (journal, konto) = try journalMitKonto()
    let eintrag = Journaleintrag(kontoId: konto.id!, ticket: "51756927", setup: "Ausbruch",
                                 regeltreue: false, zustand: 3, marktumfeld: "Trend",
                                 grund: "Stop zu eng", stopEinstieg: d("0.64572"), geaendertAm: zeit)
    try journal.speichereJournal(eintrag)
    #expect(try journal.journaleintraege(konto: konto) == ["51756927": eintrag])
}

@Test func zweimalSpeichernErgibtEinenEintrag() throws {
    let (journal, konto) = try journalMitKonto()
    var eintrag = Journaleintrag(kontoId: konto.id!, ticket: "51756927", setup: "Ausbruch", geaendertAm: zeit)
    try journal.speichereJournal(eintrag)
    eintrag.setup = "Rücklauf"
    eintrag.stopEinstieg = d("0.6457")
    try journal.speichereJournal(eintrag)
    let alle = try journal.journaleintraege(konto: konto)
    #expect(alle.count == 1)
    #expect(alle["51756927"]?.setup == "Rücklauf")
    #expect(alle["51756927"]?.stopEinstieg == d("0.6457"))
}

@Test func exportStopBleibtUnveraendert() throws {
    let (journal, konto) = try journalMitKonto()
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "51756927",
                                                stopEinstieg: d("0.65000"), geaendertAm: zeit))
    let position = try #require(try journal.geschlossenePositionen(konto: konto).first { $0.ticket == "51756927" })
    #expect(position.stopLoss == d("0.64572"))
}

@Test func eintragOhnePositionIstErlaubtUndUeberstehtReImport() throws {
    let (journal, konto) = try journalMitKonto()
    // Ticket aus dem Juni, noch nicht importiert.
    let eintrag = Journaleintrag(kontoId: konto.id!, ticket: "51821462", grund: "Plan vorab", geaendertAm: zeit)
    try journal.speichereJournal(eintrag)
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-06-04-daily.html")
    try journal.importiereMT4(datei: Data(contentsOf: url), dateiname: "beispiel-2026-06-04-daily.html",
                              serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    #expect(try journal.journaleintraege(konto: konto)["51821462"] == eintrag)
    #expect(try journal.geschlossenePositionen(konto: konto).contains { $0.ticket == "51821462" })
}

@Test func loeschenEntferntNurDiesenEintrag() throws {
    let (journal, konto) = try journalMitKonto()
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "1", setup: "a", geaendertAm: zeit))
    try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "2", setup: "b", geaendertAm: zeit))
    try journal.loescheJournal(konto: konto, ticket: "1")
    try journal.loescheJournal(konto: konto, ticket: "gibt es nicht")
    #expect(Array(try journal.journaleintraege(konto: konto).keys) == ["2"])
}

@Test func ungueltigeEingabenWerdenAbgelehnt() throws {
    let (journal, konto) = try journalMitKonto()
    #expect(throws: SpeicherFehler.self) {
        try journal.speichereJournal(Journaleintrag(kontoId: konto.id!, ticket: "1", zustand: 6))
    }
    #expect(throws: SpeicherFehler.self) {
        try journal.speichereJournal(Journaleintrag(kontoId: 999, ticket: "1"))
    }
    #expect(try journal.journaleintraege(konto: konto).isEmpty)
}

@Test func alteDatenbankWirdAufNeuestenStandGehoben() throws {
    let ordner = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path

    // Stand vor diesem Paket: nur Migration v1.
    try Schema.migrator.migrate(DatabaseQueue(path: pfad), upTo: "v1 Konten, Importe, MT4-Auszüge")
    let journal = try Journal(pfad: pfad)
    #expect(try journal.angewandteMigrationen() == ["v1 Konten, Importe, MT4-Auszüge", "v2 Journal je Trade", "v3 Broker-Importe CSV",
                                                   "v4 Review-Ziele", "v5 Handelsregeln je Konto",
                                                   "v6 Produktart", "v7 Playbook", "v8 Tagesnotiz, verpasste Trades, Bilder", "v9 Merkliste",
                                                   "v10 Risiko und Tags"])
}
