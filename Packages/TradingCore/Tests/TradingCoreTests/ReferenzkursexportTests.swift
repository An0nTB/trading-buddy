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
