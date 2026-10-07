import Foundation
import Observation
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

    /// Ohne eingestellte Regeln gibt es keine Regeltreue; der Score rechnet dann ohne diese Achse.
    @Test func auswertungRegeltreueOhneRegelnFehlt() throws {
        let m = try modell()
        #expect(m.angeglicheneTrades.count == 1)
        #expect(Auswertungsquelle.regeltreue(m) == nil)
    }

    @Test func offeneTagAuswertungBeobachtetAenderungenAusZweitemFenster() async throws {
        let auswertungsfenster = try modell()
        let tradesfenster = auswertungsfenster
        let trade = try #require(tradesfenster.trades.first)
        for tags in [["Ausbruch"], ["Ruecklauf"], []] {
            await confirmation("Tag-Auswertung wird neu aufgebaut") { aktualisiert in
                withObservationTracking {
                    _ = Auswertungsquelle.merkmale(auswertungsfenster, art: .tags)
                } onChange: {
                    aktualisiert()
                }
                tradesfenster.setzeTags(tags, trade: trade)
            }
            let auswertung = Merkmalauswertung(trades: auswertungsfenster.angeglicheneTrades,
                merkmale: Auswertungsquelle.merkmale(auswertungsfenster, art: .tags))
            #expect(auswertung.merkmale.map(\.merkmal) == tags)
            #expect(auswertung.ohneMerkmal == (tags.isEmpty ? 1 : 0))
            if !tags.isEmpty {
                #expect(auswertung.merkmale.first?.anzahl == 1)
                #expect(auswertung.merkmale.first?.netto == trade.netProfit)
                #expect(auswertung.merkmale.first?.tradeIDs == [trade.id])
            }
        }
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
}
