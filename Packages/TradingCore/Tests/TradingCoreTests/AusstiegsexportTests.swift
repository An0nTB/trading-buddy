import Foundation
import Testing
@testable import TradingCore

/// Ausstiegsanalysen im Export für den Connector (Doc 39, Paket B4). Kerzen wie in `AusstiegsanalyseTests`.

private let utc = TimeZone(secondsFromGMT: 0)!
private func zeitpunkt(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "Z")! }
private func zahl(_ text: String) -> Decimal { Decimal(string: text)! }

private func minute(_ beginn: String, _ o: String, _ h: String, _ l: String, _ c: String) -> Zeitkerze {
    Zeitkerze(beginn: zeitpunkt(beginn), dauer: 60, open: zahl(o), high: zahl(h), low: zahl(l), close: zahl(c))
}

private let kauf = Trade(id: "k1", symbol: "XYZ", side: .buy, lots: 1, openTime: zeitpunkt("2026-03-02T10:00:30"),
                         closeTime: zeitpunkt("2026-03-02T10:04:20"), openPrice: 100, closePrice: 103,
                         stopLoss: 98, profit: 30)

private let kerzen = [
    minute("2026-03-02T10:00:00", "100", "100.5", "99.5", "100.2"),
    minute("2026-03-02T10:01:00", "100.2", "101", "98.5", "100.8"),
    minute("2026-03-02T10:02:00", "100.8", "104", "100.5", "103.5"),
    minute("2026-03-02T10:03:00", "103.5", "103.8", "102.5", "103"),
    minute("2026-03-02T10:04:00", "103", "103.2", "102.8", "103"),
    minute("2026-03-02T10:05:00", "103", "105.5", "102.9", "105"),
]

private func konto(ausstieg: [JournalExport.Ausstieg]) -> JournalExport.Kontodaten {
    JournalExport.Kontodaten(broker: "A", kontonummer: "1111", waehrung: "EUR", trades: [kauf], ausstieg: ausstieg)
}

@Test func ausstiegImExportRundreiseUndLiegengelassenAusDemTrade() throws {
    let analyse = try #require(Ausstiegsanalyse(trade: kauf, kerzen: kerzen))
    var anderer = kauf
    anderer.id = "x9"
    let fremd = try #require(Ausstiegsanalyse(trade: anderer, kerzen: kerzen))
    // Eine Analyse zu einem Trade, der nicht im Konto steht, fällt weg.
    let daten = konto(ausstieg: [JournalExport.Ausstieg(fremd), JournalExport.Ausstieg(analyse)])
    #expect(daten.ausstieg?.map(\.tradeID) == ["k1"])

    let export = JournalExport(konten: [daten], zeitzone: utc, erstellt: zeitpunkt("2026-03-03T00:00:00"))
    let json = String(decoding: try export.json(), as: UTF8.self)
    // Werte als Text wie die Beträge; der Betrag `liegengelassen` steht nicht in der Datei.
    let werteAlsText = json.contains("\"mae\":\"1.5\"") && json.contains("\"mfeR\":\"2\"")
    #expect(werteAlsText && !json.contains("liegengelassen"))
    let gelesen = try JournalExport.lese(Data(json.utf8))
    #expect(gelesen == export)

    let zurueck = try #require(gelesen.konten.first?.ausstiegJeTrade["k1"])
    #expect(zurueck.analyse(kauf) == analyse)
    // Mit dem angeglichenen Trade (30 USD zu 24 EUR) rechnet der Connector wie die App in Kontowährung.
    var angeglichen = kauf
    angeglichen.profit = 24
    let erwartet = try #require(Ausstiegsanalyse(trade: angeglichen, kerzen: kerzen))
    #expect(zurueck.analyse(angeglichen) == erwartet)
    #expect(erwartet.liegengelassen == 8)
}

@Test func ausstiegFehltOderIstUnlesbarOhneDasKontoZuVerlieren() throws {
    #expect(konto(ausstieg: []).ausstieg == nil)
    let analyse = try #require(Ausstiegsanalyse(trade: kauf, kerzen: kerzen))
    let export = JournalExport(konten: [konto(ausstieg: [JournalExport.Ausstieg(analyse)])], zeitzone: utc,
                               erstellt: zeitpunkt("2026-03-03T00:00:00"))
    let json = String(decoding: try export.json(), as: UTF8.self)
    let kaputt = json.replacingOccurrences(of: "\"mae\":\"1.5\"", with: "\"mae\":\"x\"")
    #expect(kaputt != json)
    let gelesen = try JournalExport.lese(Data(kaputt.utf8))
    #expect(gelesen.konten.first?.trades == [kauf])
    #expect(gelesen.konten.first?.ausstieg == nil)
}

@Test func bestExitImExportRundreiseWieInDerApp() throws {
    let analyse = try #require(Ausstiegsanalyse(trade: kauf, kerzen: kerzen))
    let best = try #require(BestExit(trade: kauf, kerzen: kerzen))
    let export = JournalExport(konten: [konto(ausstieg: [JournalExport.Ausstieg(analyse, bestExit: best)])],
                               zeitzone: utc, erstellt: zeitpunkt("2026-03-03T00:00:00"))
    let gelesen = try JournalExport.lese(try export.json())
    let zurueck = try #require(gelesen.konten.first?.ausstieg?.first?.bestExit)
    #expect(zurueck.bestExit(tradeID: "k1") == best)
    // 1 R = 2 Punkte: 1 R, 1,5 R und 2 R in der Kerze 10:02 erreicht, 3 R nicht; tatsächlich 1,5 R.
    #expect(best.stufen.map(\.ausgang) == [.ziel, .ziel, .ziel, .tatsaechlich])
    #expect(best.tatsaechlichR == zahl("1.5"))
    // Ohne Best-Exit fehlt das Feld; ein unlesbarer Wert kostet nur das Feld.
    let ohne = String(decoding: try JournalExport(konten: [konto(ausstieg: [JournalExport.Ausstieg(analyse)])],
                                                  zeitzone: utc).json(), as: UTF8.self)
    #expect(!ohne.contains("bestExit"))
    let kaputt = String(decoding: try export.json(), as: UTF8.self)
        .replacingOccurrences(of: "\"ausgang\":\"ziel\"", with: "\"ausgang\":1")
    let trotzdem = try JournalExport.lese(Data(kaputt.utf8))
    #expect(trotzdem.konten.first?.ausstieg?.first?.bestExit == nil)
    #expect(trotzdem.konten.first?.ausstieg?.first?.tradeID == "k1")
}
