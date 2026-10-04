import Foundation
import Testing
@testable import TradingCore

/// Exportdatei, Zeiträume und Auswertung (AP12). Sollwerte für den erfundenen Beispielauszug Mai 2026
/// unabhängig mit Python gerechnet (04.10.2026), Zeiten mit Serverzeit UTC+3 wie in den übrigen Tests.
private let utc = TimeZone(secondsFromGMT: 0)!
private let berlin = TimeZone(identifier: "Europe/Berlin")!

private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = utc
    return formatter.date(from: iso + "Z")!
}

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

private func beispielMai() throws -> MT4Statement {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MT4/beispiel-2026-05-31-monthly.html")
    return try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                  serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
}

@Test func exportUeberstehtDieRundreiseExakt() throws {
    let auszug = try beispielMai()
    let export = JournalExport(
        konten: [.init(broker: auszug.broker, kontonummer: auszug.accountNumber, waehrung: "EUR",
                       positionen: auszug.closedPositions, geloescht: auszug.cancelledOrders)],
        zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let daten = try export.json()
    let text = String(decoding: daten, as: UTF8.self)

    #expect(try JournalExport.lese(daten) == export)
    #expect(text.contains(#""commission":"-0.06""#))
    #expect(text.contains(#""zeitzone":"Europe\/Berlin""#) || text.contains(#""zeitzone":"Europe/Berlin""#))
    #expect(export.konten[0].trades.count == 110 && export.konten[0].geloeschteOrders.count == 68)
    #expect(export.konten[0].kurzname.hasSuffix("…5678"))
    #expect(export.rechenkern == TradingCore.version)
}

@Test func journalangabenUeberstehenDieRundreise() throws {
    let trade = Trade(id: "7", symbol: "de40", side: .buy, lots: 1, openTime: zeit("2025-05-02T08:00:00"),
                      closeTime: zeit("2025-05-02T09:00:00"), openPrice: 100, closePrice: 110, profit: 10)
    let konto = JournalExport.Kontodaten(
        broker: "GBE", kontonummer: "0001", waehrung: "EUR", trades: [trade],
        journal: ["7": Journalangaben(setup: "Ausbruch", regeltreue: false, zustand: 2, grund: "FOMO"),
                  "8": Journalangaben()],
        ziele: [Reviewziel(id: 1, text: "Höchstens 2 Revanche-Trades", von: zeit("2025-04-30T22:00:00"),
                           bis: zeit("2025-05-31T22:00:00"), messgroesse: "Revanche-Trades", zielwert: 2,
                           status: .verfehlt, ergebnis: "13 statt 2", erstellt: zeit("2025-04-30T20:00:00"))])
    #expect(konto.journal.keys.sorted() == ["7"])  // leere Angaben fallen weg
    let export = JournalExport(konten: [konto], zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let daten = try export.json()
    #expect(try JournalExport.lese(daten) == export)

    // Datei einer älteren App ohne Journal und Ziele: liest sich mit leerem Journal und ohne Ziele.
    var roh = try #require(try JSONSerialization.jsonObject(with: daten) as? [String: Any])
    var konten = try #require(roh["konten"] as? [[String: Any]])
    konten[0]["journal"] = nil
    konten[0]["ziele"] = nil
    roh["konten"] = konten
    let alt = try JSONSerialization.data(withJSONObject: roh)
    #expect(String(decoding: alt, as: UTF8.self).contains("journal") == false)
    #expect(String(decoding: alt, as: UTF8.self).contains("ziele") == false)
    #expect(try JournalExport.lese(alt).konten[0].journal.isEmpty)
    #expect(try JournalExport.lese(alt).konten[0].ziele.isEmpty)

    // Neue Datei mit Journal, gelesen wie von einem Connector vor dem Journal (Aufbau eingefroren).
    struct AlterExport: Decodable {
        struct Konto: Decodable {
            var broker: String, kontonummer: String, waehrung: String
            var trades: [Trade]
            var geloeschteOrders: [Date]
        }
        var format: Int
        var zeitzone: String
        var konten: [Konto]
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let gelesen = try decoder.decode(AlterExport.self, from: daten)
    #expect(gelesen.format == JournalExport.aktuellesFormat && gelesen.konten[0].trades == [trade])
}

@Test func neueresFormatWirdAbgelehnt() throws {
    let export = JournalExport(konten: [], zeitzone: utc, erstellt: zeit("2026-10-01T20:00:00"))
    let text = String(decoding: try export.json(), as: UTF8.self)
        .replacingOccurrences(of: "\"format\":\(JournalExport.aktuellesFormat)", with: #""format":99"#)
    #expect(throws: ExportFehler.neueresFormat(99)) { try JournalExport.lese(Data(text.utf8)) }
}

@Test func monatInBerlinMitVormonat() throws {
    let mai = try #require(Zeitspanne.monat(jahr: 2025, monat: 5, zeitzone: berlin))
    #expect(mai.von == zeit("2025-04-30T22:00:00") && mai.bis == zeit("2025-05-31T22:00:00"))
    #expect(mai.vorzeitraum(zeitzone: berlin) == Zeitspanne(von: zeit("2025-03-31T22:00:00"), bis: mai.von))
    // März mit Umstellung auf Sommerzeit: beginnt in Winterzeit, endet in Sommerzeit.
    let maerz = try #require(Zeitspanne.monat(jahr: 2025, monat: 3, zeitzone: berlin))
    #expect(maerz.von == zeit("2025-02-28T23:00:00") && maerz.bis == zeit("2025-03-31T22:00:00"))
    #expect(Zeitspanne.monat(jahr: 2025, monat: 13, zeitzone: berlin) == nil)
    #expect(Zeitspanne.monat(mit: zeit("2025-05-31T22:30:00"), zeitzone: berlin).von == zeit("2025-05-31T22:00:00"))
    #expect(mai.enthaelt(mai.von) && !mai.enthaelt(mai.bis))
}

@Test func wocheUndTage() throws {
    let woche = Zeitspanne.woche(mit: zeit("2025-05-14T12:00:00"), zeitzone: berlin)
    #expect(woche == Zeitspanne(von: zeit("2025-05-11T22:00:00"), bis: zeit("2025-05-18T22:00:00")))
    #expect(Zeitspanne.tage(von: DateComponents(year: 2025, month: 5, day: 12),
                          bis: DateComponents(year: 2025, month: 5, day: 18), zeitzone: berlin) == woche)
    #expect(woche.vorzeitraum(zeitzone: berlin)
        == Zeitspanne(von: zeit("2025-05-04T22:00:00"), bis: zeit("2025-05-11T22:00:00")))
    #expect(Zeitspanne.tage(von: DateComponents(year: 2025, month: 2, day: 30),
                          bis: DateComponents(year: 2025, month: 3, day: 2), zeitzone: berlin) == nil)
    #expect(Zeitspanne.tage(von: DateComponents(year: 2025, month: 5, day: 18),
                          bis: DateComponents(year: 2025, month: 5, day: 12), zeitzone: berlin) == nil)
}

@Test func auswertungBeispielMai() throws {
    let auszug = try beispielMai()
    let alle = auszug.closedPositions.map { Trade($0) }
    let a = Auswertung(trades: alle, geloeschteOrders: auszug.cancelledOrders.map(\.cancelledAt),
                       zeitraum: try #require(Zeitspanne.monat(jahr: 2026, monat: 5, zeitzone: utc)), zeitzone: utc)

    #expect(a.kennzahlen.anzahl == 110 && a.kennzahlen.netto == d("46.33"))
    #expect(a.kennzahlen.erwartungswertR?.gerundet(4) == d("0.0186"))
    #expect(a.kennzahlenVorzeitraum.anzahl == 0)
    #expect(a.geloeschteOrders == 68 && a.stornoquote?.gerundet(4) == d("0.3820"))
    #expect(a.kapitalverlauf.maxDrawdown == d("40.57"))
    #expect(a.befunde.map(\.muster)
        == Fehlermuster.pruefe(alle, geloeschteOrders: 68, zeitzone: utc).map(\.muster))

    let revanche = try #require(a.befunde.first { $0.muster == .revancheTrade })
    #expect(revanche.trades.count == 6 && revanche.netto == d("-1.87"))
    #expect(a.ohne(revanche)?.netto == d("48.20") && a.ohne(revanche)?.anzahl == 104)
    let verlierer = try #require(a.befunde.first { $0.muster == .verliererLaufenLassen })
    #expect(a.ohne(verlierer) == nil)

    #expect(a.beste(1).first?.id == "51789146" && a.beste(1).first?.netProfit == d("27.76"))
    #expect(a.schlechteste(1).first?.id == "51788391" && a.schlechteste(1).first?.netProfit == d("-32.13"))
    #expect(a.muster(try #require(alle.first { $0.id == revanche.trades[0] })).contains(.revancheTrade))
}

@Test func auswertungWocheMitVorwoche() throws {
    let alle = try beispielMai().closedPositions.map { Trade($0) }
    let a = Auswertung(trades: alle, zeitraum: Zeitspanne.woche(mit: zeit("2026-05-13T12:00:00"), zeitzone: berlin),
                       zeitzone: berlin)
    #expect(a.kennzahlen.anzahl == 24 && a.kennzahlen.netto == d("26.36"))
    #expect(a.kennzahlenVorzeitraum.anzahl == 26 && a.kennzahlenVorzeitraum.netto == d("-9.29"))
    #expect(a.trades.map(\.closeTime) == a.trades.map(\.closeTime).sorted())
}
