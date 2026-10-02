import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// A3 (Doc 38): Kursanalyse aus den Tageskerzen der App, mit eigenen Trades im Wert.

private let utc = TimeZone(secondsFromGMT: 0)!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

/// 20 Werktage vom 05.05. bis 30.05.2025, Schluss 101 bis 120, dazu der laufende 02.06. mit 130.
private func kerzen() -> [Kerze] {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = utc
    var liste: [Kerze] = []
    var tag = zeit("2025-05-05T00:00:00")
    var vorher: Decimal = 100
    while liste.count < 20 {
        if !kalender.isDateInWeekend(tag) {
            let schluss = vorher + 1
            liste.append(Kerze(tag: Journaltag(tag, zeitzone: utc), open: vorher, high: schluss + 1, low: vorher - 1,
                               close: schluss))
            vorher = schluss
        }
        tag = kalender.date(byAdding: .day, value: 1, to: tag)!
    }
    liste.append(Kerze(tag: Journaltag("2025-06-02")!, open: 120, high: 131, low: 119, close: 130, laufend: true))
    return liste
}

private func trade(_ id: String, _ symbol: String, netto: Decimal, waehrung: String? = "USD") -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: zeit("2025-05-12T09:00:00"),
          closeTime: zeit("2025-05-12T10:00:00"), openPrice: 100, closePrice: 100 + netto, profit: netto,
          waehrung: waehrung)
}

private func export(mitKursen: Bool = true) -> JournalExport {
    JournalExport(
        konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR",
                       trades: [trade("a", "BTC/USD", netto: 30), trade("b", "BTC/USD", netto: -10),
                                trade("c", "ETH/USD", netto: 5)])],
        zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: zeit("2025-06-02T12:00:00"),
        kursverlauf: mitKursen ? [.init(symbol: "BTCUSD", quelle: "kraken", waehrung: "usd",
                                        stand: zeit("2025-06-02T11:00:00"), kerzen: kerzen())] : [])
}

@Test func kursanalyseMitKennzahlenDesRechenkerns() throws {
    let text = Ausgabe.kursanalyse(export(), symbol: "btc-usd")
    let erwartet = try #require(Kursanalyse(kerzen: kerzen()))
    #expect(text.contains("# Henry · Kursanalyse BTCUSD (12 Monate)"))
    #expect(text.contains("Kurse: Tageskerzen von kraken in USD, abgerufen 02.06.2025 13:00, 20 abgeschlossene Tage "
        + "bis 2025-05-30 (UTC-Kalendertage)."))
    #expect(text.contains("| Letzter Schluss (2025-05-30) | 120,00 USD |"))
    #expect(text.contains("| Aktueller Kurs (laufender Tag, kein Schluss) | 130,00 USD |"))
    #expect(text.contains("| Veränderung 1 Woche | \(Format.prozent(erwartet.veraenderung[.woche])) |"))
    #expect(text.contains("| Veränderung 12 Monate | – |"))
    #expect(text.contains("| Schwankung aufs Jahr | \(Format.prozent(erwartet.schwankungJahr)) |"))
    #expect(text.contains("| Durchschnittliche Tagesspanne (ATR 14) | \(Format.zahl(erwartet.atr14!)) USD ("))
    #expect(text.contains("| Größter Rückgang vom Hoch im Zeitraum | 0,0 % |"))
    #expect(text.contains("| Kraken …4242 | USD | 2 | 20,00 | 50,0 % | – |"))
    #expect(!text.contains("| Kraken …4242 | USD | 3 |"))
    #expect(text.contains("hole_nachrichten mit begriff=BTCUSD"))
    #expect(text.contains("## Rezept für die Kursanalyse (Henry)") && text.contains("keine Kauf- oder Verkaufssignale"))
    #expect(Ausgabe.kursanalyse(export(), symbol: "BTCUSD", monate: 0).contains("Kursanalyse BTCUSD (1 Monat)"))
    #expect(Ausgabe.datenstand(export()).contains("Kursverläufe (Tageskerzen) für 1 Werte: BTCUSD (hole_kursanalyse)."))
}

@Test func ohneKursverlaufNurEigeneTrades() {
    let fremd = Ausgabe.kursanalyse(export(), symbol: "ETH/USD")
    #expect(fremd.contains("Kein Kursverlauf in der App für ETH/USD. Kursverläufe gibt es für: BTCUSD."))
    #expect(fremd.contains("| Kraken …4242 | USD | 1 | 5,00 |") && !fremd.contains("## Kennzahlen"))
    #expect(Ausgabe.kursanalyse(export(mitKursen: false), symbol: "BTCUSD")
        .contains("Die App hat noch keine Kurse geladen."))
    #expect(Ausgabe.kursanalyse(export(), symbol: " ") == "SYMBOL FEHLT: `symbol` angeben, z. B. eines von: BTCUSD.")
    #expect(Ausgabe.kursanalyse(export(), symbol: "SOL").contains("Keine geschlossenen Trades seit"))
}

@Test func kursreiheUeberstehtDieRundreise() throws {
    let original = export()
    let json = String(decoding: try original.json(), as: UTF8.self)
    #expect(json.contains("\"laufend\":true") && json.contains("\"close\":\"120\""))
    #expect(try JournalExport.lese(Data(json.utf8)).kursverlauf == original.kursverlauf)
    // Eine unlesbare Kerze kostet nur die Kerzen dieser Reihe.
    let kaputt = json.replacingOccurrences(of: "\"close\":\"120\"", with: "\"close\":\"x\"")
    let gelesen = try JournalExport.lese(Data(kaputt.utf8))
    #expect(kaputt != json && gelesen.kursverlauf?.first?.kerzen.isEmpty == true && gelesen.konten[0].trades.count == 3)
    #expect(Ausgabe.kursanalyse(gelesen, symbol: "BTCUSD").contains("Für BTCUSD liegen keine abgeschlossenen Tageskerzen vor."))
}
