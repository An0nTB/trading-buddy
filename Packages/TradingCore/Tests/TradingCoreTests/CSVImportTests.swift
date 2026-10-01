import Foundation
import Testing
@testable import TradingCore

/// Synthetische Testdateien aus R2 (Recherche Brokerformate, 01.10.2026), keine echten Konten.
/// Sollwerte unabhängig vom Swift-Code mit Python aus den Dateien gerechnet (01.10.2026).
private func csv(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/R2/\(name).csv")
    return try String(contentsOf: url, encoding: .utf8)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func zeitpunkt(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func csvMitAnfuehrungszeichenUndZeilenumbruch() {
    let t = CSVTabelle(text: "\u{FEFF}a;b\r\n\"x;\"\"y\"\"\";2\r\n\r\n\"mehr\nzeilig\";3\n")
    #expect(t.kopf == ["a", "b"])
    #expect(t.zeilen == [["x;\"y\"", "2"], ["mehr\nzeilig", "3"]])
}

@Test func zahlenformate() throws {
    #expect(try CSVWerte.zahl("1.000,00", .komma, zeile: 1) == 1000)
    #expect(try CSVWerte.zahl("-0,99", .komma, zeile: 1) == dez("-0.99"))
    #expect(try CSVWerte.zahl("2.0000000000", .punkt, zeile: 1) == 2)
    #expect(try CSVWerte.zahl(" ", .punkt, zeile: 1) == 0)
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 4, text: "1,5")) { try CSVWerte.zahl("1,5", .punkt, zeile: 4) }
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 4, text: "1-2")) { try CSVWerte.zahl("1-2", .punkt, zeile: 4) }
}

@Test func tradeRepublicKommaformat() throws {
    let text = try csv("trade_republic_2026_komma")
    #expect(TradeRepublicCSV.erkennt(text))
    #expect(!ScalableCSV.erkennt(text))
    let k = try TradeRepublicCSV.lies(text)
    #expect(k.ausfuehrungen.map(\.id) == ["tr-0002", "tr-0003", "tr-0005", "tr-0006"])
    #expect(k.geldbewegungen.map(\.art) == [.einzahlung, .dividende, .steuer, .zinsen])
    #expect(k.verworfen.isEmpty)
    #expect(k.kassenwirkung == dez("921.12"))

    let kauf = k.ausfuehrungen[0]
    #expect(kauf.zeit == zeitpunkt("2026-03-02T09:15:12Z"))
    #expect(kauf.seite == .buy)
    #expect(kauf.rohzeile.count == 23)
    #expect(k.ausfuehrungen[1].seite == .sell)
    #expect(k.ausfuehrungen[1].menge == 2)
    #expect(k.ausfuehrungen[3].sparplan)
    #expect(!kauf.sparplan)

    let dividende = k.geldbewegungen[1]
    #expect(dividende.betrag == dez("0.87"))
    #expect(dividende.steuer == dez("-0.23"))
    #expect(dividende.kennung == "US0378331005")
    #expect(dividende.nurDatum)
    #expect(!k.geldbewegungen[0].nurDatum)
}

@Test func tradeRepublicAltesSemikolonformat() throws {
    let text = try csv("trade_republic_alt_semikolon")
    #expect(TradeRepublicCSV.erkennt(text))
    let k = try TradeRepublicCSV.lies(text)
    #expect(k.ausfuehrungen.count == 2)
    #expect(k.geldbewegungen.count == 1)
    #expect(k.kassenwirkung == dez("1027.98"))
    #expect(Positionsbildung.bilde(k.ausfuehrungen).trades.map(\.netProfit) == [dez("27.98")])
}

@Test func positionsbildungTradeRepublic() throws {
    let k = try TradeRepublicCSV.lies(csv("trade_republic_2026_komma"))
    let ergebnis = Positionsbildung.bilde(k.ausfuehrungen)
    #expect(ergebnis.trades.count == 1)
    let sap = try #require(ergebnis.trades.first)
    #expect(sap.id == "tr-0003")
    #expect(sap.symbol == "SAP")
    #expect(sap.lots == 2)
    #expect(sap.openPrice == 200)
    #expect(sap.closePrice == 220)
    #expect(sap.profit == 40)
    #expect(sap.commission == -2)
    #expect(sap.taxes == dez("-10.02"))
    #expect(sap.netProfit == dez("27.98"))
    #expect(sap.openTime == zeitpunkt("2026-03-02T09:15:12Z"))
    #expect(ergebnis.offen.map(\.kennung) == ["BTC", "IE00B4L5Y983"])
}

@Test func scalable() throws {
    let text = try csv("scalable_2026")
    #expect(ScalableCSV.erkennt(text))
    #expect(!TradeRepublicCSV.erkennt(text))
    let k = try ScalableCSV.lies(text)
    #expect(k.verworfen == ["SCALSYN0003"])
    #expect(k.ausfuehrungen.map(\.id) == ["SCALSYN0002", "SCALSYN0004", "SCALSYN0005"])
    #expect(k.geldbewegungen.map(\.art) == [.einzahlung, .dividende, .steuer])
    #expect(k.kassenwirkung == dez("991.33"))
    // 10:01:15 deutsche Winterzeit ist 09:01:15 UTC.
    #expect(k.ausfuehrungen[0].zeit == zeitpunkt("2026-03-02T09:01:15Z"))
    #expect(k.ausfuehrungen[1].seite == .sell)
    #expect(k.ausfuehrungen[2].sparplan)
    #expect(k.geldbewegungen[1].nurDatum)
    #expect(k.geldbewegungen[1].steuer == dez("-4.06"))
    // Steuererstattung als eigener Eintrag, nicht am Trade.
    #expect(k.geldbewegungen[2].betrag == 0)
    #expect(k.geldbewegungen[2].steuer == 2)

    let sap = try #require(Positionsbildung.bilde(k.ausfuehrungen).trades.first)
    #expect(sap.profit == 40)
    #expect(sap.commission == dez("-1.98"))
    #expect(sap.taxes == dez("-10.03"))
    #expect(sap.netProfit == dez("27.99"))
}

@Test func fifoTeiltKaeufeAnteilig() throws {
    let start = Date(timeIntervalSince1970: 0)
    func ausfuehrung(_ id: String, tag: Double, _ seite: Side, _ menge: Decimal, _ betrag: Decimal) -> Ausfuehrung {
        Ausfuehrung(id: id, zeit: start.addingTimeInterval(tag * 86_400), kennung: "X", name: "", seite: seite,
                    menge: menge, preis: abs(betrag / menge), betrag: betrag, gebuehr: -1, waehrung: "EUR")
    }
    let ergebnis = Positionsbildung.bilde([
        ausfuehrung("v1", tag: 2, .sell, 15, 300),
        ausfuehrung("k1", tag: 0, .buy, 10, -100),
        ausfuehrung("k2", tag: 1, .buy, 10, -200),
    ])
    let trade = try #require(ergebnis.trades.first)
    // Verkauf schließt k1 ganz und k2 zur Hälfte: 300 − 100 − 100.
    #expect(trade.profit == 100)
    #expect(trade.commission == dez("-2.5"))
    #expect(trade.lots == 15)
    #expect(trade.symbol == "X")
    #expect(trade.openTime == start)
    #expect(ergebnis.offen.map(\.id) == ["k2"])
    #expect(ergebnis.offen[0].menge == 5)
    #expect(ergebnis.offen[0].betrag == -100)
    #expect(ergebnis.offen[0].gebuehr == dez("-0.5"))
}

@Test func fehlerBrechenAb() {
    #expect(throws: CSVImportFehler.fehlendeSpalte("time")) { try ScalableCSV.lies("date;status\n") }
    let kopf = "datetime,account_type,category,type,name,symbol,shares,price,amount,fee,tax,currency,description,"
        + "transaction_id\n"
    let kaputt = kopf + "2026-03-02T08:00:00Z,DEFAULT,CASH,DIVIDEND,,,,,1.2.3,,,EUR,,tr-9\n"
    #expect(throws: CSVImportFehler.ungueltigeZahl(zeile: 2, text: "1.2.3")) { try TradeRepublicCSV.lies(kaputt) }
}

@Test func steuernImExportNurWennVorhanden() throws {
    let trade = Trade(id: "1", symbol: "SAP", side: .buy, lots: 2, openTime: zeitpunkt("2026-03-02T09:15:12Z"),
                      closeTime: zeitpunkt("2026-03-09T14:40:55Z"), openPrice: 200, closePrice: 220,
                      commission: -2, profit: 40, taxes: dez("-10.02"))
    var ohne = trade
    ohne.taxes = 0
    let encoder = JSONEncoder()
    #expect(String(decoding: try encoder.encode(ohne), as: UTF8.self).contains("taxes") == false)
    let daten = try encoder.encode(trade)
    #expect(try JSONDecoder().decode(Trade.self, from: daten) == trade)
    #expect(try JSONDecoder().decode(Trade.self, from: encoder.encode(ohne)) == ohne)
}
