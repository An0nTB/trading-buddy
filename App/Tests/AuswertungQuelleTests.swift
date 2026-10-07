import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Daten der Seite „Auswertung“ (Doc 02 Nr. 65) gegen ein Journal im Arbeitsspeicher, synthetische Testdaten.
@Suite @MainActor struct AuswertungQuelleTests {
    private typealias T = AppTestdaten

    private func modell() throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    /// Ohne eingestellte Regeln und Journalbewertungen gibt es keine Regeltreue; der Score rechnet dann ohne diese Achse.
    @Test func auswertungRegeltreueOhneRegelnFehlt() throws {
        let m = try modell()
        #expect(m.angeglicheneTrades.count == 1)
        #expect(Auswertungsquelle.regeltreue(m) == nil)
    }

    /// Wochentag und Stunde aus der Heatmap zählen dieselben Trades wie die Heatmap selbst.
    @Test func auswertungZeitBalkenZaehlenWieHeatmap() throws {
        let m = try modell()
        let heatmap = Tiefenanalyse.heatmap(m.angeglicheneTrades, zeitzone: m.zeitzone)
        let tage = Auswertungsquelle.zusammengefasst(heatmap, nachWochentag: true)
        let stunden = Auswertungsquelle.zusammengefasst(heatmap, nachWochentag: false)
        let summe = heatmap.zellen.map(\.anzahl).reduce(0, +)
        #expect(tage.map(\.anzahl).reduce(0, +) == summe)
        #expect(stunden.map(\.anzahl).reduce(0, +) == summe)
        #expect(Set(tage.flatMap(\.tradeIDs)) == Set(m.angeglicheneTrades.filter { !$0.nurDatum }.map(\.id)))
    }

    /// Gruppen nach Setup: Trades ohne Setup landen in „ohne Setup“, Netto wie die Kennzahlen.
    @Test func auswertungGruppenOhneSetup() throws {
        let m = try modell()
        let setups = Auswertungsquelle.setups(m)
        let gruppen = Auswertungsquelle.gruppen(m.angeglicheneTrades, schluessel: { setups[$0.id] ?? Gruppenname.ohneSetup },
                                                name: { $0 })
        #expect(gruppen.map(\.id) == [Gruppenname.ohneSetup])
        #expect(gruppen.first?.netto == m.kennzahlen.netto)
        #expect(gruppen.first?.tradeIDs == m.angeglicheneTrades.map(\.id))
    }

    /// Ein Drill-down ist gleich, wenn Titel und Trades gleich sind; die ID trägt beides.
    @Test func auswertungDrilldownKennung() {
        let a = Drilldown(titel: "Montag", tradeIDs: ["1", "2"])
        let b = Drilldown(titel: "Montag", tradeIDs: ["1", "2"])
        #expect(a == b)
        #expect(a.id != Drilldown(titel: "Montag", tradeIDs: ["1"]).id)
    }

    @Test(arguments: [false, true]) func journalbewertungZaehltOhneRegeln(regeltreu: Bool) throws {
        let m = try modell()
        let trade = try #require(m.trades.first)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.regeltreue = regeltreu
        m.speichereJournal(eintrag)
        #expect(m.regeln.leer)
        #expect(Auswertungsquelle.regeltreue(m) == (regeltreu ? Decimal(1) : Decimal(0)))
        m.instrument = "Nicht im Zeitraum"
        #expect(Auswertungsquelle.regeltreue(m) == nil)
    }

    @Test func manuelleVerstoesseGehenOhneRegelnInDenScoreEin() throws {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.scalable.utf8), dateiname: "appt-score.csv",
                                      kontonummer: "DE0012345678", kontowaehrung: "EUR", zeitzone: T.berlin)
        let konto = try #require(try journal.konten().first)
        for tag in 1...Leistungsscore.mindestanzahl {
            let trade = ManuellerTrade(symbol: "Score", einstieg: T.zeit(2026, 5, tag, 10),
                                       ausstieg: T.zeit(2026, 5, tag, 11), markterwartung: .buy,
                                       groesse: 1, einstiegskurs: 100, ausstiegskurs: tag % 2 == 0 ? 110 : 95)
            let ticket = try journal.speichereManuellenTrade(trade, konto: konto).ticket
            try journal.speichereJournal(Journaleintrag(kontoId: try #require(konto.id), ticket: ticket,
                                                       regeltreue: tag != 1))
        }
        let m = AppModell(journal: journal, nebenwirkungen: false)
        m.instrument = "Score"
        let quote = try #require(Auswertungsquelle.regeltreue(m))
        #expect(quote == Decimal(Leistungsscore.mindestanzahl - 1) / Decimal(Leistungsscore.mindestanzahl))
        let score = try #require(Leistungsscore(trades: m.angeglicheneTrades, zeitzone: m.zeitzone, regeltreue: quote))
        let spanne = try #require(Zeitspanne.monat(jahr: 2026, monat: 5, zeitzone: m.zeitzone))
        let bericht = Zeitraumbericht(trades: m.angeglicheneTrades, zeitraum: spanne, zeitzone: m.zeitzone,
                                      kontowaehrung: "EUR", manuell: m.manuellVerletzt)
        let vergleich = try #require(Leistungsscore(trades: bericht.auswertung.trades, zeitzone: m.zeitzone,
                                                   regeltreue: bericht.disziplin.quote))
        #expect(score.komponenten.contains { $0.komponente == .regeltreue })
        #expect(score.gesamt == vergleich.gesamt)
        m.instrument = "Testwert AG"
        #expect(m.angeglicheneTrades.count == 1)
        #expect(Auswertungsquelle.regeltreue(m) == nil)
    }

}
