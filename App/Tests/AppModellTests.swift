import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Zustand der App (`AppModell`) gegen ein Journal im Arbeitsspeicher, ohne Export und EZB-Abruf
/// (`nebenwirkungen: false`, Patch AppTests_AppModell_init). Befunde A1, A3, X3, W3 aus Doc 36 und 40.
@Suite @MainActor struct AppModellTests {
    private typealias T = AppTestdaten

    private func modell() throws -> AppModell {
        AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
    }

    @Test func importZeigtDieTradesDesNeuenKontos() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.konten.count == 1)
        #expect(m.trades.count == 1)
        #expect(m.trades.first?.netProfit == T.d("48"))
    }

    /// X3: Nach dem Import eines zweiten Kontos wechselt die App dorthin und setzt die Filter zurück.
    @Test func importInNeuesKontoSetztFilterZurueck() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        m.instrument = "Testwert AG"
        m.zeitraum = .monat(T.zeit(2026, 3, 1))
        _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.konto?.broker == "Kraken")
        #expect(m.instrument == nil)
        #expect(m.zeitraum == .alle)
        #expect(m.trades.count == 1)
    }

    /// A3: Kontowechsel setzt Instrument, Zeitraum und Musterfilter zurück.
    @Test func kontowechselSetztFilterZurueck() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        let depot = try #require(m.konten.first { $0.broker == "Scalable Capital" }?.id)
        m.instrument = "ETH/USD"
        m.musterFilter = .ohneStop
        m.waehleKonto(depot)
        #expect(m.instrument == nil)
        #expect(m.musterFilter == nil)
        #expect(m.zeitraum == .alle)
        #expect(m.trades.count == 1)
    }

    @Test func monatsfilterZeigtNurTradesDesMonats() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        let monat = try #require(m.monate.first)
        m.zeitraum = .monat(monat)
        #expect(m.trades.count == 1)
        m.zeitraum = .monat(T.zeit(2026, 2, 1))
        #expect(m.trades.isEmpty)
    }

    /// A1 und Stop aus dem Journal: Speichern zieht Trades sofort nach, leerer Eintrag wird gelöscht.
    @Test func journalStopWirktSofortUndLeererEintragVerschwindet() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        let trade = try #require(m.trades.first)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.stopEinstieg = T.d("48.5")
        eintrag.setup = "Ausbruch"
        m.speichereJournal(eintrag)
        #expect(m.trades.first?.stopLoss == T.d("48.5"))
        #expect(m.journaleintraege[trade.id]?.setup == "Ausbruch")

        m.speichereJournal(Journaleintrag(kontoId: eintrag.kontoId, ticket: trade.id))
        #expect(m.journaleintraege[trade.id] == nil)
        #expect(m.trades.first?.stopLoss == nil)
        #expect(m.fehler == nil)
    }

    /// W3: Summen nur in Kontowährung. Ohne EZB-Kurs fehlt der USD-Trade in den Summen, bleibt in der Liste
    /// und wird im Währungsstand gezählt (Grundlage des Mischwährungshinweises).
    @Test func fremdwaehrungOhneKursFehltInDenSummen() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.kraken().utf8), dateiname: "appt-kraken.csv", kontonummer: "KR-00001111",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.trades.count == 1)
        #expect(m.trades.first?.waehrung == "USD")
        #expect(m.angeglicheneTrades.isEmpty)
        let stand = m.waehrungsstand
        #expect(stand.ohneKurs == 1)
        #expect(stand.umgerechnet == 0)
        #expect(stand.waehrungen.contains("USD"))
    }

    @Test func kontowaehrungBrauchtKeineUmrechnung() throws {
        let m = try modell()
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.angeglicheneTrades.map(\.id) == m.trades.map(\.id))
        #expect(m.waehrungsstand.leer)
    }
}
