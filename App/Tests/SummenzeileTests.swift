import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Regression zum Gegencheck G9 (Doc 49): Die Summenzeile unter der Trade-Liste rechnet über `modell.anzeige.trades`
/// in der Anzeigewährung und zählt Trades ohne EZB-Kurs getrennt. Geprüft wird der Vertrag, auf den sich die Ansicht
/// stützt: Die angeglichenen Trades behalten ihre IDs, sodass der Filter auf die sichtbare Liste greift, und die
/// Summe steht in `summenwaehrung` statt in der Tradewährung.
@Suite @MainActor struct SummenzeileTests {
    private typealias T = AppTestdaten

    private static let kurse = Referenzkurse(kurse: [T.tag(2026, 4, 2): ["USD": T.d("1.25"), "GBP": T.d("0.8")],
                                                     T.tag(2026, 4, 3): ["USD": T.d("1.25"), "GBP": T.d("0.8")]])

    /// Zwei USD-Trades (je 43,90 USD) auf einem EUR-Konto.
    private func modell(kurse: Bool) throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        if kurse { m.ezb.kurse = Self.kurse }
        for kennung in ["A", "B"] {
            _ = try m.importiereCSV(daten: Data(T.kraken(kennung: kennung).utf8), dateiname: "appt-kraken-\(kennung).csv",
                                    kontonummer: "KR-00001111", kontoname: "Kraken", waehrung: "EUR", zeitzone: T.berlin)
        }
        return m
    }

    /// Rechnet wie `Summenzeile.body`: angeglichene Trades der sichtbaren Liste, Rest ohne Kurs.
    private func summe(_ trades: [Trade], _ m: AppModell) -> (netto: Decimal, ohneKurs: Int) {
        let ids = Set(trades.map(\.id))
        let angeglichen = m.anzeige.trades.filter { ids.contains($0.id) }
        return (Kennzahlen(trades: angeglichen).netto, trades.count - angeglichen.count)
    }

    @Test func summeInKontowaehrungStattTradewaehrung() throws {
        let m = try modell(kurse: true)
        #expect(m.trades.count == 2)
        #expect(m.summenwaehrung == "EUR")
        let alle = summe(m.trades, m)
        #expect(alle.netto == T.d("70.24"))
        #expect(alle.ohneKurs == 0)
        // Die Zeilen selbst bleiben in USD (W1); ohne Angleich stünde hier 87,80.
        #expect(Kennzahlen(trades: m.trades).netto == T.d("87.8"))
    }

    /// Gefilterte Liste: Die Summe enthält nur die sichtbaren Trades.
    @Test func summeFolgtDerSichtbarenListe() throws {
        let m = try modell(kurse: true)
        let sichtbar = try #require(m.trades.first)
        let teil = summe([sichtbar], m)
        #expect(teil.netto == T.d("35.12"))
        #expect(teil.ohneKurs == 0)
    }

    @Test func summeInGewaehlterAnzeigewaehrung() throws {
        let m = try modell(kurse: true)
        m.anzeigewaehrung = "GBP"
        #expect(m.summenwaehrung == "GBP")
        #expect(summe(m.trades, m).netto == T.d("56.192"))
    }

    /// Ohne EZB-Kurs fehlen die Trades in der Summe und werden als „ohne Kurs“ gezählt.
    @Test func ohneKursFehlenTradesInDerSumme() throws {
        let m = try modell(kurse: false)
        let alle = summe(m.trades, m)
        #expect(alle.netto == 0)
        #expect(alle.ohneKurs == 2)
    }
}
