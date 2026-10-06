import Foundation
import Testing
@testable import TradingCore

/// Export der Felder aus #265/#267: Basiswert und Markterwartung von Hebelprodukten, geplantes Risiko.
/// Erfundene Trades (05.10.2026).
private func tcZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func tcTrade(_ id: String, stop: Decimal? = nil) -> Trade {
    Trade(id: id, symbol: "TURBO NASDAQ 100 SHORT 21000", side: .buy, lots: 10,
          openTime: tcZeit("2026-03-02T10:00:00Z"), closeTime: tcZeit("2026-03-02T11:00:00Z"),
          openPrice: 2, closePrice: Decimal(string: "2.5")!, stopLoss: stop, profit: 5,
          basiswert: "Nasdaq 100", markterwartung: .sell)
}

@Test func tradeCodableBehaeltBasiswertMarkterwartungUndGeplantesRisiko() throws {
    let mitRisiko = tcTrade("A").mitGeplantemRisiko(Decimal(string: "12.5")!)
    let ohne = Trade(id: "B", symbol: "SAP", side: .sell, lots: 1, openTime: tcZeit("2026-03-03T10:00:00Z"),
                     closeTime: tcZeit("2026-03-03T11:00:00Z"), openPrice: 100, closePrice: 99, profit: 1)
    let daten = try JSONEncoder().encode([mitRisiko, ohne])
    let zurueck = try JSONDecoder().decode([Trade].self, from: daten)
    #expect(zurueck == [mitRisiko, ohne])
    #expect(zurueck[0].geplantesRisiko == Decimal(string: "12.5")!)
    #expect(zurueck[0].basiswert == "Nasdaq 100" && zurueck[0].markterwartung == .sell)
    // Abgeleitet, kein eigenes Feld: ohne Stop zählt das geplante Risiko als angenommen.
    #expect(zurueck[0].risikoAngenommen && zurueck[0].risk == Decimal(string: "12.5")!)
    #expect(!zurueck[1].risikoAngenommen && zurueck[1].risk == nil)
    // Ohne Angabe fehlen die Felder; ältere Connector-Versionen lesen den Export unverändert.
    let text = String(decoding: daten, as: UTF8.self)
    #expect(text.components(separatedBy: "\"geplantesRisiko\":\"12.5\"").count == 2)
    #expect(text.components(separatedBy: "\"basiswert\"").count == 2)
    #expect(text.components(separatedBy: "\"markterwartung\"").count == 2)
    #expect(!text.contains("risikoAngenommen"))
}

@Test func tradeCodableUnlesbaresGeplantesRisikoKostetNurDasFeld() throws {
    let original = try JSONEncoder().encode(tcTrade("C"))
    let gelesen = try JSONSerialization.jsonObject(with: original)
    var objekt = try #require(gelesen as? [String: Any])
    objekt["geplantesRisiko"] = "kein Betrag"
    objekt["markterwartung"] = "seitwaerts"
    let daten = try JSONSerialization.data(withJSONObject: objekt)
    let t = try JSONDecoder().decode(Trade.self, from: daten)
    #expect(t.id == "C" && t.geplantesRisiko == nil && t.markterwartung == nil && t.basiswert == "Nasdaq 100")
}
