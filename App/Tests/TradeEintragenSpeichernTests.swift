import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Speichern aus dem Formular und Import der Journal-Sicherung über das AppModell, mit Journal im Speicher.
/// Alle Daten erfunden.
@MainActor @Suite struct TradeEintragenSpeichernTests {
    private typealias T = AppTestdaten

    private func modell() throws -> AppModell {
        AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
    }

    private func entwurf() -> TradeEntwurf {
        var e = TradeEntwurf(jetzt: T.zeit(2026, 3, 2, 9))
        e.ausstieg = T.zeit(2026, 3, 2, 11)
        e.symbol = "Testwert AG"
        e.groesse = 10
        e.einstiegskurs = 100
        e.ausstiegskurs = T.d("112.5")
        e.gebuehren = T.d("2.5")
        e.risiko = 50
        e.setup = "Ausbruch"
        e.zeiteinheit = "M15"
        e.gedanken = "erfunden"
        e.neuerKontoname = "Testdepot"
        return e
    }

    @Test func handtradeLandetInNeuemKonto() throws {
        let m = try modell()
        let e = entwurf()
        let ticket = try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                                   neuerKontoname: e.neuerKontoname, waehrung: "EUR")
        #expect(ticket.hasPrefix("hand-"))
        let konto = try #require(m.konto)
        #expect(konto.kontoname == "Testdepot")
        #expect(konto.broker == AppModell.handBroker)
        #expect(m.positionen.count == 1)
        #expect(m.positionen.first?.stopLoss == 95)
        let eintrag = try #require(m.journaleintraege[ticket])
        #expect(eintrag.setup == "Ausbruch")
        #expect(eintrag.zeiteinheit == "M15")
        #expect(eintrag.grund == "erfunden")
        #expect(eintrag.risikoEinstieg == 50)
        #expect(eintrag.regeltreue == true)
    }

    @Test func zweiterHandtradeImBestehendenKonto() throws {
        let m = try modell()
        let e = entwurf()
        try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                      neuerKontoname: "Testdepot", waehrung: "EUR")
        let id = try #require(m.konto?.id)
        try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .bestehend(id),
                                      neuerKontoname: "", waehrung: "EUR")
        #expect(m.konten.count == 1)
        #expect(m.positionen.count == 2)
    }

    @Test func journalSicherungWirdImportiert() throws {
        let m = try modell()
        let json = """
        {"trades": [
          {"id": "a1", "datum": "2026-03-02", "uhrzeit": "10:00", "asset": "Testwert AG", "klasse": "Aktie",
           "richtung": "Long", "art": "direkt", "setup": "Ausbruch", "zeiteinheit": "M15", "groesse": "10",
           "entry": "100,00", "exit": "112,50", "risiko": "50", "regel": true, "notiz": "erfunden"},
          {"id": "a2", "datum": "2026-03-06", "uhrzeit": "09:00", "asset": "Offen AG", "groesse": "1",
           "entry": "5", "exit": ""}
        ], "setups": ["Ausbruch"]}
        """
        let ergebnis = try m.importiereJournalSicherung(daten: Data(json.utf8), dateiname: "journal-sicherung-test.json",
                                                        kontoname: "Browser-Journal")
        #expect(ergebnis.geschlosseneNeu == 1)
        #expect(ergebnis.ohneAusstieg == 1)
        #expect(m.konto?.waehrung == "EUR")
        #expect(m.positionen.count == 1)
        #expect(m.positionen.first?.ausstiegszeitBekannt == false)
        let erneut = try m.importiereJournalSicherung(daten: Data(json.utf8), dateiname: "journal-sicherung-test.json",
                                                      kontoname: "Browser-Journal")
        #expect(erneut.status == .dateiBereitsImportiert)
    }
}
