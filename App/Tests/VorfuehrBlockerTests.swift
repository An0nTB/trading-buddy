import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Vorführ-Blocker aus dem Codex-Review vom 04.10.2026: Kachel „Ohne Regelbrüche“ zählt Regelverstöße wie
/// Disziplin und Monatsbericht (B1); der Notiz-Editor des alten Kontos löscht nach einem Kontowechsel nicht die
/// Notiz eines anderen Kontos mit gleicher Ticketnummer (B2).
@Suite @MainActor struct VorfuehrBlockerTests {
    private typealias T = AppTestdaten

    @Test func kachelZaehltRegelverstoesseWieDisziplin() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        try m.legeBeispieldatenAn(heute: T.zeit(2026, 9, 15, 12))
        let verletzt = m.verletzteTrades
        #expect(verletzt.count == 2)
        #expect(m.trades.filter { verletzt.contains($0.id) }.count == 2)
        #expect(m.disziplin.verletzt == 2)
    }

    @Test func notizDesAltenKontosLaesstAnderesKontoInRuhe() throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot A", waehrung: "EUR", zeitzone: T.berlin)
        // Andere Einzahlung, damit die Datei nicht als schon importiert gilt; Kauf und Verkauf tragen dieselben Nummern.
        let zweite = T.scalable.replacingOccurrences(of: "2.000,00", with: "3.000,00")
        _ = try m.importiereCSV(daten: Data(zweite.utf8), dateiname: "appt-scalable-b.csv", kontonummer: "DE0087654321",
                                kontoname: "Depot B", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.konten.count == 2)
        let a = try #require(m.konten.first { $0.kontoname == "Depot A" })
        let b = try #require(m.konten.first { $0.kontoname == "Depot B" })
        let kontoA = try #require(a.id)
        let kontoB = try #require(b.id)

        m.waehleKonto(kontoB)
        let ticket = try #require(m.alleTrades.first?.id)
        m.speichereJournal(Journaleintrag(kontoId: kontoB, ticket: ticket, grund: "Notiz B"))
        m.waehleKonto(kontoA)
        #expect(m.alleTrades.contains { $0.id == ticket })
        m.speichereJournal(Journaleintrag(kontoId: kontoA, ticket: ticket, grund: "Notiz A"))

        // Kontowechsel zu B, danach speichert der Editor beim Verlassen den geleerten Eintrag von A.
        m.waehleKonto(kontoB)
        m.speichereJournal(Journaleintrag(kontoId: kontoA, ticket: ticket))
        #expect(m.journaleintraege[ticket]?.grund == "Notiz B")
        #expect(try journal.journaleintraege(konto: b)[ticket]?.grund == "Notiz B")
        #expect(try journal.journaleintraege(konto: a)[ticket] == nil)

        // Ein geänderter Eintrag von A landet bei A, nicht in der Anzeige von B.
        m.speichereJournal(Journaleintrag(kontoId: kontoA, ticket: ticket, grund: "Notiz A2"))
        #expect(m.journaleintraege[ticket]?.grund == "Notiz B")
        #expect(try journal.journaleintraege(konto: a)[ticket]?.grund == "Notiz A2")
        #expect(m.fehler == nil)
    }
}
