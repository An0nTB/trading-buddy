import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.8.0: Summen nur innerhalb einer Währung (Trade.waehrung, Rechenkern 0.17.0).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ schluss: String, netto: Decimal, waehrung: String? = nil) -> Trade {
    Trade(id: id, symbol: id.hasPrefix("u") ? "BTCUSD" : "SAP", side: .buy, lots: 1,
          openTime: zeit(schluss).addingTimeInterval(-600), closeTime: zeit(schluss),
          openPrice: 100, closePrice: 100 + netto, profit: netto, waehrung: waehrung)
}

private func export(_ trades: [Trade], regeln: Handelsregeln? = nil, ziele: [Reviewziel] = []) -> JournalExport {
    JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades,
                                 ziele: ziele, regeln: regeln)],
                  zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
}

private let gemischt = [trade("e1", "2025-05-05T10:00:00", netto: 10), trade("e2", "2025-05-06T10:00:00", netto: -4),
                        trade("e3", "2025-05-07T10:00:00", netto: 6, waehrung: "EUR"),
                        trade("u1", "2025-05-05T12:00:00", netto: 500, waehrung: "usd"),
                        trade("u2", "2025-04-10T12:00:00", netto: -80, waehrung: "USD")]

@Test func summenNurInDerKontowaehrung() throws {
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export(gemischt))
    #expect(anfrage.konto.waehrung == "EUR" && anfrage.konto.trades.map(\.id) == ["e1", "e2", "e3"])
    #expect(anfrage.auswertung().kennzahlen.netto == 12)
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("Konto Kraken …4242, Beträge in EUR. Nur Trades in EUR. Nicht in diesen Summen "
        + "(eigene Abfrage mit waehrung): USD: 2 Trades, davon 1 im Zeitraum. Beträge verschiedener Währungen "
        + "nie zusammenrechnen."))
    #expect(!text.contains("BTCUSD"))
    #expect(Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10).contains("Nur Trades in EUR."))
    #expect(Ausgabe.datenstand(export(gemischt)).contains(
        "- Kraken …4242, EUR: 5 Trades, geschlossen 10.04.2025 bis 07.05.2025, davon in anderer Währung USD 2 "
            + "(Auswertung je Währung über waehrung), 0 gelöschte Orders."))
}

@Test func andereWaehrungOhneZieleUndBetragsgrenzen() throws {
    let regeln = Handelsregeln(maxTagesverlust: 100, maxTradesJeTag: 3, maxRisikoJeTrade: 50)
    let mai = Zeitspanne.monat(jahr: 2025, monat: 5, zeitzone: berlin)!
    let ziel = Reviewziel(id: 1, text: "Netto über 0", von: mai.von, bis: mai.bis, messgroesse: "netto", zielwert: 0)
    let anfrage = try Anfrage.lies(["monat": "2025-05", "waehrung": " usd "],
                                   export: export(gemischt, regeln: regeln, ziele: [ziel]))
    #expect(anfrage.konto.waehrung == "USD" && anfrage.kontowaehrung == "EUR")
    #expect(anfrage.konto.trades.map(\.id) == ["u1", "u2"] && anfrage.auswertung().kennzahlen.netto == 500)
    #expect(anfrage.konto.regeln == Handelsregeln(maxTradesJeTag: 3) && anfrage.konto.ziele.isEmpty)
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("Beträge in USD. Kontowährung ist EUR; Ziele und Betragsgrenzen der Handelsregeln gelten "
        + "dort und fehlen hier. Nur Trades in USD."))
    #expect(text.contains("EUR: 3 Trades, davon 3 im Zeitraum"))
    #expect(text.contains("- Ziele früherer Reviews: gelten in der Kontowährung EUR und stehen nur in der Abfrage "
        + "ohne waehrung."))

    #expect(throws: AnfrageFehler.waehrungUnbekannt("CHF", ["EUR", "USD"])) {
        try Anfrage.lies(["waehrung": "chf"], export: export(gemischt))
    }
    #expect(AnfrageFehler.waehrungUnbekannt("CHF", ["EUR", "USD"]).text
        == "WÄHRUNG UNBEKANNT: „CHF“ kommt in diesem Konto nicht vor. Vorhanden: EUR, USD.")
}

@Test func ohneTradesInKontowaehrungGiltDieHaeufigste() throws {
    let nurFremd = [trade("u1", "2025-05-05T12:00:00", netto: 5, waehrung: "USD"),
                    trade("u2", "2025-05-06T12:00:00", netto: 5, waehrung: "USD"),
                    trade("t1", "2025-05-07T12:00:00", netto: 5, waehrung: "USDT")]
    let anfrage = try Anfrage.lies([:], export: export(nurFremd))
    #expect(anfrage.konto.waehrung == "USD" && anfrage.konto.trades.count == 2)
    #expect(Array(anfrage.andereWaehrungen.keys) == ["USDT"])
    // Gleich viele: alphabetisch zuerst.
    let gleich = try Anfrage.lies([:], export: export(Array(nurFremd.dropFirst())))
    #expect(gleich.konto.waehrung == "USD")
    // Nur eine Währung, gleich der Kontowährung: kein Hinweis, Ausgabe wie bisher.
    let einfach = try Anfrage.lies(["monat": "2025-05"], export: export(Array(gemischt.prefix(3))))
    #expect(einfach.andereWaehrungen.isEmpty && Ausgabe.waehrungshinweis(einfach).isEmpty)
    #expect(!Ausgabe.datenstand(export(Array(gemischt.prefix(3)))).contains("anderer Währung"))
}

@Test func anzahlRegelnZaehlenAlleWaehrungenBetragsgrenzenNurDieEigene() throws {
    // Ein Tag mit fünf Trades: drei in EUR, zwei in USD. Grenze 4 Trades je Tag, 100 Tagesverlust.
    let tag = [trade("e1", "2025-05-05T08:00:00", netto: -30), trade("e2", "2025-05-05T09:00:00", netto: -30),
               trade("u1", "2025-05-05T10:00:00", netto: -500, waehrung: "USD"),
               trade("u2", "2025-05-05T11:00:00", netto: 5, waehrung: "USD"),
               trade("e3", "2025-05-05T12:00:00", netto: 10)]
    let regeln = Handelsregeln(maxTagesverlust: 100, maxTradesJeTag: 4)
    let eur = try Anfrage.lies(["monat": "2025-05"], export: export(tag, regeln: regeln))
    // e3 ist der fünfte Trade des Tages; der USD-Verlust zählt nicht in den EUR-Tagesverlust.
    let inEur = eur.verstoesse(eur.konto.trades)
    #expect(inEur.map(\.trade) == ["e3"] && inEur.map(\.art) == [.tradesJeTag])
    let usd = try Anfrage.lies(["monat": "2025-05", "waehrung": "USD"], export: export(tag, regeln: regeln))
    #expect(usd.verstoesse(usd.konto.trades).isEmpty)
}
