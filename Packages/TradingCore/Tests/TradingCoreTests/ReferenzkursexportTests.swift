import Foundation
import Testing
@testable import TradingCore

/// EZB-Referenzkurse im Export für den Währungsangleich im Connector (AP12, Zweiter Gegencheck X2 und W4).

private let utc = TimeZone(secondsFromGMT: 0)!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ schluss: String, waehrung: String?) -> Trade {
    Trade(id: id, symbol: "BTCUSD", side: .buy, lots: 1, openTime: zeit(schluss).addingTimeInterval(-600),
          closeTime: zeit(schluss), openPrice: 100, closePrice: 110, profit: 100, waehrung: waehrung)
}

/// Mai 2025, jeden Tag USD 2, CHF 1 und JPY 160 je Euro.
private func maikurse() -> Referenzkurse {
    let start = Journaltag("2025-05-01")!
    var kurse: [Journaltag: [String: Decimal]] = [:]
    for i in 0..<31 {
        let tag = Journaltag(start.beginn(in: utc).addingTimeInterval(Double(i) * 86_400), zeitzone: utc)
        kurse[tag] = ["USD": 2, "CHF": 1, "JPY": 160]
    }
    return Referenzkurse(kurse: kurse)
}

@Test func referenzkursauszugNurTageUndWaehrungenDerFremdwaehrung() throws {
    let konten: [JournalExport.Kontodaten] = [
        .init(broker: "A", kontonummer: "1111", waehrung: "EUR",
              trades: [trade("e", "2025-05-05T12:00:00", waehrung: nil),
                       trade("u", "2025-05-20T12:00:00", waehrung: "USD")]),
        .init(broker: "B", kontonummer: "2222", waehrung: "chf",
              trades: [trade("t", "2025-05-28T12:00:00", waehrung: "USDT")])
    ]
    let auszug = JournalExport.referenzkursauszug(maikurse(), fuer: konten)
    // u braucht 12. bis 21. Mai, t 20. bis 29. Mai; JPY kommt nicht vor, EUR ist immer 1.
    #expect(auszug.count == 18)
    #expect(auszug.first?.tag == Journaltag("2025-05-12") && auszug.last?.tag == Journaltag("2025-05-29"))
    #expect(auszug.allSatisfy { $0.kurse == ["USD": 2, "CHF": 1] })

    let export = JournalExport(konten: konten, zeitzone: utc, erstellt: zeit("2025-06-01T00:00:00"),
                               referenzkurse: auszug)
    let json = String(decoding: try export.json(), as: UTF8.self)
    #expect(json.contains("\"kurse\":{\"CHF\":\"1\",\"USD\":\"2\"},\"tag\":\"2025-05-12\""))
    let gelesen = try JournalExport.lese(Data(json.utf8))
    #expect(gelesen == export && gelesen.format == 2)
    let kurse = try #require(gelesen.angleichskurse)
    #expect(kurse.umrechnen(100, von: "USD", nach: "EUR", am: zeit("2025-05-20T12:00:00"), zeitzone: utc) == 50)

    let nurEuro = [JournalExport.Kontodaten(broker: "A", kontonummer: "1111", waehrung: "EUR",
                                            trades: [trade("e", "2025-05-05T12:00:00", waehrung: "eur")])]
    #expect(JournalExport.referenzkursauszug(maikurse(), fuer: nurEuro).isEmpty)
    #expect(JournalExport(konten: nurEuro, zeitzone: utc).referenzkurse == nil)
}

@Test func referenzkursauszugAuchFuerDieSteuerInKontenOhneEuro() throws {
    // Befund G4 (Doc 49): CHF-Konto mit CHF-Trades braucht den CHF-Kurs für die Euro-Summen der Steuer.
    let konten = [JournalExport.Kontodaten(broker: "B", kontonummer: "2222", waehrung: "CHF",
                                           trades: [trade("c", "2025-05-20T12:00:00", waehrung: nil)])]
    let auszug = JournalExport.referenzkursauszug(maikurse(), fuer: konten)
    #expect(auszug.count == 10 && auszug.allSatisfy { $0.kurse == ["CHF": 1] })
    let kurse = try #require(JournalExport(konten: konten, zeitzone: utc, referenzkurse: auszug).angleichskurse)
    #expect(kurse.inEuro(100, waehrung: "CHF", am: zeit("2025-05-20T12:00:00"), zeitzone: utc) == 100)
}

@Test func neueresFormatVorDemRestErkannt() throws {
    // Befund G7 (Doc 49): Ein Feld in neuer Form darf die Meldung „neueres Format“ nicht verdecken.
    let export = JournalExport(konten: [], zeitzone: utc, erstellt: zeit("2026-10-01T20:00:00"))
    let text = String(decoding: try export.json(), as: UTF8.self)
        .replacingOccurrences(of: "\"format\":\(JournalExport.aktuellesFormat)", with: #""format":3"#)
        .replacingOccurrences(of: #""konten":[]"#, with: #""konten":"neue Form""#)
    #expect(text.contains(#""format":3"#) && text.contains("neue Form"))
    #expect(throws: ExportFehler.neueresFormat(3)) { try JournalExport.lese(Data(text.utf8)) }
}

@Test func anzeigewaehrungMitKursenImExport() throws {
    // Befund H21 (Doc 52): Euro-Konto nur mit Euro-Trades, Anzeige in USD braucht den USD-Kurs der Schlusstage.
    let konten = [JournalExport.Kontodaten(broker: "A", kontonummer: "1111", waehrung: "EUR",
                                           trades: [trade("e", "2025-05-20T12:00:00", waehrung: nil)])]
    #expect(JournalExport.referenzkursauszug(maikurse(), fuer: konten).isEmpty)
    let auszug = JournalExport.referenzkursauszug(maikurse(), fuer: konten, anzeigewaehrung: "usd")
    #expect(auszug.count == 10 && auszug.allSatisfy { $0.kurse == ["USD": 2] })
    // Anzeige in der Währung der Trades braucht keinen Kurs.
    #expect(JournalExport.referenzkursauszug(maikurse(), fuer: konten, anzeigewaehrung: "EUR").isEmpty)

    let export = JournalExport(konten: konten, zeitzone: utc, erstellt: zeit("2025-06-01T00:00:00"),
                               referenzkurse: auszug, anzeigewaehrung: " usd ")
    #expect(export.anzeigewaehrung == "USD")
    #expect(try JournalExport.lese(try export.json()) == export)
    // Ohne Wahl fehlt das Feld; ältere Connectoren übergehen es, das Format bleibt.
    let ohne = JournalExport(konten: konten, zeitzone: utc, anzeigewaehrung: "")
    let ohneText = String(decoding: try ohne.json(), as: UTF8.self)
    #expect(ohne.anzeigewaehrung == nil && !ohneText.contains("anzeigewaehrung"))
    #expect(export.format == 2)
}
