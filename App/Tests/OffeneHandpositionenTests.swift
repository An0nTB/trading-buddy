import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Offen eingetragene Hand-Trades in der Karte „Offene Positionen“ (Tim 06.10.2026): Position, Richtung und
/// Buchgewinn wie `ManuellerTrade.ergebnis`. Journal im Speicher, alle Daten erfunden. Geprüft werden Werte.
@MainActor @Suite struct OffeneHandpositionenTests {
    private typealias T = AppTestdaten

    private func offenerEntwurf() -> TradeEntwurf {
        var e = TradeEntwurf(jetzt: T.zeit(2026, 3, 2, 9))
        e.offen = true
        e.symbol = "Testwert AG"
        e.groesse = 10
        e.einstiegskurs = 100
        e.gebuehren = T.d("2.5")
        e.risiko = 50
        e.neuerKontoname = "Testdepot"
        return e
    }

    private func speichere(_ e: TradeEntwurf, in m: AppModell) throws -> String {
        try m.speichereManuellenTrade(try #require(e.trade), angaben: e.angaben, kontowahl: .neu,
                                      neuerKontoname: e.neuerKontoname, waehrung: "EUR")
    }

    /// Ein offener Kauf steht in der Karte; Buchgewinn = (Kurs − Einstieg) × Größe, Gebühren als Kosten.
    @Test func offenerKaufStehtInDerKarte() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        let ticket = try speichere(offenerEntwurf(), in: m)
        let positionen = m.offenePositionen
        #expect(positionen.count == 1)
        let p = try #require(positionen.first)
        #expect(p.id == "hand-\(ticket)")
        #expect(p.symbol == "Testwert AG")
        #expect(p.seite == .buy)
        #expect(p.menge == 10)
        #expect(p.einstieg == 100)
        #expect(p.waehrung == nil)
        #expect(p.auszugskurs == nil)
        let bewertung = p.bewertung(kurs: T.d("112.5"))
        #expect(bewertung.brutto == 125)
        #expect(bewertung.netto == T.d("122.5"))
        #expect(!bewertung.unsicher)
    }

    /// Short: Gewinn bei fallendem Kurs; nach dem Schließen ist die Position weg.
    @Test func shortGewinntBeiFallendemKursUndVerschwindetNachDemSchliessen() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        var e = offenerEntwurf()
        e.markterwartung = .sell
        let ticket = try speichere(e, in: m)
        let p = try #require(m.offenePositionen.first)
        #expect(p.seite == .sell)
        let bewertung = p.bewertung(kurs: 90)
        #expect(bewertung.brutto == 100)

        var schliessen = try #require(m.handEntwurf(ticket: ticket))
        schliessen.offen = false
        schliessen.ausstiegskurs = 90
        schliessen.ausstieg = T.zeit(2026, 3, 2, 11)
        try m.speichereManuellenTrade(try #require(schliessen.trade), angaben: schliessen.angaben,
                                      kontowahl: schliessen.kontowahl, neuerKontoname: "", waehrung: "EUR",
                                      ticket: schliessen.ticket)
        #expect(m.offenePositionen.isEmpty)
    }

    /// Ein Schein bleibt ohne Wert: Der Kurs der Quelle gehört zum Basiswert.
    @Test func scheinBleibtOhneWert() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        var e = offenerEntwurf()
        e.schein = true
        e.markterwartung = .sell
        _ = try speichere(e, in: m)
        let p = try #require(m.offenePositionen.first)
        #expect(p.seite == .sell) // Richtung nach Markterwartung, gekauft ist der Schein
        let bewertung = p.bewertung(kurs: 120)
        #expect(bewertung.brutto == nil)
    }
}
