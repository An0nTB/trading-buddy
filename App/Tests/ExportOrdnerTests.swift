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

    @MainActor @Test func offeneHandpositionMitRegelgrundlagenKommtMit() throws {
        let journal = try Journal.imSpeicher()
        let konto = try journal.legeKontoAn(broker: "Test", kontonummer: "1234", waehrung: "EUR")
        let a = ManuellerTrade(symbol: "A", einstieg: T.zeit(2026, 4, 1, 9), markterwartung: .buy,
                               groesse: 10, einstiegskurs: 100, ausstiegskurs: nil, stopKurs: 93, risiko: 5)
        let ticket = try journal.speichereHandtrade(a, konto: konto)
        try journal.speichereJournal(Journaleintrag(kontoId: try #require(konto.id), ticket: ticket, setup: "Ausbruch"))
        try journal.setzeStandardRisiko(20, konto: konto)
        let b = ManuellerTrade(symbol: "B", einstieg: T.zeit(2026, 4, 1, 10), ausstieg: T.zeit(2026, 4, 1, 11),
                               markterwartung: .buy, groesse: 10, einstiegskurs: 100, ausstiegskurs: 110, stopKurs: 96)
        let geschlossen = try journal.speichereManuellenTrade(b, konto: konto)
        try journal.setzeHandelsregeln(Handelsregeln(maxOffenePositionen: 1, maxOffenesRisiko: 100), konto: konto)
        let modell = AppModell(journal: journal, nebenwirkungen: false)
        let daten = try #require(try JournalExport.lese(ExportOrdner.export(journal, zeitzone: T.berlin).json()).konten.first)
        #expect(daten.offene == [OffenerTrade(id: ticket, openTime: a.einstieg, risiko: 70)])
        #expect(daten.offene == modell.offeneRegelpositionen)
        #expect(daten.offeneVollstaendig == true)
        #expect(daten.journal[ticket]?.setup == "Ausbruch")
        let verstoesse = Regelpruefung.pruefe(daten.trades, regeln: try #require(daten.regeln), zeitzone: T.berlin,
                                             offene: try #require(daten.offene))
        #expect(Set(verstoesse.filter { $0.trade == geschlossen.ticket }.map(\.art)) == [.offenePositionen, .offenesRisiko])
    }

    @MainActor @Test func offeneKaeufeMitGeplantemRisikoBleibenJeKonto() throws {
        let journal = try Journal.imSpeicher()
        let nurKauf = T.kraken().split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("\"sell\"") }.joined(separator: "\n")
        _ = try journal.importiereCSV(datei: Data(nurKauf.utf8), dateiname: "appt-kauf.csv",
                                      kontonummer: "1234", kontowaehrung: "EUR", zeitzone: T.berlin)
        let konto = try #require(try journal.konten().first)
        try journal.setzeStandardRisiko(25, konto: konto)
        _ = try journal.legeKontoAn(broker: "Leer", kontonummer: "5678", waehrung: "EUR")
        let export = try JournalExport.lese(ExportOrdner.export(journal, zeitzone: T.berlin).json())
        let offene = try #require(export.konten.first { $0.broker == konto.broker }?.offene)
        #expect(offene.count == 1)
        #expect(offene.first?.risiko == 25)
        #expect(offene.first?.openTime == T.zeit(2026, 4, 1, 10))
        #expect(export.konten.first { $0.broker == "Leer" }?.offene == [])
        #expect(export.konten.allSatisfy { $0.offeneVollstaendig == true })
        let modell = AppModell(journal: journal, nebenwirkungen: false)
        modell.waehleKonto(konto.id)
        #expect(offene == modell.offeneRegelpositionen)
    }

    @Test func auszugSchliesstBereitsGeschlosseneTicketsAusUndNimmtStopRisiko() {
        let a = OpenPosition(ticket: "A", rohzeile: [], side: .buy, lots: 1, symbol: "Test",
                             openTime: T.zeit(2026, 4, 1, 9), openPrice: 100, stopLoss: 93,
                             currentPrice: 110, commission: 0, swap: 0, profit: 100)
        var b = a
        b.ticket = "B"
        let geschlossen = Trade(id: "B", symbol: "Test", side: .buy, lots: 1, openTime: b.openTime,
                                 closeTime: T.zeit(2026, 4, 1, 11), openPrice: 100, closePrice: 110, profit: 100)
        let offene = AppModell.offeneRegelpositionen(auszug: [a, b], geschlossen: [geschlossen],
                                                     kaeufe: [], hand: [], quellen: Risikoquellen(konto: 20))
        #expect(offene == [OffenerTrade(id: "A", openTime: a.openTime, risiko: 70)])
    }

    @Test func mt5ExportKennzeichnetFehlendenBrokerbestandUndBehaeltHandpositionen() throws {
        let journal = try Journal.imSpeicher()
        let html = """
        <html><title>Trade History Report</title><table>
        <tr><td>Account:</td><td>1234 (EUR, Test, real, Hedge)</td></tr>
        <tr><td>Company:</td><td>Test</td></tr>
        <tr><th>Positions</th></tr>
        <tr><td>Time</td><td>Position</td><td>Symbol</td><td>Type</td><td>Volume</td><td>Price</td><td>S / L</td>
        <td>T / P</td><td>Time</td><td>Price</td><td>Commission</td><td>Swap</td><td>Profit</td></tr>
        <tr><td>2026.04.01 10:00:00</td><td>B</td><td>Testindex</td><td>buy</td><td>1</td><td>100</td><td>90</td>
        <td>0</td><td>2026.04.01 11:00:00</td><td>110</td><td>0</td><td>0</td><td>10</td></tr>
        </table></html>
        """
        try journal.importiereMT5(datei: Data(html.utf8), dateiname: "appt-mt5.html", serverZeitzone: T.utc)
        let konto = try #require(try journal.konten().first)
        let hand = ManuellerTrade(symbol: "A", einstieg: T.zeit(2026, 4, 1, 9), markterwartung: .buy,
                                  groesse: 1, einstiegskurs: 100, ausstiegskurs: nil, risiko: 20)
        let ticket = try journal.speichereHandtrade(hand, konto: konto)
        let daten = try #require(try JournalExport.lese(ExportOrdner.export(journal, zeitzone: T.berlin).json()).konten.first)
        #expect(daten.trades.map(\.id) == ["B"])
        #expect(daten.offene?.map(\.id) == [ticket])
        #expect(daten.offeneVollstaendig == false)
    }

    @Test func verkaufOhneKaufKennzeichnetUnvollstaendigenBestand() throws {
        let journal = try Journal.imSpeicher()
        let nurVerkauf = T.kraken().split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("\"buy\"") }.joined(separator: "\n")
        _ = try journal.importiereCSV(datei: Data(nurVerkauf.utf8), dateiname: "appt-verkauf.csv",
                                      kontonummer: "1234", kontowaehrung: "EUR", zeitzone: T.berlin)
        let daten = try #require(try ExportOrdner.export(journal, zeitzone: T.berlin).konten.first)
        #expect(daten.offene == [])
        #expect(daten.offeneVollstaendig == false)
    }
}
#endif
