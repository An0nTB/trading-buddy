import Foundation
import Testing
import TradingCore
@testable import Trading_Buddy

/// Anzeigeformate (`Format`). Geprüft werden Vorzeichen und Währungszeichen, nicht der Wortlaut,
/// weil Sprache und Region des Rechners die Schreibweise bestimmen.
@Suite struct FormatAnzeigeTests {
    private typealias T = AppTestdaten

    @Test func gewinnHatPlusVerlustMinusNullKeinVorzeichen() {
        #expect(Format.geld(T.d("12.5"), "EUR").hasPrefix("+"))
        #expect(!Format.geld(T.d("-12.5"), "EUR").hasPrefix("+"))
        #expect(Format.geld(T.d("-12.5"), "EUR").contains("12"))
        #expect(!Format.geld(0, "EUR").hasPrefix("+"))
        // `betrag` zeigt nie ein Plus, auch nicht bei Gewinn.
        #expect(!Format.betrag(T.d("12.5"), "EUR").hasPrefix("+"))
    }

    /// W1 (Doc 40): Ein Betrag in US-Dollar trägt nie das Eurozeichen, auch auf einem Euro-Konto.
    @Test func fremdwaehrungstraegtIhrEigenesZeichen() {
        let trade = Trade(id: "APPT-1", symbol: "ETH/USD", side: .buy, lots: 1, openTime: T.zeit(2026, 4, 1),
                          closeTime: T.zeit(2026, 4, 2), openPrice: 3000, closePrice: 2880, profit: -120, waehrung: "usd")
        let text = Format.geld(trade.netProfit, trade.waehrung(kontowaehrung: "EUR"))
        #expect(!text.contains("€"))
        #expect(text.contains("$") || text.contains("USD"))
        #expect(Format.geld(trade.netProfit, "EUR").contains("€"))
    }

    @Test func fehlendeWerteZeigenEinenStrich() {
        #expect(Format.prozent(nil) == "–")
        #expect(Format.zahl(nil) == "–")
        #expect(Format.r(nil) == "–")
        #expect(Format.dauer(nil) == "–")
    }

    /// Mengen unter 1 (Krypto) zeigen ihre Stellen bis zur achten; Forex-Lots bleiben bei ein bis zwei.
    /// Verglichen werden nur die Ziffern, weil das Trennzeichen von der Region abhängt.
    @Test func lotsZeigtKleineMengenUndLaesstForexLotsUnveraendert() {
        func ziffern(_ text: String) -> String { text.filter(\.isNumber) }
        #expect(ziffern(Format.lots(T.d("0.0001"))) == "00001")
        #expect(ziffern(Format.lots(T.d("0.00012345"))) == "000012345")
        #expect(ziffern(Format.lots(T.d("0.5"))) == "05")
        #expect(ziffern(Format.lots(T.d("-0.0025"))) == "00025")
        // Forex-Lots wie bisher: eine Nachkommastelle mindestens, zwei höchstens.
        #expect(ziffern(Format.lots(T.d("0.1"))) == "01")
        #expect(ziffern(Format.lots(T.d("0.25"))) == "025")
        #expect(ziffern(Format.lots(T.d("1"))) == "10")
        #expect(ziffern(Format.lots(T.d("2.5"))) == "25")
        #expect(ziffern(Format.lots(T.d("100"))) == "1000")
        #expect(ziffern(Format.lots(T.d("1.23456789"))) == "123")
    }

    @Test func rVielfacheMitVorzeichenUndEinheit() {
        #expect(Format.r(T.d("1.5")).hasPrefix("+"))
        #expect(Format.r(T.d("1.5")).hasSuffix(" R"))
        #expect(!Format.r(T.d("-0.8")).hasPrefix("+"))
        #expect(Format.r(T.d("-0.8")).hasSuffix(" R"))
    }
}
