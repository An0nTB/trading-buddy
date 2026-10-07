import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Verdächtige Handeinträge bleiben erreichbar, zählen aber erst nach ausdrücklicher Bestätigung mit.
@Suite @MainActor struct HandDuplikateTests {
    private typealias T = AppTestdaten

    private func modellMitDuplikat() throws -> (AppModell, Trade, String) {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-duplikat.csv",
                                kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR",
                                zeitzone: T.berlin)
        let broker = try #require(m.trades.first)
        let hand = ManuellerTrade(symbol: broker.symbol, einstieg: broker.openTime, ausstieg: broker.closeTime,
                                  markterwartung: broker.side, groesse: broker.lots,
                                  einstiegskurs: broker.openPrice, ausstiegskurs: broker.closePrice, gebuehren: 2)
        let ticket = try m.speichereManuellenTrade(hand, angaben: TradeAngaben(setup: "Ausbruch", risikoEinstieg: 20),
                                                  kontowahl: .bestehend(try #require(m.konto?.id)),
                                                  neuerKontoname: "", waehrung: "EUR")
        return (m, broker, ticket)
    }

    @Test func verdachtBleibtInDerListeUndFehltInKennzahlen() throws {
        let (m, broker, ticket) = try modellMitDuplikat()
        #expect(m.tradeListe.count == 2)
        #expect(m.moeglicheDuplikate[ticket] == [broker.id])
        #expect(m.trades.map(\.id) == [broker.id])
        #expect(m.kennzahlen.anzahl == 1)
        #expect(m.kennzahlen.netto == 48)
        let hand = try #require(m.tradeListe.first { $0.id == ticket })
        #expect(hand.risk == 20)
        #expect(m.journaleintrag(hand)?.setup == "Ausbruch")
    }

    @Test func eigenstaendigBehaltenZaehltAuchNachNeuladenMit() throws {
        let (m, _, ticket) = try modellMitDuplikat()
        try m.behalteHandtrade(try #require(m.tradeListe.first { $0.id == ticket }))
        m.laden()
        #expect(m.moeglicheDuplikate.isEmpty)
        #expect(m.tradeListe.count == 2)
        #expect(m.kennzahlen.anzahl == 2)
        #expect(m.kennzahlen.netto == 96)
    }

    @Test func loeschenEntferntNurDenHandeintrag() throws {
        let (m, broker, ticket) = try modellMitDuplikat()
        try m.loescheHandtrade(try #require(m.tradeListe.first { $0.id == ticket }))
        #expect(m.moeglicheDuplikate.isEmpty)
        #expect(m.tradeListe.map(\.id) == [broker.id])
        #expect(m.kennzahlen.netto == 48)
    }

    #if os(macOS)
    @Test func connectorExportSchliesstVerdachtBisZurBestaetigungAus() throws {
        let (m, broker, ticket) = try modellMitDuplikat()
        let journal = try #require(m.journal)
        let vorher = try ExportOrdner.export(journal, zeitzone: T.berlin)
        #expect(vorher.konten.first?.trades.map(\.id) == [broker.id])
        try m.behalteHandtrade(try #require(m.tradeListe.first { $0.id == ticket }))
        let nachher = try ExportOrdner.export(journal, zeitzone: T.berlin)
        #expect(nachher.konten.first?.trades.count == 2)
    }
    #endif
}
