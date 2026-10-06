import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.18.0: `hole_tiefenanalyse` mit denselben Rechnungen wie die Seite „Auswertung“ der App, geplantes
/// Risiko und Überhandeln nach #266. Erfundene Trades (05.10.2026).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }
private func zahl(_ text: String) -> Decimal { Decimal(string: text)! }

private func beispielExport() throws -> JournalExport {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-05-31-monthly.html")
    let auszug = try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                        serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    return JournalExport(
        konten: [.init(broker: auszug.broker, kontonummer: auszug.accountNumber, waehrung: "EUR",
                       positionen: auszug.closedPositions, geloescht: auszug.cancelledOrders)],
        zeitzone: berlin, erstellt: Date(timeIntervalSince1970: 1_790_000_000))
}

@Test func tiefenanalyseRechnetWieDerKern() throws {
    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: try beispielExport())
    let text = Ausgabe.tiefenanalyse(anfrage)
    let trades = anfrage.auswertung().trades
    #expect(text.contains("# Henry · Tiefenanalyse Mai 2026"))
    let r = RKennzahlen(trades: trades)
    if r.anzahlMitR > 0 {
        #expect(text.contains("| Erwartungswert | \(Format.r(r.erwartungswertR)) |"))
        #expect(text.contains("| Trades mit R | \(r.anzahlMitR) von 110 |"))
    } else {
        #expect(text.contains("Kein Trade mit R: weder Stop noch geplantes Risiko."))
    }
    // Kein Regelwerk und keine Journalangabe: Score ohne Regeltreue, wie der Kern ihn ohne Wert rechnet.
    let score = try #require(Leistungsscore(trades: trades, zeitzone: berlin))
    #expect(text.contains("Gesamt \(Format.zahl(score.gesamt, stellen: 0)) aus 110 Trades."))
    #expect(text.contains("Ohne Regeltreue: keine Handelsregeln und keine Journalangabe dazu."))
    #expect(!text.contains("| Regeltreue |"))
    let kosten = Tiefenanalyse.fehlermusterKosten(anfrage.auswertung())
    let teuerstes = try #require(kosten.first)
    #expect(text.contains("| \(teuerstes.muster.bezeichnung)"))
    let d = Tiefenanalyse.drawdown(trades)
    #expect(text.contains("Größter Rückgang \(Format.zahl(d.maxDrawdown))"))
    #expect(text.contains("## Wochentag × Stunde der Eröffnung (Felder ab 5 Trades)"))
    #expect(text.contains("## Stärken und Schwächen (Gruppen ab 10 Trades)"))
    #expect(text.contains("Setup fehlt, weil im Journal keins eingetragen ist."))
    // Ohne Kerzen in der App kein Best-Exit-Abschnitt.
    #expect(!text.contains("## Best-Exit"))
    #expect(text.contains(Rezept.tiefenText) && text.contains(Rezept.hinweis))
}

@Test func tiefenanalyseNimmtSetupUndRegeltreueAusDemJournal() throws {
    var export = try beispielExport()
    let alle = export.konten[0].trades
    var journal: [String: Journalangaben] = [:]
    for (i, t) in alle.enumerated() {
        journal[t.id] = Journalangaben(setup: i % 2 == 0 ? "Ausbruch" : "Rücksetzer", regeltreue: i % 4 != 0)
    }
    export.konten[0].journal = journal
    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: export)
    let text = Ausgabe.tiefenanalyse(anfrage)
    #expect(text.contains(", Setup (Journal)."))
    #expect(text.contains("| Regeltreue |") && !text.contains("Ohne Regeltreue"))
}

/// Kauf zu 100, Stop 98 (1 R = 2 Punkte = 20), Schluss 103: tatsächlich 1,5 R.
private let kauf = Trade(id: "k1", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-03-02T10:00:30"),
                         closeTime: zeit("2026-03-02T10:04:20"), openPrice: 100, closePrice: 103,
                         stopLoss: 98, profit: 30)

private func minute(_ beginn: String, _ o: String, _ h: String, _ l: String, _ c: String) -> Zeitkerze {
    Zeitkerze(beginn: zeit(beginn), dauer: 60, open: zahl(o), high: zahl(h), low: zahl(l), close: zahl(c))
}

private let kerzen = [
    minute("2026-03-02T10:00:00", "100", "100.5", "99.5", "100.2"),
    minute("2026-03-02T10:01:00", "100.2", "101", "98.5", "100.8"),
    minute("2026-03-02T10:02:00", "100.8", "104", "100.5", "103.5"),
    minute("2026-03-02T10:03:00", "103.5", "103.8", "102.5", "103"),
    minute("2026-03-02T10:04:00", "103", "103.2", "102.8", "103"),
]

private func ohneStop(_ id: String, _ tag: String, netto: Decimal) -> Trade {
    Trade(id: id, symbol: "SAP", side: .buy, lots: 1, openTime: zeit(tag + "T09:00:00"),
          closeTime: zeit(tag + "T09:30:00"), openPrice: 100, closePrice: 100 + netto, profit: netto)
        .mitGeplantemRisiko(10)
}

@Test func bestExitUndAngenommenesRisikoAusDemExport() throws {
    let analyse = try #require(Ausstiegsanalyse(trade: kauf, kerzen: kerzen))
    let best = try #require(BestExit(trade: kauf, kerzen: kerzen))
    var ohneKerzen = kauf
    ohneKerzen.id = "k2"
    let trades = [kauf, ohneKerzen, ohneStop("s1", "2026-03-03", netto: 5), ohneStop("s2", "2026-03-04", netto: -10)]
    let datei = JournalExport(
        konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades,
                       ausstieg: [JournalExport.Ausstieg(analyse, bestExit: best)])],
        zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    // Über die Datei wie im Betrieb: geplantes Risiko und Best-Exit kommen zurück.
    let export = try JournalExport.lese(try datei.json())
    let anfrage = try Anfrage.lies(["monat": "2026-03"], export: export)
    let text = Ausgabe.tiefenanalyse(anfrage)

    #expect(text.contains("| Trades mit R | 4 von 4, davon 2 angenommen |"))
    #expect(text.contains("Angenommen heißt: ohne Stop, R aus dem in der App eingetragenen geplanten Risiko."))
    // 1,5 + 1,5 + 0,5 − 1 = 2,5 R über 4 Trades.
    #expect(text.contains("| Erwartungswert | 0,63 R |"))
    #expect(text.contains("Kein Score: erst ab 20 Trades im Zeitraum (hier 4)."))

    #expect(text.contains("## Best-Exit (feste Ziele in R gegen den tatsächlichen Ausstieg)"))
    // 2 R in der Kerze 10:02 erreicht: 0,5 R mehr als tatsächlich, 0,5 × 20 = 10 Euro.
    #expect(text.contains("| 2,00 R | 1 | 1 | 0 | 0 | 2,00 R | 2,00 R | 0,50 R (10,00) |"))
    #expect(text.contains("| 3,00 R | 1 | 0 | 0 | 1 | 1,50 R | 1,50 R | 0,00 R (0,00) |"))
    #expect(text.contains("Tatsächlich: Summe 1,50 R, Ø 1,50 R aus 1 Trades; höchste Summe bei 2,00 R."))
    // s1 und s2 haben angenommenes R, aber keine Kerzen in der App; k2 hat einen Stop, aber keine Kerzen.
    #expect(text.contains("Ausgelassen: 0 ohne R, 3 ohne Minutenkerzen."))

    let auswertung = Ausgabe.auswertung(anfrage)
    #expect(auswertung.contains("- Davon 2 von 4 Trades mit R ohne Stop: R aus dem geplanten Risiko"))
    // Drei Tage mit Trades: Überhandeln ist nicht geprüft, nicht „ohne Treffer“.
    #expect(auswertung.contains("Nicht geprüft: Überhandeln, erst ab 10 Tagen mit Trades (hier 3)."))
    let ohneTreffer = try #require(auswertung.components(separatedBy: "\n").first { $0.hasPrefix("Ohne Treffer:") })
    #expect(!ohneTreffer.contains("Überhandeln"))
}

@Test func ueberhandelnNenntDieGrenzeStattEinesWerts() throws {
    // Zehn Tage mit je einer Position, am elften vier: Median 1 plus 2 ergibt Grenze 3, die vierte ist überhandelt.
    var trades: [Trade] = []
    for tag in 1...10 {
        let datum = String(format: "2026-03-%02d", tag + 1)
        trades.append(ohneStop("t\(tag)", datum, netto: 1))
    }
    for nummer in 1...4 {
        let t = Trade(id: "x\(nummer)", symbol: "SAP", side: .buy, lots: 1,
                      openTime: zeit("2026-03-20T0\(nummer + 4):00:00"), closeTime: zeit("2026-03-20T0\(nummer + 4):30:00"),
                      openPrice: 100, closePrice: 99, profit: -1)
        trades.append(t)
    }
    let export = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades)],
                               zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let text = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-03"], export: export))
    #expect(text.contains("- Überhandeln: 1 Trades, netto -1,00"))
    #expect(text.contains("betroffen ab Position 4 eines Tages"))
    #expect(text.contains("Regel: Positionen eines Tages über dem üblichen Maß (Median der Positionen je Tag plus 2), "
        + "geprüft erst ab 10 Tagen mit Trades."))
    #expect(!text.contains("Nicht geprüft: Überhandeln"))
}

@Test func geplantesRisikoBeiFremdwaehrungErstNachDemAngleich() throws {
    // Geplantes Risiko 20 Euro an beiden Trades; der USD-Trade bringt 50 USD = 40 Euro bei 1,25 USD je Euro.
    let eur = ohneStop("e1", "2025-05-05", netto: 10).mitGeplantemRisiko(20)
    var usd = ohneStop("u1", "2025-05-05", netto: 50).mitGeplantemRisiko(20)
    usd.waehrung = "USD"
    var export = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: [eur, usd])],
                               zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let tag = try #require(Journaltag("2025-05-05"))
    export.referenzkurse = [JournalExport.Tageskurse(tag: tag, kurse: ["USD": zahl("1.25")])]
    // In Kontowährung wie die App: 40 ÷ 20 = 2 R und 10 ÷ 20 = 0,5 R.
    let inEuro = Ausgabe.tiefenanalyse(try Anfrage.lies(["monat": "2025-05"], export: export))
    #expect(inEuro.contains("| Trades mit R | 2 von 2, davon 2 angenommen |"))
    #expect(inEuro.contains("| Erwartungswert | 1,25 R |"))
    // Nur USD ohne Umrechnung: Euro-Risiko gegen Dollar-Ergebnis gäbe ein falsches R, also keins.
    let inDollar = Ausgabe.tiefenanalyse(try Anfrage.lies(["monat": "2025-05", "waehrung": "USD"], export: export))
    #expect(inDollar.contains("Kein Trade mit R: weder Stop noch geplantes Risiko."))
}
