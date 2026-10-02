import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Regression zu den Gegencheck-Zeilen G27 und G28 (Doc 49).
/// G27: Im Testbetrieb (`nebenwirkungen: false`) schreiben Kurs- und Nachrichtendienst des AppModells in eine eigene
/// Suite statt in die Einstellungen des Nutzers. G28: Jede Änderung, die der Connector sehen muss, stößt den Export an;
/// `exportAnstoesse` zählt das auch ohne Nebenwirkungen.
@Suite @MainActor struct AppModellTestbetriebTests {
    private typealias T = AppTestdaten

    private func mitDepot() throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        return m
    }

    @Test func nachrichtendienstSchreibtNurInDieTestsuite() throws {
        let schluessel = Nachrichtendienst.schluesselGesehenBis
        let testsuite = try #require(UserDefaults(suiteName: "TradingBuddyTests.AppModell"))
        defer { testsuite.removeObject(forKey: schluessel) }
        let vorher = UserDefaults.standard.object(forKey: schluessel) as? Date
        let zeit = T.zeit(2031, 1, 2, 3, 4)
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        m.nachrichten.markiereGesehen(jetzt: zeit)
        #expect(UserDefaults.standard.object(forKey: schluessel) as? Date == vorher)
        #expect(testsuite.object(forKey: schluessel) as? Date == zeit)
    }

    @Test func ohneJournalKeinExport() {
        #expect(AppModell(journal: nil, nebenwirkungen: false).exportAnstoesse == 0)
    }

    @Test func startUndImportStossenExportAn() throws {
        let leer = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        #expect(leer.exportAnstoesse == 1)
        let m = try mitDepot()
        #expect(m.exportAnstoesse > 1)
    }

    /// Regeln (X4), Ziele und Journal stoßen den Export an; abgelehnte Regeln nicht.
    @Test func aenderungenStossenExportAn() throws {
        let m = try mitDepot()

        var vorher = m.exportAnstoesse
        try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 3))
        #expect(m.exportAnstoesse > vorher)

        vorher = m.exportAnstoesse
        #expect(throws: SpeicherFehler.self) { try m.speichereRegeln(Handelsregeln(maxTradesJeTag: 0)) }
        #expect(m.exportAnstoesse == vorher)

        vorher = m.exportAnstoesse
        let jetzt = Date()
        try m.legeZielAn(Reviewziel(text: "Testziel", von: jetzt.addingTimeInterval(-86_400),
                                    bis: jetzt.addingTimeInterval(6 * 86_400)))
        #expect(m.exportAnstoesse > vorher)

        vorher = m.exportAnstoesse
        let trade = try #require(m.trades.first)
        var eintrag = try #require(m.journaleintrag(trade))
        eintrag.regeltreue = false
        m.speichereJournal(eintrag)
        #expect(m.exportAnstoesse > vorher)
    }
}
