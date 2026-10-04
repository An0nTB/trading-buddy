import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Rechenkern 0.22.0: Kurstag in deutscher Zeit auch westlich von UTC (Dritter Gegencheck G6), Regelprüfung
/// über `ohneBetrag` wie in der App (G1, G2).

private let newYork = TimeZone(identifier: "America/New_York")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ schluss: String, netto: Decimal, waehrung: String? = nil) -> Trade {
    Trade(id: id, symbol: "SAP", side: .buy, lots: 1, openTime: zeit(schluss).addingTimeInterval(-600),
          closeTime: zeit(schluss), openPrice: 100, closePrice: 100 + netto, profit: netto, waehrung: waehrung)
}

@Test func kurstagInDeutscherZeitAuchInNewYork() throws {
    // 07.05.2025 23:30 UTC ist in New York noch der 07.05., in Deutschland schon der 08.05.
    let usd = trade("u", "2025-05-07T23:30:00", netto: 50, waehrung: "USD")
    var datei = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: [usd])],
                              zeitzone: newYork, erstellt: zeit("2026-10-01T20:00:00"))
    datei.referenzkurse = [JournalExport.Tageskurse(tag: try #require(Journaltag("2025-05-07")),
                                                    kurse: ["USD": try #require(Decimal(string: "1.25"))]),
                           JournalExport.Tageskurse(tag: try #require(Journaltag("2025-05-08")), kurse: ["USD": 2])]
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: datei)
    // 50 USD zum Kurs vom 08.05. (2,00) = 25 EUR, wie App und Bericht.
    #expect(anfrage.auswertung().kennzahlen.netto == 25)
    #expect(anfrage.bericht().auswertung.kennzahlen.netto == 25)
}

@Test func regelnZaehlenTradesOhneKursNurNachAnzahl() throws {
    let regeln = Handelsregeln(maxTagesverlust: 5, maxTradesJeTag: 2)
    let trades = [trade("a", "2025-05-06T08:00:00", netto: -100, waehrung: "USD"),
                  trade("b", "2025-05-06T09:00:00", netto: 1),
                  trade("c", "2025-05-06T10:00:00", netto: 1)]
    let datei = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades,
                                             regeln: regeln)],
                              zeitzone: newYork, erstellt: zeit("2026-10-01T20:00:00"))
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: datei)
    let verstoesse = anfrage.verstoesse(anfrage.konto.trades)
    // c ist der dritte Trade des Tages; der USD-Verlust ohne Kurs zählt nicht zum Tagesverlust.
    #expect(verstoesse.map(\.trade) == ["c"] && verstoesse.map(\.art) == [.tradesJeTag])
}

@Test func verstossEinesTradesOhneKursStehtWieInAppUndPDF() throws {
    // Codex-Vollreview 04.10.: Der USD-Trade ohne Kurs ist der dritte des Tages; App und PDF zählen seinen Verstoß.
    let trades = [trade("b", "2025-05-06T08:00:00", netto: 1), trade("c", "2025-05-06T09:00:00", netto: 1),
                  trade("u", "2025-05-06T10:00:00", netto: -50, waehrung: "USD")]
    var datei = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades,
                                             regeln: Handelsregeln(maxTradesJeTag: 2))],
                              zeitzone: newYork, erstellt: zeit("2026-10-01T20:00:00"))
    let ohneKurse = try Anfrage.lies(["monat": "2025-05"], export: datei)
    // Kurse in der Datei, aber keiner am Schlusstag von u: derselbe Fall über den Währungsangleich.
    datei.referenzkurse = [JournalExport.Tageskurse(tag: try #require(Journaltag("2025-04-01")), kurse: ["USD": 2])]
    let mitKursen = try Anfrage.lies(["monat": "2025-05"], export: datei)
    for anfrage in [ohneKurse, mitKursen] {
        #expect(anfrage.ohneKurs.map(\.id) == ["u"])
        let text = anfrage.regelabschnitt(anfrage.auswertung().trades).joined(separator: "\n")
        #expect(text.contains("| Trades am Tag | 1 |"))
        #expect(text.contains("Trades mit mindestens einem Verstoß: 1 von 3, netto 0"))
        #expect(text.contains("Ohne Verstoß: 2 Trades, netto 2"))
        #expect(text.contains("Mitgezählt wie in der App: 1 Trades in anderer Währung ohne EZB-Kurs am Schlusstag, "
            + "davon 1 mit Verstoß."))
    }
    // Mit waehrung nur diese Währung: der USD-Trade gehört in die eigene Abfrage.
    let nurEur = try Anfrage.lies(["monat": "2025-05", "waehrung": "EUR"], export: datei)
    #expect(nurEur.ohneKurs.isEmpty)
    #expect(nurEur.regelabschnitt(nurEur.auswertung().trades).contains("Kein Verstoß im Zeitraum (2 Trades geprüft)."))
}
