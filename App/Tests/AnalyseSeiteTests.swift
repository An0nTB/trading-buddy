import Testing
@testable import Trading_Buddy

/// Seite „Analyse“ unter Markt (Tim 05.10.2026): Wertliste aus allen bekannten Quellen und Platz in der Seitenleiste.
@Suite struct AnalyseSeiteTests {
    @Test func wertlisteFasstAlleQuellenZusammen() {
        let liste = AnalyseWerte.liste(trades: ["BTCUSDT", "AAPL", "BTCUSDT"], positionen: ["EURUSD"],
                                       merkliste: [" NVDA ", ""], chartwerte: ["AAPL", "ETHUSDT"])
        #expect(liste == ["AAPL", "BTCUSDT", "ETHUSDT", "EURUSD", "NVDA"])
    }

    @Test func ohneWerteBleibtDieListeLeer() {
        #expect(AnalyseWerte.liste(trades: [], positionen: [], merkliste: [], chartwerte: []).isEmpty)
    }

    @Test func analyseStehtUnterMarktNachKurschart() {
        let markt = Bereich.markt
        let kurschart = markt.firstIndex(of: .kurschart)
        #expect(kurschart != nil)
        #expect(markt.firstIndex(of: .analyse) == kurschart.map { $0 + 1 })
        #expect(Bereich.unterMehr.contains(.analyse))
        #expect(Bereich.analyse.symbol != Bereich.kurschart.symbol)
    }
}
