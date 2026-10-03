import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.14.0: Netto in der Anzeigewährung der App im Kopf (Vierter Gegencheck H21, Doc 52).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ schluss: String, netto: Decimal) -> Trade {
    Trade(id: id, symbol: "AAPL", side: .buy, lots: 1, openTime: zeit(schluss).addingTimeInterval(-600),
          closeTime: zeit(schluss), openPrice: 100, closePrice: 100 + netto, profit: netto)
}

/// USD-Konto; die App zeigt Summen in `anzeige`. Kurse am 05.05. (1,25 USD je Euro) und 06.05. (2,00).
private func export(anzeige: String?) throws -> JournalExport {
    let trades = [trade("a", "2025-05-05T12:00:00", netto: 300), trade("b", "2025-05-06T12:00:00", netto: 180),
                  trade("c", "2025-05-30T12:00:00", netto: 20)]
    return JournalExport(
        konten: [.init(broker: "Alpaca", kontonummer: "7777", waehrung: "USD", trades: trades)],
        zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"),
        referenzkurse: [.init(tag: try #require(Journaltag("2025-05-05")), kurse: ["USD": try #require(Decimal(string: "1.25"))]),
                        .init(tag: try #require(Journaltag("2025-05-06")), kurse: ["USD": 2])],
        anzeigewaehrung: anzeige)
}

@Test func nettoInDerAnzeigewaehrungImKopf() throws {
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: try export(anzeige: "EUR"))
    // 300 / 1,25 + 180 / 2 = 240 + 90; c am 30.05. findet in sieben Tagen keinen Kurs.
    let summe = try #require(anfrage.anzeigesumme)
    #expect(summe == Anzeigesumme(waehrung: "EUR", netto: 330, trades: 2, ohneKurs: 1))
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("Die App zeigt Summen in EUR (Anzeigewährung): netto im Zeitraum 330,00 EUR aus 2 Trades "
        + "(EZB-Referenzkurs am Schlusstag, Näherung; 1 Trades ohne Kurs fehlen). Alle anderen Beträge hier in USD."))
    // Die Auswertung selbst bleibt in Kontowährung.
    #expect(anfrage.konto.waehrung == "USD" && anfrage.auswertung().kennzahlen.netto == 500)
    #expect(Rezept.text.contains("Nennt der Kopf eine Anzeigewährung der App"))
}

@Test func keinHinweisOhneAbweichendeAnzeigewaehrung() throws {
    for anzeige in [nil, "USD"] {
        let anfrage = try Anfrage.lies(["monat": "2025-05"], export: try export(anzeige: anzeige))
        #expect(anfrage.anzeigesumme == nil)
        #expect(!Ausgabe.auswertung(anfrage).contains("Die App zeigt Summen"))
    }
    // Ohne Kurse in der Datei kein Hinweis.
    var ohneKurse = try export(anzeige: "EUR")
    ohneKurse.referenzkurse = nil
    #expect(try Anfrage.lies(["monat": "2025-05"], export: ohneKurse).anzeigesumme == nil)
}
