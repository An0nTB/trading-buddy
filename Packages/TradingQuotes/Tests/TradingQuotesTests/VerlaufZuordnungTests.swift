import Foundation
import Testing
@testable import TradingQuotes

/// Codex M1 (04.10.2026): Verläufe gehören zu Quelle und Quellsymbol, nicht nur zum Journal-Symbol.
private func verlauf(_ symbol: String, _ quelle: String, _ quellSymbol: String) -> Kursverlauf {
    let kerze = Tageskerze(zeit: tag0, eroeffnung: 1, hoch: 1, tief: 1, schluss: 1)
    return Kursverlauf(journalSymbol: symbol, quelle: quelle, quellSymbol: quellSymbol, kerzen: [kerze], geladen: tag0)
}

@Test func bereinigtVerwirftVerlaeufeEinerAnderenQuelle() {
    let alt = verlauf("BTC", "kraken", "BTC/EUR")
    let eth = verlauf("ETH", "kraken", "ETH/EUR")
    let stand = Verlaufsstand(verlaeufe: ["BTC": alt, "ETH": eth], fehler: ["BTC": "alt"], geladen: empfangen)
    let zuordnungen = [Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/USD"),
                       Kurszuordnung(journalSymbol: "ETH", quelle: "kraken", quellSymbol: "ETH/EUR")]
    let neu = stand.bereinigt(fuer: zuordnungen)
    #expect(neu.verlaeufe["BTC"] == nil)
    #expect(neu.fehler["BTC"] == nil)
    #expect(neu.verlaeufe["ETH"] == eth)
    #expect(neu.geladen == empfangen)
    // Danach ist BTC neu und wird sofort geholt, nicht erst nach 20 Stunden.
    #expect(neu.zuErneuern(["BTC", "ETH"], jetzt: empfangen.addingTimeInterval(600)) == ["BTC"])
    // Quellwechsel bei gleichem Quellsymbol zählt ebenso.
    let andereQuelle = [Kurszuordnung(journalSymbol: "ETH", quelle: "alpaca", quellSymbol: "ETH/EUR")]
    #expect(stand.bereinigt(fuer: andereQuelle).verlaeufe["ETH"] == nil)
    #expect(stand.bereinigt(fuer: []) == stand)
}

@Test func laderBehaeltBeiFehlerKeinenVerlaufDerAltenQuelle() async {
    let lader = Verlaufslader(quellen: [Kursverlaeufe.kraken(abruf: testabruf(Abrufmitschnitt([(502, "")])))],
                              warte: { _ in })
    let alt = verlauf("BTC", "kraken", "BTC/EUR")
    let bisher = Verlaufsstand(verlaeufe: ["BTC": alt], fehler: [:], geladen: tag0)
    let zuordnung = Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/USD")
    let stand = await lader.lade([zuordnung], bisher: bisher, jetzt: empfangen)
    #expect(stand.verlaeufe["BTC"] == nil)
    #expect(stand.fehler["BTC"] != nil)
}
