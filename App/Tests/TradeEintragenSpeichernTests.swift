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

    /// Gespeicherte Positionen des gewählten Kontos, direkt aus dem Journal.
    private func positionen(_ m: AppModell) throws -> [ClosedPosition] {
        let journal = try #require(m.journal)
        let konto = try #require(m.konto)
        return try journal.geschlossenePositionen(konto: konto)
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
        let gespeichert = try positionen(m)
        #expect(gespeichert.count == 1)
        #expect(gespeichert.first?.stopLoss == 95)
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
        let gespeichert = try positionen(m)
        #expect(gespeichert.count == 2)
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
        let importiert = try positionen(m)
        #expect(importiert.count == 1)
        #expect(importiert.first?.ausstiegszeitBekannt == false)
        let erneut = try m.importiereJournalSicherung(daten: Data(json.utf8), dateiname: "journal-sicherung-test.json",
                                                      kontoname: "Browser-Journal")
        #expect(erneut.status == .dateiBereitsImportiert)
    }

    // MARK: Bearbeiten und Löschen (Paket 1a)

    @Test func bearbeitenErsetztDenTradeUndBehaeltDasJournal() throws {
        let m = try modell()
        let e = entwurf()
        let ticket = try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                                   neuerKontoname: e.neuerKontoname, waehrung: "EUR")
        var zustand = try #require(m.journaleintraege[ticket])
        zustand.zustand = 4
        m.speichereJournal(zustand)
        let trade = try #require(m.alleTrades.first)
        #expect(m.istHandtrade(trade))
        var bearbeitung = try #require(m.handEntwurf(trade))
        #expect(bearbeitung.ticket == ticket)
        #expect(bearbeitung.stopArt == .risiko)
        #expect(bearbeitung.risiko == 50)
        #expect(bearbeitung.setup == "Ausbruch")
        #expect(bearbeitung.gedanken == "erfunden")
        #expect(bearbeitung.gebuehren == T.d("2.5"))
        bearbeitung.ausstiegskurs = 90
        bearbeitung.gedanken = "geändert"
        let neuesTicket = try m.speichereManuellenTrade(try #require(bearbeitung.trade), angaben: bearbeitung.angaben,
                                                        kontowahl: bearbeitung.kontowahl, neuerKontoname: "",
                                                        waehrung: "EUR", ticket: bearbeitung.ticket)
        #expect(neuesTicket == ticket)
        let gespeichert = try positionen(m)
        #expect(gespeichert.count == 1)
        #expect(gespeichert.first?.profit == -100)
        let eintrag = try #require(m.journaleintraege[ticket])
        #expect(eintrag.grund == "geändert")
        #expect(eintrag.zustand == 4)
        #expect(eintrag.risikoEinstieg == 50)
    }

    @Test func stopAlsKursBehaeltDasBisherigeRisiko() throws {
        let m = try modell()
        var e = entwurf()
        e.stopArt = .kurs
        e.stopKurs = 97
        e.risiko = nil
        let ticket = try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                                   neuerKontoname: e.neuerKontoname, waehrung: "EUR")
        var mitRisiko = try #require(m.journaleintraege[ticket])
        mitRisiko.risikoEinstieg = 80
        m.speichereJournal(mitRisiko)
        let trade = try #require(m.alleTrades.first)
        let bearbeitung = try #require(m.handEntwurf(trade))
        #expect(bearbeitung.stopArt == .kurs)
        #expect(bearbeitung.stopKurs == 97)
        #expect(bearbeitung.angaben.risikoEinstieg == 80)
    }

    @Test func loeschenEntferntTradeUndJournal() throws {
        let m = try modell()
        let e = entwurf()
        let ticket = try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                                   neuerKontoname: e.neuerKontoname, waehrung: "EUR")
        try m.loescheHandtrade(try #require(m.alleTrades.first))
        let uebrig = try positionen(m)
        #expect(uebrig.isEmpty)
        #expect(m.journaleintraege[ticket] == nil)
    }

    @Test func importierterTradeIstKeinHandtrade() throws {
        let m = try modell()
        let json = """
        {"trades": [{"id": "b1", "datum": "2026-03-02", "uhrzeit": "10:00", "asset": "Testwert AG",
                     "groesse": "10", "entry": "100", "exit": "110"}]}
        """
        _ = try m.importiereJournalSicherung(daten: Data(json.utf8), dateiname: "journal-sicherung-b.json",
                                             kontoname: "Browser-Journal")
        let trade = try #require(m.alleTrades.first)
        #expect(!m.istHandtrade(trade))
        #expect(m.handEntwurf(trade) == nil)
        #expect(throws: (any Error).self) { try m.loescheHandtrade(trade) }
    }
}
