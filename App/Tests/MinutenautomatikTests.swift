import Foundation
import Testing
import TradingCore
@testable import Trading_Buddy

private let jetztFest = T.zeit(2026, 10, 5, 12)

/// Automatischer Abruf der Minutenkerzen (Tim 05.10.2026): wann er anläuft und welche Trades er nimmt.
@Suite struct MinutenautomatikTests {
    private func trade(_ id: String, auf: Date, zu: Date, nurDatum: Bool = false) -> Trade {
        Trade(id: id, symbol: "BTC/EUR", side: .buy, lots: 1, openTime: auf, closeTime: zu,
              openPrice: 100, closePrice: 110, profit: 10, nurDatum: nurDatum)
    }

    @Test func startUndNeueTradesSindEinAnlass() {
        #expect(Minutenautomatik.neuerAnlass(bekannt: nil, ids: ["A"]))
        #expect(!Minutenautomatik.neuerAnlass(bekannt: nil, ids: []))
        #expect(Minutenautomatik.neuerAnlass(bekannt: ["A"], ids: ["A", "B"]))
    }

    @Test func bekannteTradesSindKeinAnlass() {
        // Erneutes Laden oder Kontowechsel zurück: nichts Neues, kein Abruf.
        #expect(!Minutenautomatik.neuerAnlass(bekannt: ["A", "B"], ids: ["A"]))
        #expect(!Minutenautomatik.neuerAnlass(bekannt: ["A", "B"], ids: ["A", "B"]))
    }

    @Test func nimmtNurTradesWieDerKnopfUndHoechstens31TageAlt() {
        let passend = trade("passend", auf: T.zeit(2026, 10, 4, 9), zu: T.zeit(2026, 10, 4, 10))
        let ohneUhrzeit = trade("ohneUhrzeit", auf: T.zeit(2026, 10, 4), zu: T.zeit(2026, 10, 4), nurDatum: true)
        let zuAlt = trade("zuAlt", auf: T.zeit(2026, 8, 1, 9), zu: T.zeit(2026, 8, 1, 10))
        // Schluss vor 30 Minuten: das Fenster (Ausstieg plus eine Stunde) läuft noch.
        let nochOffen = trade("nochOffen", auf: T.zeit(2026, 10, 5, 11), zu: T.zeit(2026, 10, 5, 11, 30))
        // Haltedauer über 31 Tage: zu langes Fenster für die Quelle.
        let zuLang = trade("zuLang", auf: T.zeit(2026, 8, 20), zu: T.zeit(2026, 10, 1))
        let ids = Minutenautomatik.kandidaten([passend, ohneUhrzeit, zuAlt, nochOffen, zuLang], jetzt: jetztFest).map(\.id)
        #expect(ids == ["passend"])
    }

    @Test func grenzeVon31TagenGiltAbSchluss() {
        let knapp = trade("knapp", auf: T.zeit(2026, 9, 4, 11), zu: T.zeit(2026, 9, 4, 12, 30))
        let drueber = trade("drueber", auf: T.zeit(2026, 9, 4, 10), zu: T.zeit(2026, 9, 4, 11))
        let ids = Minutenautomatik.kandidaten([knapp, drueber], jetzt: jetztFest).map(\.id)
        #expect(ids == ["knapp"])
    }
}
