import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Steuer-PDF Seite 1: ein Krypto-Trade ohne EZB-Kurs zählt bei „Ohne Euro-Kurs“ einmal, obwohl er im Topf Krypto
/// und als Los der Haltefrist ohne Euro-Wert auftaucht (App-Tests-Befund zu #210).
@Suite @MainActor struct SteuerOhneKursTests {
    private typealias T = AppTestdaten

    @Test func kryptoTradeOhneKursZaehltEinmal() throws {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "O").utf8), dateiname: "appt-steuer-ohnekurs.csv",
                                kontonummer: "KR-00005555", kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        let anlage = try #require(m.steuerAnlage(2026))
        let topf = try #require(anlage.toepfe.first { $0.topf == .krypto })
        #expect(topf.ohneEuro == 1)
        let krypto = try #require(anlage.krypto)
        #expect(krypto.ohneEuro >= 1)
        #expect(anlage.ohneKurs == 1)
    }
}
