import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Geplantes Risiko (Doc 02 Nr. 64), freie Tags (Nr. 65) und die eigene Grenze für „Überhandeln“ im
/// `AppModell`, gegen ein Journal im Arbeitsspeicher ohne Export. Geprüft werden Werte, keine Texte.
@Suite @MainActor struct GeplantesRisikoAppTests {
    private typealias T = AppTestdaten

    private func mitDepot() throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "risiko-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    /// Der Standard des Kontos gilt als angenommenes Risiko; entfernt ist er wieder weg.
    @Test func standardDesKontosIstAngenommen() throws {
        let m = try mitDepot()
        let ohne = try #require(m.trades.first)
        #expect(ohne.risk == nil)

        try m.setzeStandardRisiko(T.d("50"))
        let mit = try #require(m.trades.first { $0.id == ohne.id })
        #expect(mit.risk == T.d("50"))
        #expect(mit.risikoAngenommen)
        #expect(m.wirksamesRisiko(mit)?.herkunft == .konto)
        // Auch die angeglichenen Trades (Grundlage der Kennzahlen) rechnen damit.
        #expect(m.angeglicheneTrades.first { $0.id == ohne.id }?.risk == T.d("50"))

        try m.setzeStandardRisiko(nil)
        #expect(m.trades.first { $0.id == ohne.id }?.risk == nil)
        #expect(m.fehler == nil)
    }

    @Test(arguments: [true, false])
    func geloeschtesSetupAktualisiertRisikoKennzahlenUndExport(mitKontorisiko: Bool) throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        let setup = try m.speichereSetup(Setup(name: "Ausbruch"))
        let setupId = try #require(setup.id)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.setup = setup.name
        m.speichereJournal(eintrag)
        if mitKontorisiko { try m.setzeStandardRisiko(50) }
        try m.setzeStandardRisiko(100, setupId: setupId)
        #expect(m.trades.first?.risk == 100)
        #expect(m.kennzahlen.erwartungswertR == trade.netProfit / 100)
        let exportVorher = m.exportAnstoesse

        try m.loescheSetup(setup)

        #expect(m.trades.first?.risk == (mitKontorisiko ? 50 : nil))
        #expect(m.angeglicheneTrades.first?.risk == (mitKontorisiko ? 50 : nil))
        #expect(m.wirksamesRisiko(trade)?.herkunft == (mitKontorisiko ? .konto : nil))
        #expect(m.kennzahlen.erwartungswertR == (mitKontorisiko ? trade.netProfit / 50 : nil))
        #expect(m.exportAnstoesse == exportVorher + 1)
        #expect(m.fehler == nil)
    }

    /// Das Risiko am Trade geht dem Standard des Kontos vor.
    @Test func risikoAmTradeGehtVor() throws {
        let m = try mitDepot()
        try m.setzeStandardRisiko(T.d("50"))
        let trade = try #require(m.trades.first)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.risikoEinstieg = T.d("20")
        m.speichereJournal(eintrag)
        let neu = try #require(m.trades.first { $0.id == trade.id })
        #expect(neu.risk == T.d("20"))
        #expect(m.wirksamesRisiko(neu)?.herkunft == .trade)
    }

    /// Ein Eintrag nur mit Risiko ist nicht leer; ein Risiko von null fällt beim Bereinigen weg.
    @Test func risikoZaehltAlsAngabe() throws {
        var eintrag = Journaleintrag(kontoId: 1, ticket: "1")
        #expect(eintrag.ohneAngaben)
        eintrag.risikoEinstieg = T.d("30")
        #expect(!eintrag.ohneAngaben)
        eintrag.risikoEinstieg = 0
        #expect(eintrag.bereinigt.risikoEinstieg == nil)
        var mitZeiteinheit = Journaleintrag(kontoId: 1, ticket: "1")
        mitZeiteinheit.zeiteinheit = " M5 "
        #expect(!mitZeiteinheit.ohneAngaben)
        #expect(mitZeiteinheit.bereinigt.zeiteinheit == "M5")
        #expect(!mitZeiteinheit.gleicheAngaben(wie: Journaleintrag(kontoId: 1, ticket: "1")))
    }

    /// Tags ohne Leerzeichen und doppelte Schreibweisen; Vorschläge kennen sie danach.
    @Test func tagsSetzenUndVorschlagen() throws {
        let m = try mitDepot()
        let trade = try #require(m.trades.first)
        m.setzeTags(["Ausbruch", " ausbruch ", "FOMO"], trade: trade)
        #expect(m.tradeTags[trade.id] == ["Ausbruch", "FOMO"])
        #expect(Set(m.tagVorschlaege) == ["Ausbruch", "FOMO"])
        m.setzeTags([], trade: trade)
        #expect(m.tradeTags[trade.id] == nil)
        #expect(m.fehler == nil)
    }

    /// „Höchstens Trades je Tag“ ist die Schwelle für „Überhandeln“.
    @Test func eigeneGrenzeIstSchwelleFuerUeberhandeln() throws {
        let m = try mitDepot()
        #expect(m.musterSchwellen.maxTradesProTag == nil)
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 3))
        #expect(m.musterSchwellen.maxTradesProTag == 3)
    }
}
