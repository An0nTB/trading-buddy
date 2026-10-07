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

    @Test func datumsimportBleibtInNewYorkImKalendermonat() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false, testZeitzone: zone)
        let csv = T.scalable.replacingOccurrences(of: "2026-04-01", with: "2026-09-30")
            .replacingOccurrences(of: "2026-04-02", with: "2026-10-01")
            .replacingOccurrences(of: "15:00:00", with: "00:00:00")
        _ = try m.importiereCSV(daten: Data(csv.utf8), dateiname: "appt-datum.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.utc)
        let trade = try #require(m.trades.first)
        #expect(trade.nurDatum && trade.closeTime == T.zeit(2026, 10, 1))
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zone
        let oktober = try #require(kalender.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(m.monate == [oktober])
        m.zeitraum = .monat(oktober)
        let ergebnis = Monatskalender(trades: m.kalenderTrades, jahr: 2026, monat: 10, kalender: kalender)
        #expect(m.trades.map(\.id) == [trade.id])
        #expect(m.kontoTrades.map(\.id) == [trade.id])
        #expect(m.angeglicheneTrades.map(\.id) == [trade.id])
        #expect(m.kennzahlen.anzahl == ergebnis.anzahl && ergebnis.anzahl == 1)
        #expect(m.kennzahlen.netto == ergebnis.netto && ergebnis.netto == T.d("48"))
        m.zeitraum = .monat(try #require(kalender.date(from: DateComponents(year: 2026, month: 9, day: 1))))
        #expect(m.trades.isEmpty && m.kontoTrades.isEmpty && m.angeglicheneTrades.isEmpty)
    }

}
