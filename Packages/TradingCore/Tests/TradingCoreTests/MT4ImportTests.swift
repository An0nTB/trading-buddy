import Foundation
import Testing
@testable import TradingCore

/// Pseudonymisierte Original-Auszüge von GBE brokers (Mai/Juni 2025).
/// Konto und Name sind ersetzt, alle Zahlen sind echt.
private func html(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MT4/\(name).html")
    return try String(contentsOf: url, encoding: .utf8)
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let utcPlus3 = TimeZone(secondsFromGMT: 3 * 3600)!

private func auszug(_ name: String, zeitzone: TimeZone = utc) throws -> MT4Statement {
    try MT4Statement.parse(html: html(name), serverZeitzone: zeitzone)
}

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

private func utcZeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = utc
    return formatter.date(from: iso)!
}

/// Sollwerte, unabhängig vom Swift-Code mit Python aus den Dateien gezählt (01.10.2026).
struct Sollwerte: Sendable, CustomTestStringConvertible {
    let datei: String
    let geschlossen: Int
    let geloescht: Int
    let offen: Int
    let closedTradePL: String
    let floatingPL: String
    let balance: String
    let equity: String
    var testDescription: String { datei }
}

let alleAuszuege = [
    Sollwerte(datei: "gbe-2025-05-14-daily", geschlossen: 4, geloescht: 4, offen: 0, closedTradePL: "-2.31", floatingPL: "0", balance: "556.88", equity: "556.88"),
    Sollwerte(datei: "gbe-2025-05-18-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "-4.89", balance: "560.44", equity: "555.55"),
    Sollwerte(datei: "gbe-2025-05-22-daily", geschlossen: 1, geloescht: 0, offen: 1, closedTradePL: "1.19", floatingPL: "0.06", balance: "564.52", equity: "564.58"),
    Sollwerte(datei: "gbe-2025-05-25-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "1.01", balance: "564.52", equity: "565.53"),
    Sollwerte(datei: "gbe-2025-05-31-monthly", geschlossen: 83, geloescht: 57, offen: 0, closedTradePL: "7.14", floatingPL: "0", balance: "568.63", equity: "568.63"),
    Sollwerte(datei: "gbe-2025-06-02-daily", geschlossen: 14, geloescht: 8, offen: 0, closedTradePL: "3.94", floatingPL: "0", balance: "572.57", equity: "572.57"),
    Sollwerte(datei: "gbe-2025-06-04-daily", geschlossen: 1, geloescht: 0, offen: 0, closedTradePL: "0.73", floatingPL: "0", balance: "573.30", equity: "573.30"),
    Sollwerte(datei: "gbe-2025-06-05-daily", geschlossen: 4, geloescht: 14, offen: 1, closedTradePL: "1.03", floatingPL: "-0.91", balance: "574.33", equity: "573.42"),
    Sollwerte(datei: "gbe-2025-06-06-daily", geschlossen: 2, geloescht: 0, offen: 1, closedTradePL: "1.45", floatingPL: "-4.04", balance: "575.78", equity: "571.74"),
    Sollwerte(datei: "gbe-2025-06-07-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "-3.96", balance: "575.78", equity: "571.82"),
]

@Test(arguments: alleAuszuege)
func auszugStimmtMitSollwertenUndEigenenSummen(soll: Sollwerte) throws {
    let a = try auszug(soll.datei)
    #expect(a.closedPositions.count == soll.geschlossen)
    #expect(a.cancelledOrders.count == soll.geloescht)
    #expect(a.openPositions.count == soll.offen)
    #expect(a.workingOrders.isEmpty)
    #expect(a.closedTradePL == d(soll.closedTradePL))
    #expect(a.floatingPL == d(soll.floatingPL))
    #expect(a.summary.balance == d(soll.balance))
    #expect(a.summary.equity == d(soll.equity))
    #expect(a.pruefe() == [])
    #expect(a.broker == "GBE brokers Ltd.")
    #expect(a.accountNumber == "100001")
    #expect(a.accountName == "Max Muster")
}

@Test func monatsauszugHatSummenAberKeinenVortag() throws {
    let a = try auszug("gbe-2025-05-31-monthly")
    #expect(a.kind == .monthly)
    #expect(a.summary.previousBalance == nil)
    #expect(a.closedTotals == Totals(commission: d("-4.14"), swap: d("-1.45"), profit: d("12.73")))
    #expect(a.reportTime == utcZeit("2025-05-31T23:59:00Z"))
    #expect(Set(a.closedPositions.map(\.ticket)).count == 83)
}

@Test func geschlossenePositionVollstaendigGelesen() throws {
    let a = try auszug("gbe-2025-05-14-daily", zeitzone: utcPlus3)
    #expect(a.kind == .daily)
    #expect(a.summary.previousBalance == d("559.19"))
    #expect(a.serverZeitzone == utcPlus3)
    let p = try #require(a.closedPositions.first)
    #expect(p.ticket == "88075715")
    #expect(p.rohzeile == ["88075715", "2025.05.13 08:51:24", "buy", "0.01", "cadchfc", "0.60361", "0.58231",
                           "0.60574", "2025.05.14 12:51:41", "0.59880", "-0.07", "0.03", "-5.13"])
    #expect(p.side == .buy)
    #expect(p.lots == d("0.01"))
    #expect(p.symbol == "cadchfc")
    #expect(p.openPrice == d("0.60361"))
    #expect(p.stopLoss == d("0.58231"))
    #expect(p.takeProfit == d("0.60574"))
    #expect(p.closePrice == d("0.59880"))
    #expect(p.netProfit == d("-5.17"))
    // Serverzeit UTC+3: 08:51:24 auf dem Server ist 05:51:24 UTC.
    #expect(p.openTime == utcZeit("2025-05-13T05:51:24Z"))
    #expect(p.closeTime == utcZeit("2025-05-14T09:51:41Z"))
}

@Test func geloeschteOrderZaehltNichtAlsTrade() throws {
    let a = try auszug("gbe-2025-05-14-daily")
    let o = try #require(a.cancelledOrders.first)
    #expect(o.ticket == "88114946")
    #expect(o.rohzeile.last == "cancelled")
    #expect(o.type == .buyStop)
    #expect(o.type.side == .buy)
    #expect(o.takeProfit == nil)
    #expect(o.marketPrice == d("21303.55"))
    #expect(!a.closedPositions.contains { $0.ticket == o.ticket })
}

@Test func offenePositionMitAktuellemKurs() throws {
    let p = try #require(try auszug("gbe-2025-05-22-daily").openPositions.first)
    #expect(p.ticket == "88167088")
    #expect(p.side == .sell)
    #expect(p.symbol == "eurgbpc")
    #expect(p.currentPrice == d("0.84086"))
    #expect(p.netProfit == d("0.06"))
}

@Test func veraenderteZahlFaelltBeiPruefungAuf() throws {
    let text = try html("gbe-2025-05-14-daily").replacingOccurrences(of: "<td>-5.13</td>", with: "<td>-5.14</td>")
    let a = try MT4Statement.parse(html: text, serverZeitzone: utc)
    #expect(a.pruefe().map(\.pruefung) == ["Kursergebnis geschlossen"])
}

@Test func unbekannteZeileBrichtImportAb() throws {
    let text = try html("gbe-2025-05-14-daily")
        .replacingOccurrences(of: "<td>buy</td><td>0.01</td><td>cadchfc</td>", with: "<td>balance</td><td>0.01</td><td>cadchfc</td>")
    #expect(throws: MT4ImportFehler.unbekannteAuftragsart("balance")) {
        try MT4Statement.parse(html: text, serverZeitzone: utc)
    }
}

@Test func geaenderterSpaltenkopfBrichtImportAb() throws {
    let text = try html("gbe-2025-05-14-daily").replacingOccurrences(of: "<td>R/O Swap</td>", with: "<td>Swap</td>")
    #expect(throws: MT4ImportFehler.self) {
        try MT4Statement.parse(html: text, serverZeitzone: utc)
    }
}

@Test func fremdesHTMLWirdAbgelehnt() {
    #expect(throws: MT4ImportFehler.keinMT4Auszug) {
        try MT4Statement.parse(html: "<title>Rechnung</title><table></table>", serverZeitzone: utc)
    }
}

@Test func zahlenUndZeitenStreng() throws {
    #expect(try MT4Werte.zahl("10 000.00") == d("10000"))
    #expect(try MT4Werte.zahl("-0.07") == d("-0.07"))
    #expect(throws: MT4ImportFehler.self) { try MT4Werte.zahl("1,5") }
    #expect(throws: MT4ImportFehler.self) { try MT4Werte.zahl("") }
    #expect(throws: MT4ImportFehler.self) { try MT4Werte.zeit("2025.02.30 00:00:00", zeitzone: utc) }
    #expect(try MT4Werte.berichtszeit("2025 June 7, 23:59", zeitzone: utc) == utcZeit("2025-06-07T23:59:00Z"))
}
