import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Stop aus dem Journal (`Trade.mitJournal`) und Journalangaben für den Connector. App und Export
/// rechnen beide damit; weicht eins ab, zeigen App und Claude verschiedene R-Werte.
@Suite struct JournalregelTests {
    private typealias T = AppTestdaten

    private let trade = Trade(id: "APPT-7", symbol: "DE40", side: .buy, lots: 1, openTime: T.zeit(2026, 4, 1, 9),
                              closeTime: T.zeit(2026, 4, 1, 10), openPrice: 100, closePrice: 110,
                              stopLoss: 105, profit: 10)

    @Test func ohneEintragBleibtDerStopAusDemExport() {
        #expect(trade.mitJournal(nil) == trade)
    }

    @Test func eintragOhneStopAendertNichts() {
        let eintrag = Journaleintrag(kontoId: 1, ticket: "APPT-7", setup: "Ausbruch")
        #expect(trade.mitJournal(eintrag).stopLoss == 105)
    }

    @Test func nachgetragenerStopErsetztDenLetztenStop() {
        let eintrag = Journaleintrag(kontoId: 1, ticket: "APPT-7", stopEinstieg: 95)
        let ergebnis = trade.mitJournal(eintrag)
        #expect(ergebnis.stopLoss == 95)
        // Nur der Stop ändert sich; Ergebnis und Zeiten bleiben.
        #expect(ergebnis.netProfit == trade.netProfit)
        #expect(ergebnis.openTime == trade.openTime)
    }

    @Test func angabenUebernehmenAlleFelderAusserStop() {
        let eintrag = Journaleintrag(kontoId: 1, ticket: "APPT-7", setup: "Ausbruch", regeltreue: false, zustand: 2,
                                     marktumfeld: "Trend", grund: "Bruch des Hochs", stopEinstieg: 95)
        let angaben = eintrag.angaben
        #expect(angaben.setup == "Ausbruch")
        #expect(angaben.regeltreue == false)
        #expect(angaben.zustand == 2)
        #expect(angaben.marktumfeld == "Trend")
        #expect(angaben.grund == "Bruch des Hochs")
    }

    @Test func eintragOhneAngabenGiltAlsLeer() {
        #expect(Journaleintrag(kontoId: 1, ticket: "APPT-7").ohneAngaben)
        #expect(!Journaleintrag(kontoId: 1, ticket: "APPT-7", stopEinstieg: 95).ohneAngaben)
        #expect(Journaleintrag(kontoId: 1, ticket: "APPT-7").gleicheAngaben(wie: nil))
    }

    @Test func bereinigtMachtLeereTexteZuNil() {
        let eintrag = Journaleintrag(kontoId: 1, ticket: "APPT-7", setup: "  ", marktumfeld: " Trend ", grund: "\n")
        let sauber = eintrag.bereinigt
        #expect(sauber.setup == nil)
        #expect(sauber.marktumfeld == "Trend")
        #expect(sauber.grund == nil)
        #expect(sauber.ohneAngaben == false)
    }
}
