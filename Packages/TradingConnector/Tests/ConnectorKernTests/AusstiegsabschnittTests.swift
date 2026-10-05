import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.11.0: Ausstiegsanalysen der App in Auswertung und Trade-Liste (Doc 39, Paket B4).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

/// Kauf über zehn Minuten bis `schluss`, Einstieg 100.
private func trade(_ id: String, _ schluss: String, netto: Decimal, stop: Decimal?, waehrung: String? = nil) -> Trade {
    Trade(id: id, symbol: id.hasPrefix("u") ? "BTCUSD" : "SAP", side: .buy, lots: 1,
          openTime: zeit(schluss).addingTimeInterval(-600), closeTime: zeit(schluss),
          openPrice: 100, closePrice: 100 + netto, stopLoss: stop, profit: netto, waehrung: waehrung)
}

/// Eine Kerze genau über die Haltedauer, also nicht unscharf.
private func ausstieg(_ t: Trade, hoch: Decimal, tief: Decimal) throws -> JournalExport.Ausstieg {
    let kerze = Zeitkerze(beginn: t.openTime, dauer: 600, open: t.openPrice, high: hoch, low: tief, close: t.closePrice)
    return JournalExport.Ausstieg(try #require(Ausstiegsanalyse(trade: t, kerzen: [kerze])))
}

private let e1 = trade("e1", "2025-05-05T10:00:00", netto: 10, stop: 95)
private let e2 = trade("e2", "2025-05-06T10:00:00", netto: -4, stop: 95)
private let e3 = trade("e3", "2025-05-07T10:00:00", netto: 6, stop: nil)
private let u1 = trade("u1", "2025-05-05T12:00:00", netto: 500, stop: nil, waehrung: "USD")

private func datei() throws -> JournalExport {
    // e1: MFE 20, MAE 3, Stop-Abstand 5. e2: Verlierer, der 6 Punkte (1,2 R) im Plus lag. u1: ohne Stop. e3: ohne Kerzen.
    let analysen = [try ausstieg(e1, hoch: 120, tief: 97), try ausstieg(e2, hoch: 106, tief: 96),
                    try ausstieg(u1, hoch: 700, tief: 100)]
    var export = JournalExport(
        konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: [e1, e2, e3, u1],
                       ausstieg: analysen)],
        zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    // 1 EUR = 1,25 USD am 05.05.2025.
    let tag = try #require(Journaltag("2025-05-05"))
    export.referenzkurse = [JournalExport.Tageskurse(tag: tag, kurse: ["USD": try #require(Decimal(string: "1.25"))])]
    return export
}

@Test func ausstiegsabschnittMitSummeInKontowaehrung() throws {
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: try datei())
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Ausstieg (Kursverlauf während der Trades, aus Kerzen in der App)"))
    #expect(text.contains("| Trades mit Kursen | 3 von 4 |"))
    // Effizienz 0,5, −0,67 und 0,83: Median 0,5.
    #expect(text.contains("| Anteil der MFE erzielt, Median | 50,0 % |"))
    #expect(text.contains("| MAE der Gewinner, Median | 0,60 R |"))
    #expect(text.contains("| Verlierer, die 1 R im Plus lagen | 1 von 1 |"))
    // e1 10 + e2 10 + u1 100 USD, umgerechnet 80 EUR.
    #expect(text.contains("| Bis zur MFE offen, Summe vor Kosten | 100,00 EUR |"))
    #expect(!text.contains("unscharf") && !text.contains("eher zu groß"))
    #expect(text.contains("- Ausstieg: 3 von 4 Trades mit Uhrzeit haben Kerzen in der App"))
    #expect(Rezept.text.contains("keine Stop- oder Zielmarke vorschlagen"))

    let liste = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10)
    #expect(liste.contains("| Ticket | MAE | MFE | MFE erzielt | Bis MFE offen | Danach für | Danach gegen | Kerzen |"))
    #expect(liste.contains("| e1 | 0,60 R | 4,00 R | 50,0 % | 10,00 | – | – | – |"))
    // Ohne Stop als Anteil am Einstiegskurs; liegengelassen nach dem Angleich in EUR.
    #expect(liste.contains("| u1 | 0,0 % | 600,0 % | 83,3 % | 80,00 | – | – | – |"))
}

@Test func ausstiegsabschnittJeWaehrungUndOhneAnalysen() throws {
    let usd = try Anfrage.lies(["monat": "2025-05", "waehrung": "USD"], export: try datei())
    let text = Ausgabe.auswertung(usd)
    #expect(text.contains("| Trades mit Kursen | 1 von 1 |"))
    #expect(text.contains("| Bis zur MFE offen, Summe vor Kosten | 100,00 USD |"))

    let ohne = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: [e1, e2])],
                             zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: ohne)
    let leer = Ausgabe.auswertung(anfrage)
    #expect(!leer.contains("## Ausstieg") && !leer.contains("- Ausstieg:"))
    #expect(!Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10).contains("MFE erzielt"))
}

@Test func quelleUndHinweisDerKerzen() throws {
    // Doc 59 B9: Herkunft und Eigenheit der Minutenkerzen stehen im Export und in der Ausgabe.
    var original = try datei()
    var analysen = original.konten[0].ausstieg ?? []
    analysen[0].quelle = "MT4"
    analysen[0].hinweis = "MetaTrader-Kurse des eigenen Brokers, Geldkurs (Bid); Abweichung um den Spread möglich."
    analysen[1].quelle = "MT4"
    analysen[1].hinweis = analysen[0].hinweis
    analysen[2].quelle = "Binance"
    analysen[2].hinweis = "Kurs in USDT statt USD (Binance führt kein USD)."
    original.konten[0].ausstieg = analysen
    let gelesen = try JournalExport.lese(try original.json())
    #expect(gelesen.konten[0].ausstieg == analysen)
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: gelesen)
    let erwartet = "Kerzen der App: Binance 1, MT4 2 Trades. MetaTrader-Kurse des eigenen Brokers, Geldkurs (Bid); "
        + "Abweichung um den Spread möglich. Kurs in USDT statt USD (Binance führt kein USD)."
    #expect(Ausgabe.auswertung(anfrage).contains(erwartet))
    #expect(Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10).contains(erwartet))
    // Ältere Datei ohne Quelle: kein Satz.
    #expect(anfrage.kerzenquellen([]) == nil)
    #expect(!Ausgabe.auswertung(try Anfrage.lies(["monat": "2025-05"], export: try datei())).contains("Kerzen der App:"))
}
