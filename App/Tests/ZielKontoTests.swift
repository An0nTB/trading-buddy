import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Codex-Review 04.10.2026, M5: Ein Zielentwurf merkt sich sein Konto. Nach einem Kontowechsel landet das Ziel beim
/// Konto des Entwurfs, die Liste des gerade gewählten Kontos bleibt unberührt.
@Suite @MainActor struct ZielKontoTests {
    private typealias T = AppTestdaten

    @Test func zielLandetBeimKontoDesEntwurfs() throws {
        let journal = try Journal.imSpeicher()
        let m = AppModell(journal: journal, nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "appt-kraken-a.csv",
                                kontonummer: "KR-00001111", kontoname: "Konto A", waehrung: "EUR", zeitzone: T.utc)
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "B").utf8), dateiname: "appt-kraken-b.csv",
                                kontonummer: "KR-00002222", kontoname: "Konto B", waehrung: "EUR", zeitzone: T.utc)
        let a = try #require(m.konten.first { $0.kontoname == "Konto A" })
        let b = try #require(m.konten.first { $0.kontoname == "Konto B" })
        let jetzt = Date()
        let ziel = Reviewziel(text: "Höchstens zwei Trades", von: jetzt, bis: jetzt.addingTimeInterval(7 * 86_400))

        // Entwurf bei A begonnen, inzwischen ist B gewählt.
        m.waehleKonto(b.id)
        try m.legeZielAn(ziel, konto: a.id)
        #expect(m.ziele.isEmpty)
        #expect(try journal.ziele(konto: a).count == 1)
        #expect(try journal.ziele(konto: b).isEmpty)

        // Ohne Konto wie bisher beim gewählten Konto.
        try m.legeZielAn(ziel)
        #expect(m.ziele.count == 1)
        #expect(try journal.ziele(konto: b).count == 1)

        // Gelöschtes oder unbekanntes Konto: Fehler statt stiller Ablage woanders.
        #expect(throws: Zielfehler.keinKonto) { try m.legeZielAn(ziel, konto: -1) }
    }
}
