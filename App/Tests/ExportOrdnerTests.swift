#if os(macOS)
import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Export für den Claude-Connector (`ExportOrdner.export`), gegen ein Journal im Arbeitsspeicher.
/// Geprüft wird, was die Gegenchecks Doc 36 und 40 an der Schnittstelle App → Connector fanden:
/// Stop aus dem Journal, Währung je Trade, Regeln und Notizen im Export, Beträge als Text statt JSON-Zahl.
@Suite struct ExportOrdnerTests {
    private typealias T = AppTestdaten

    private func journalMitScalable() throws -> (Journal, Konto) {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                  kontonummer: "DE0012345678", kontowaehrung: "EUR", zeitzone: T.berlin)
        let konto = try #require(try journal.konten().first)
        return (journal, konto)
    }

    @Test func exportEnthaeltDenTradeMitBetragUndKurzerKontonummer() throws {
        let (journal, _) = try journalMitScalable()
        let export = try ExportOrdner.export(journal, zeitzone: T.berlin)

        #expect(export.zeitzone == "Europe/Berlin")
        let konto = try #require(export.konten.first)
        #expect(export.konten.count == 1)
        #expect(konto.broker == "Scalable Capital")
        // Nur die letzten vier Stellen der Kontonummer verlassen die App.
        #expect(konto.kontonummer == "5678")
        #expect(konto.waehrung == "EUR")
        let trade = try #require(konto.trades.first)
        #expect(konto.trades.count == 1)
        #expect(trade.netProfit == T.d("48"))
        #expect(trade.waehrung(kontowaehrung: konto.waehrung) == "EUR")
    }

    @Test func stopAusDemJournalErsetztDenStopImExport() throws {
        let (journal, konto) = try journalMitScalable()
        let vorher = try #require(try ExportOrdner.export(journal, zeitzone: T.berlin).konten.first?.trades.first)
        try journal.speichereJournal(Journaleintrag(kontoId: try #require(konto.id), ticket: vorher.id,
                                                    setup: "Ausbruch", stopEinstieg: T.d("48.5")))

        let kontodaten = try #require(try ExportOrdner.export(journal, zeitzone: T.berlin).konten.first)
        let nachher = try #require(kontodaten.trades.first)
        #expect(nachher.stopLoss == T.d("48.5"))
        #expect(kontodaten.journal[vorher.id]?.setup == "Ausbruch")
    }

    @Test func regelnNotizenUndVerpassteTradesKommenMit() throws {
        let (journal, konto) = try journalMitScalable()
        try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 3), konto: konto)
        _ = try journal.speichereTagesnotiz(Tagesnotiz(tag: T.tag(2026, 4, 1), plan: "Nur Ausbrüche", erstellt: T.zeit(2026, 4, 1, 7)),
                                        jetzt: T.zeit(2026, 4, 1, 7))
        try journal.speichereVerpasstenTrade(VerpassterTrade(id: "APPT-V1", zeit: T.zeit(2026, 4, 1, 12), symbol: "DE40",
                                                             seite: .buy, grund: .zoegern, ergebnisR: T.d("1.5")))

        let export = try ExportOrdner.export(journal, zeitzone: T.berlin)
        #expect(export.konten.first?.regeln?.maxTradesJeTag == 3)
        #expect(export.tagesnotizen?.map(\.tag) == [T.tag(2026, 4, 1)])
        #expect(export.verpassteTrades?.first?.id == "APPT-V1")
        #expect(export.verpassteTrades?.first?.ergebnisR == T.d("1.5"))
    }

    @Test func geaenderteRegelnStehenBeimNaechstenExportDrin() throws {
        let (journal, konto) = try journalMitScalable()
        try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 3), konto: konto)
        _ = try ExportOrdner.export(journal, zeitzone: T.berlin)
        try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 5), konto: konto)
        #expect(try ExportOrdner.export(journal, zeitzone: T.berlin).konten.first?.regeln?.maxTradesJeTag == 5)
    }

    @Test func fremdwaehrungBleibtAmTradeStehen() throws {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.kraken().utf8), dateiname: "appt-kraken.csv",
                                  kontonummer: "KR-00001111", kontowaehrung: "EUR")
        let konto = try #require(try ExportOrdner.export(journal, zeitzone: T.berlin).konten.first)
        let trade = try #require(konto.trades.first)
        // Kontowährung EUR, Trade in USD: der Connector darf den Betrag nicht als Euro lesen (W1, W4).
        #expect(konto.waehrung == "EUR")
        #expect(trade.waehrung == "USD")
        #expect(trade.netProfit == T.d("43.9"))
    }

    @Test func gleicheEndziffernBeimSelbenBrokerBekommenMehrStellen() throws {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.kraken(kennung: "A").utf8), dateiname: "appt-a.csv",
                                  kontonummer: "11145678", kontowaehrung: "EUR")
        _ = try journal.importiereCSV(datei: Data(T.kraken(kennung: "B").utf8), dateiname: "appt-b.csv",
                                  kontonummer: "99995678", kontowaehrung: "EUR")
        let nummern = try ExportOrdner.export(journal, zeitzone: T.berlin).konten.map(\.kontonummer).sorted()
        #expect(nummern == ["45678", "95678"])
    }

    /// Beträge als Text, damit `Decimal` exakt zurückkommt (Lehre: Decimal nie als JSON-Zahl).
    @Test func betraegeStehenImJSONAlsText() throws {
        let (journal, _) = try journalMitScalable()
        try journal.speichereVerpasstenTrade(VerpassterTrade(id: "APPT-V2", zeit: T.zeit(2026, 4, 1, 12), symbol: "DE40",
                                                             seite: .sell, grund: .zuSpaet, ergebnisR: T.d("-0.7")))
        let daten = try ExportOrdner.export(journal, zeitzone: T.berlin).json()
        let wurzel = try #require(try JSONSerialization.jsonObject(with: daten) as? [String: Any])
        let konten = try #require(wurzel["konten"] as? [[String: Any]])
        let trades = try #require(konten.first?["trades"] as? [[String: Any]])
        let trade = try #require(trades.first)
        for feld in ["lots", "openPrice", "closePrice", "commission", "swap", "profit"] {
            #expect(trade[feld] is String, "Feld \(feld) ist keine Zeichenkette")
        }
        let verpasst = try #require((wurzel["verpassteTrades"] as? [[String: Any]])?.first)
        #expect(verpasst["ergebnisR"] is String)
        // Und der Connector liest dieselben Werte zurück.
        let gelesen = try JournalExport.lese(daten)
        #expect(gelesen.konten.first?.trades.first?.netProfit == T.d("48"))
        #expect(gelesen.verpassteTrades?.first?.ergebnisR == T.d("-0.7"))
    }

    @MainActor @Test func gekaufterShortScheinBleibtImExportShort() throws {
        let (journal, konto) = try journalMitScalable()
        let schein = ManuellerTrade(symbol: "Short-Schein", einstieg: T.zeit(2026, 4, 3, 10),
                                    ausstieg: T.zeit(2026, 4, 3, 11), markterwartung: .sell, schein: true,
                                    groesse: 100, einstiegskurs: 2, ausstiegskurs: 3)
        let ticket = try journal.speichereManuellenTrade(schein, konto: konto).ticket
        let m = AppModell(journal: journal, nebenwirkungen: false)
        let export = try JournalExport.lese(ExportOrdner.export(journal, zeitzone: m.zeitzone).json())
        let daten = try #require(export.konten.first)
        let trade = try #require(daten.trades.first { $0.id == ticket })
        #expect(trade.side == .buy && trade.markterwartung == .sell && trade.richtung == .sell)
        let spanne = try #require(Zeitspanne.monat(jahr: 2026, monat: 4, zeitzone: m.zeitzone))
        let auswertung = Auswertung(trades: daten.trades, zeitraum: spanne, zeitzone: m.zeitzone)
        #expect(Tiefenanalyse.anteileRichtung(auswertung.trades) == Tiefenanalyse.anteileRichtung(m.angeglicheneTrades))
        let short = auswertung.trades.filter { $0.richtung == .sell }
        let appShort = m.angeglicheneTrades.filter { $0.richtung == .sell }
        #expect(short.map(\.id) == [ticket] && appShort.map(\.id) == [ticket])
        #expect(Kennzahlen(trades: short).netto == 100 && Kennzahlen(trades: appShort).netto == 100)
    }

}
#endif
