import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Beispieldaten für Beta-Tester (Hauptthread 03.10.2026): anlegen, zählen, entfernen; ein echtes Konto bleibt
/// unberührt. Alles im Arbeitsspeicher, `heute` fest, damit der Plan bei jedem Lauf gleich ist.
@Suite @MainActor struct BeispieldatenTests {
    private typealias T = AppTestdaten
    private static let heute = T.zeit(2026, 9, 15, 12)

    @Test func planIstFestUndEndetVorHeute() {
        let plan = Beispieldaten.plan(heute: Self.heute)
        #expect(plan == Beispieldaten.plan(heute: Self.heute))
        #expect(plan.geschaefte.count == Beispieldaten.anzahl)
        #expect(plan.geschaefte.allSatisfy { $0.auf < $0.zu && $0.zu < Self.heute })
        #expect(plan.geschaefte.contains { $0.paar.hasSuffix("USD") })
        #expect(plan.geschaefte.contains { $0.verkauf > $0.kauf })
        #expect(plan.geschaefte.contains { $0.verkauf < $0.kauf })
        let jeTag = Dictionary(grouping: plan.geschaefte) { Journaltag($0.auf, zeitzone: Beispieldaten.zeitzone) }
        #expect(jeTag.values.filter { $0.count > Beispieldaten.maxTradesJeTag }.count == 2)
        #expect(jeTag[plan.notizTag]?.count == 4)
    }

    @Test func anlegenZaehlenEntfernenEchtesKontoBleibt() throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        let echt = try #require(m.konto)
        let echteTrades = m.alleTrades.count

        try m.legeBeispieldatenAn(heute: Self.heute)
        let beispiel = try #require(m.beispielkonto)
        #expect(m.konten.count == 2)
        #expect(m.konto?.id == beispiel.id)
        #expect(beispiel.kontoname == Beispieldaten.kontoname)
        #expect(m.alleTrades.count == Beispieldaten.anzahl)
        #expect(m.verstoesse.filter { $0.art == .tradesJeTag }.count == 2)
        #expect(m.journaleintraege.values.filter { $0.stopEinstieg != nil }.count == 40)
        #expect(try journal.tagesnotizen(von: T.tag(2026, 1, 1), bis: T.tag(2026, 12, 31)).count == 1)

        // Ein zweiter Klick legt nichts doppelt an.
        try m.legeBeispieldatenAn(heute: Self.heute)
        #expect(m.konten.count == 2)

        try m.entferneBeispieldaten()
        #expect(m.beispielkonto == nil)
        #expect(m.konten.map(\.id) == [echt.id])
        #expect(m.alleTrades.count == echteTrades)
        #expect(try journal.tagesnotizen(von: T.tag(2026, 1, 1), bis: T.tag(2026, 12, 31)).isEmpty)

        // Nach dem Entfernen lässt sich das Beispielkonto wieder anlegen (dieselbe Datei, derselbe Fingerabdruck).
        try m.legeBeispieldatenAn(heute: Self.heute)
        #expect(m.alleTrades.count == Beispieldaten.anzahl)
    }

    /// Eigene Tagesnotizen bleiben beim Entfernen; nur die Beispielnotiz geht.
    @Test func eigeneNotizBleibt() throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        let eigene = Tagesnotiz(tag: T.tag(2026, 9, 1), plan: "Eigener Plan", erstellt: Self.heute)
        try journal.speichereTagesnotiz(eigene)
        try m.legeBeispieldatenAn(heute: Self.heute)
        try m.entferneBeispieldaten()
        #expect(try journal.tagesnotizen(von: T.tag(2026, 1, 1), bis: T.tag(2026, 12, 31)).map(\.plan) == ["Eigener Plan"])
    }
}
