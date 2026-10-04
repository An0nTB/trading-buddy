#if os(macOS)
import Foundation
import PDFKit
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Durchstich für die Vorführung mit Beispieldaten (#224): anlegen, Kennzahlen und Disziplin, Bericht- und
/// Steuer-PDF, Export für den Connector schreiben und wieder lesen, entfernen. Ein echtes Konto daneben bleibt
/// unverändert. Journal im Arbeitsspeicher, Export in einen eigenen Ordner unter `temporaryDirectory`; der
/// gemerkte Export-Ordner des Nutzers bleibt unberührt.
@Suite @MainActor struct BeispieldatenDurchstichTests {
    private typealias T = AppTestdaten
    private static let heute = T.zeit(2026, 9, 15, 12)

    /// Was am echten Konto hängt und sich nicht ändern darf.
    private struct EchterStand: Equatable {
        var tradeIDs: [String]
        var netto: Decimal
        var regeln: Handelsregeln
        var journal: [String: Journaleintrag]
    }

    private func echterStand(_ m: AppModell, _ id: Int64?) -> EchterStand {
        m.waehleKonto(id)
        return EchterStand(tradeIDs: m.alleTrades.map(\.id).sorted(), netto: m.kennzahlen.netto, regeln: m.regeln,
                           journal: m.journaleintraege)
    }

    /// Schreibt den Export wie `ExportOrdner.schreibe` in `ordner` und liest ihn wie der Connector
    /// (`Exportdatei.lade`: Datei `JournalExport.dateiname`, `JournalExport.lese`). Die App bindet ConnectorKern
    /// nicht ein, daher derselbe Weg ohne dessen Hülle.
    private func exportiereUndLies(_ journal: Journal, nach ordner: URL) throws -> JournalExport {
        let export = try ExportOrdner.export(journal, zeitzone: T.berlin)
        let datei = ordner.appending(path: JournalExport.dateiname)
        try export.json().write(to: datei, options: .atomic)
        return try JournalExport.lese(try Data(contentsOf: datei))
    }

    private func seiten(_ daten: Data?) throws -> Int {
        let daten = try #require(daten)
        return try #require(PDFDocument(data: daten)).pageCount
    }

    @Test func vorfuehrungVonAnlegenBisEntfernen() throws {
        let ordner = FileManager.default.temporaryDirectory
            .appending(path: "appt-durchstich-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)

        // Echtes Konto vorher, mit Regel und Journaleintrag.
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-durchstich-scalable.csv",
                                kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        let echt = try #require(m.konto)
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 5))
        let echterTrade = try #require(m.alleTrades.first)
        var eintrag = try #require(m.journaleintrag(echterTrade))
        eintrag.setup = "Eigenes Setup"
        m.speichereJournal(eintrag)
        let vorher = echterStand(m, echt.id)

        // Beispieldaten anlegen: eigenes Konto, gewählt, mit Zahlen.
        try m.legeBeispieldatenAn(heute: Self.heute)
        let beispiel = try #require(m.beispielkonto)
        #expect(m.konto?.id == beispiel.id)
        #expect(m.alleTrades.count == Beispieldaten.anzahl)
        #expect(m.kennzahlen.anzahl > 0)
        #expect(m.kennzahlen.anzahl + m.waehrungsstand.ohneKurs == Beispieldaten.anzahl)
        let disziplin = m.disziplin
        #expect(disziplin.punkte.count == Beispieldaten.anzahl)
        #expect(disziplin.verletzt >= 2)
        #expect(disziplin.regeltreu > 0)

        // Bericht-PDF für den Monat des ersten Trades und Steuer-PDF fürs Jahr.
        let erster = try #require(m.alleTrades.map(\.closeTime).min())
        let monat = m.monatsbericht(erster, jetzt: Self.heute)
        #expect(!monat.bericht.disziplin.punkte.isEmpty)
        let thema = BerichtPDF.druckthema(.nordlicht)
        #expect(try seiten(BerichtPDF.daten(monat.bericht, kontext: monat.kontext, thema: thema))
                == BerichtSeite.allCases.count)
        #expect(m.steuerjahre.contains(2026))
        let steuer = try #require(m.steuerAnlage(2026, jetzt: Self.heute))
        #expect(steuer.krypto != nil)
        #expect(try seiten(steuer.daten(thema: thema)) == 2)

        // Export für den Connector: beide Konten, Trades vollständig.
        let export = try exportiereUndLies(journal, nach: ordner)
        #expect(export.konten.count == 2)
        let beispielExport = try #require(export.konten.first { $0.broker == beispiel.broker })
        let echtExport = try #require(export.konten.first { $0.broker == echt.broker })
        #expect(beispielExport.trades.count == Beispieldaten.anzahl)
        #expect(echtExport.trades.count == vorher.tradeIDs.count)
        #expect(beispielExport.regeln?.maxTradesJeTag == Beispieldaten.maxTradesJeTag)
        #expect(!(export.tagesnotizen ?? []).isEmpty)

        // Entfernen: nur das echte Konto bleibt, unverändert; der Export trägt nur noch dessen Trades.
        try m.entferneBeispieldaten()
        #expect(m.beispielkonto == nil)
        #expect(m.konten.map(\.id) == [echt.id])
        #expect(echterStand(m, echt.id) == vorher)
        let danach = try exportiereUndLies(journal, nach: ordner)
        #expect(danach.konten.count == 1)
        #expect(danach.konten.first?.trades.map(\.id).sorted() == vorher.tradeIDs)
        #expect((danach.tagesnotizen ?? []).isEmpty)
    }
}
#endif
