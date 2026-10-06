import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Formular „Trade eintragen“ und Vorschau der Journal-Sicherung ohne Ansicht (Doc 02 Nr. 63 und 64).
/// Alle Daten erfunden.
@Suite struct TradeEintragenAppTests {
    private typealias T = AppTestdaten

    /// Ausgefüllter Entwurf: Long, 10 Stück, 100 → 112,50, Gebühren 2,50, neues Konto „Test“.
    private func entwurf() -> TradeEntwurf {
        var e = TradeEntwurf(jetzt: T.zeit(2026, 3, 2, 9))
        e.ausstieg = T.zeit(2026, 3, 2, 11)
        e.symbol = "  Beispiel AG "
        e.groesse = 10
        e.einstiegskurs = 100
        e.ausstiegskurs = T.d("112.5")
        e.gebuehren = T.d("2.5")
        e.neuerKontoname = "Test"
        return e
    }

    @Test func vollstaendigerEntwurfIstSpeicherbar() throws {
        let e = entwurf()
        #expect(e.speicherbar)
        #expect(e.hinderungsgruende.isEmpty)
        let trade = try #require(e.trade)
        #expect(trade.symbol == "Beispiel AG")
        #expect(trade.ergebnis == 125)
        #expect(trade.gebuehren == T.d("2.5"))
        #expect(e.netto == T.d("122.5"))
        let position = trade.position(ticket: "m-1")
        #expect(position.ausstiegszeitBekannt)
        #expect(position.commission == T.d("-2.5"))
    }

    @Test func offenerEntwurfBrauchtKeinenExit() throws {
        var e = entwurf()
        e.ausstiegskurs = nil
        #expect(e.luecken() == [.ausstiegskurs])
        e.offen = true
        #expect(e.luecken().isEmpty)
        #expect(e.speicherbar)
        let trade = try #require(e.trade)
        #expect(trade.offen && trade.ausstieg == nil && trade.ausstiegskurs == nil)
        #expect(e.netto == nil)
        // Ein Exit aus früherer Eingabe zählt nicht, solange der Trade offen ist.
        e.ausstiegskurs = 120
        #expect(try #require(e.trade).offen)
    }

    @Test func fehlendeAngabenSperrenDasSpeichern() {
        var e = TradeEntwurf(jetzt: T.zeit(2026, 3, 2))
        #expect(!e.speicherbar)
        #expect(e.luecken() == [.groesse, .einstiegskurs, .ausstiegskurs, .kontoname])
        #expect(e.trade == nil)
        e.kontowahl = .bestehend(1)
        #expect(!e.luecken().contains(.kontoname))
    }

    /// Ohne Ausstiegszeit schließt die Position zur Einstiegszeit und zählt nur mit Datum.
    @Test func ohneAusstiegszeitNurDatum() throws {
        var e = entwurf()
        e.ausstiegBekannt = false
        let position = try #require(e.trade).position(ticket: "m-2")
        #expect(!position.ausstiegszeitBekannt)
        #expect(position.closeTime == position.openTime)
        #expect(Trade(position).nurDatum)
    }

    @Test func ausstiegVorEinstiegIstProblem() {
        var e = entwurf()
        e.ausstieg = T.zeit(2026, 3, 1)
        #expect(e.probleme == [.ausstiegVorEinstieg])
        #expect(!e.speicherbar)
    }

    /// Risiko 50 bei 10 Stück: Stop 5 Punkte unter dem Einstieg, 1 R = 50, Ergebnis 122,50 = 2,45 R.
    @Test func risikoErgibtStopUndR() throws {
        var e = entwurf()
        e.stopArt = .risiko
        e.risiko = 50
        #expect(try #require(e.trade).stop == 95)
        #expect(e.eigenesRisiko == 50)
        #expect(e.rWert(standardRisiko: 999) == T.d("2.45"))
    }

    /// Stop als Kurs gewinnt; ein Risiko aus dem anderen Modus wird nicht mitgeschickt.
    @Test func stopKursGehtVorRisiko() throws {
        var e = entwurf()
        e.risiko = 50
        e.stopArt = .kurs
        e.stopKurs = 90
        let trade = try #require(e.trade)
        #expect(trade.stopKurs == 90)
        #expect(trade.risiko == nil)
        #expect(e.eigenesRisiko == 100)
        e.stopKurs = 101
        #expect(e.probleme == [.stopAufFalscherSeite])
    }

    /// Ohne Stop rechnet R mit dem Standard-Risiko (Nr. 64), ohne beides bleibt es offen.
    @Test func ohneStopStandardRisiko() {
        let e = entwurf()
        #expect(e.eigenesRisiko == nil)
        #expect(e.rWert(standardRisiko: 50) == T.d("2.45"))
        #expect(e.rWert(standardRisiko: nil) == nil)
    }

    /// Schein Short: gekauft, Markterwartung Short, Produktart Derivat, Exit 0 erlaubt (ausgeknockt).
    @Test func scheinWirdGekauft() throws {
        var e = entwurf()
        e.schein = true
        e.markterwartung = .sell
        e.produktart = .aktie
        e.ausstiegskurs = 0
        let trade = try #require(e.trade)
        #expect(trade.handelsseite == .buy)
        #expect(trade.markterwartung == .sell)
        #expect(trade.produktart == .derivat)
        #expect(e.probleme.isEmpty)
        #expect(trade.ergebnis == -1000)
    }

    @Test func hebelproduktImNamenStelltScheinVor() {
        var e = entwurf()
        e.symbol = "Nasdaq 100 Short 21.500,00 Turbo Open End"
        let erkannt = e.uebernimmHebelprodukt()
        #expect(erkannt?.basiswert == "Nasdaq 100")
        #expect(e.schein)
        #expect(e.markterwartung == .sell)
        var aktie = entwurf()
        #expect(aktie.uebernimmHebelprodukt() == nil)
        #expect(!aktie.schein)
    }

    @Test func angabenOhneLeereTexte() {
        var e = entwurf()
        e.setup = "Ausbruch"
        e.zeiteinheit = ""
        e.gedanken = "  "
        e.planEingehalten = false
        #expect(e.angaben == TradeAngaben(setup: "Ausbruch", zeiteinheit: nil, regeltreue: false, notiz: nil))
    }

    // MARK: Journal-Sicherung

    private static let sicherung = """
    {"trades": [
      {"id": "a1", "datum": "2026-03-02", "uhrzeit": "10:00", "asset": "Beispiel AG", "klasse": "Aktie",
       "richtung": "Long", "art": "direkt", "setup": "Ausbruch", "zeiteinheit": "M15", "groesse": "10",
       "entry": "100,00", "exit": "112,50", "risiko": "50", "regel": true, "notiz": "erfunden"},
      {"id": "a2", "datum": "2026-03-05", "uhrzeit": "15:30", "asset": "KO Short Index", "klasse": "Index",
       "richtung": "Short", "art": "schein", "setup": "Umkehr", "zeiteinheit": "M5", "groesse": "100",
       "entry": "1,20", "exit": "1,00", "risiko": "", "regel": false},
      {"id": "a3", "datum": "2026-03-06", "uhrzeit": "09:00", "asset": "Offen AG", "groesse": "1",
       "entry": "5", "exit": ""}
    ], "setups": ["Ausbruch", "Pullback"]}
    """

    @Test func sicherungWirdErkanntUndGelesen() throws {
        let daten = Data(Self.sicherung.utf8)
        #expect(JournalSicherung.erkennt(daten))
        let v = try JournalSicherungVorschau.lies(daten)
        #expect(v.trades == 2)
        #expect(v.offen == 1)
        #expect(v.gewinner == 1)
        #expect(v.mitRisiko == 1)
        #expect(v.scheine == 1)
        #expect(v.netto == 105) // +125 und −20
        #expect(v.knopfText.contains("2"))
        #expect(v.zeitraum?.von == T.zeit(2026, 3, 2, 9)) // 10:00 Berlin = 09:00 UTC im März
    }

    @Test func neueSetupsOhneDoppelte() throws {
        let v = try JournalSicherungVorschau.lies(Data(Self.sicherung.utf8))
        #expect(v.neueSetups(playbook: ["ausbruch"]) == ["Pullback", "Umkehr"])
        #expect(v.neueSetups(playbook: ["Ausbruch", "Pullback", "Umkehr"]).isEmpty)
    }

    /// Andere JSON-Dateien (etwa Börsen-Einstellungen) gehen nicht in die Weiche der Journal-Sicherung.
    @Test func fremdesJSONIstKeineSicherung() {
        #expect(!JournalSicherung.erkennt(Data(#"{"boersen": []}"#.utf8)))
        #expect(!JournalSicherung.erkennt(Data("kein json".utf8)))
        #expect(throws: JournalSicherungFehler.keineTradesListe) {
            try JournalSicherungVorschau.lies(Data(#"{"boersen": []}"#.utf8))
        }
        #expect(!JournalSicherungBlatt.lesefehlerText(JournalSicherungFehler.keinJSON).isEmpty)
    }

    /// Ohne Journal-Datei kommt eine verständliche Meldung, kein Absturz.
    @MainActor @Test func ohneJournalMeldung() throws {
        let modell = AppModell(journal: nil, nebenwirkungen: false)
        let trade = try #require(entwurf().trade)
        #expect(throws: TradeEintragenFehler.keinJournal) {
            try modell.speichereManuellenTrade(trade, angaben: TradeAngaben(), kontowahl: .neu,
                                               neuerKontoname: "Test", waehrung: "EUR")
        }
        #expect(modell.standardRisiko(setup: "Ausbruch", kontowahl: .neu) == nil)
    }
}
