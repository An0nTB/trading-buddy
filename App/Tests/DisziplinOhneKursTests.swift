import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Doc 52 H4 (Kern 0.24.0): Trades ohne EZB-Kurs zählen in der Disziplin bei Anzahl und Verstößen mit, ihr Betrag
/// fließt nicht in Kapital und Netto. Vorher fehlten sie ganz, und das PDF zeigte „Mit Verstoß 0“ neben einem Verstoß.
@Suite @MainActor struct DisziplinOhneKursTests {
    private typealias T = AppTestdaten

    /// Kraken-Konto in Euro: BTC/EUR (Kontowährung) und ETH/USD, beide am 01.04.2026 eröffnet, der USD-Trade später.
    private static let kraken: String = {
        let kopf = #""txid","ordertxid","pair","aclass","subclass","time","type","ordertype","price","cost","fee","vol","margin","misc","ledgers","posttxid","posstatuscode","cprice","ccost","cfee","cvol","cmargin","net","trades""#
        func zeile(_ nr: Int, _ paar: String, _ zeit: String, _ art: String, _ preis: String, _ kosten: String) -> String {
            #""TDOK\#(nr)-AAAAA-00000\#(nr)","ODOK\#(nr)-AAAAA-00000\#(nr)","\#(paar)","forex","crypto","\#(zeit)","\#(art)","limit","\#(preis)","\#(kosten)","1.00000","0.50000000","0.00000","","LDOK\#(nr)-AAAAA-00000\#(nr)","","","","","","","","","""#
        }
        return [kopf,
                zeile(1, "XXBTZEUR", "2026-04-01 09:00:00.0000", "buy", "60000.00", "30000.00000"),
                zeile(2, "XETHZUSD", "2026-04-01 10:00:00.0000", "buy", "3000.00", "1500.00000"),
                zeile(3, "XXBTZEUR", "2026-04-02 09:00:00.0000", "sell", "61000.00", "30500.00000"),
                zeile(4, "XETHZUSD", "2026-04-03 10:00:00.0000", "sell", "3100.00", "1550.00000"),
                ""].joined(separator: "\n")
    }()

    @Test func tradeOhneKursZaehltAlsVerstossOhneBetrag() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(Self.kraken.utf8), dateiname: "appt-disziplin.csv", kontonummer: "KR-00002222",
                                kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.trades.count == 2)
        // Ohne EZB-Kurs fehlt der USD-Trade in Kontowährung.
        let euro = try #require(m.kontoTrades.first)
        #expect(m.kontoTrades.count == 1)
        #expect(m.waehrungsstand.ohneKurs == 1)

        // Ein Trade je Tag: der später eröffnete USD-Trade verstößt.
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 1))
        let disziplin = m.disziplin
        #expect(disziplin.punkte.count == 2)
        #expect(disziplin.verletzt == 1)
        #expect(disziplin.regeltreu == 1)
        #expect(disziplin.nettoVerletzt == 0)
        #expect(disziplin.nettoRegeltreu == euro.netProfit)
    }
}
