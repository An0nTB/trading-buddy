import Foundation
import Testing
@testable import TradingCore

/// Erfundene Beispielauszüge im MT4-Format (Mai/Juni 2026), erzeugt mit
/// Fixtures/MT4/erzeugen.py. Konto, Name, Broker und alle Zahlen sind erfunden.
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

/// Sollwerte, unabhängig vom Swift-Code mit Python aus den Dateien gezählt (04.10.2026).
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
    Sollwerte(datei: "beispiel-2026-05-13-daily", geschlossen: 4, geloescht: 4, offen: 0, closedTradePL: "-0.62", floatingPL: "0", balance: "1187.33", equity: "1187.33"),
    Sollwerte(datei: "beispiel-2026-05-17-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "-5.62", balance: "1203.09", equity: "1197.47"),
    Sollwerte(datei: "beispiel-2026-05-21-daily", geschlossen: 1, geloescht: 0, offen: 1, closedTradePL: "1.09", floatingPL: "0.01", balance: "1217.46", equity: "1217.47"),
    Sollwerte(datei: "beispiel-2026-05-24-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "1.06", balance: "1214.26", equity: "1215.32"),
    Sollwerte(datei: "beispiel-2026-05-31-monthly", geschlossen: 110, geloescht: 68, offen: 0, closedTradePL: "46.33", floatingPL: "0", balance: "1233.73", equity: "1233.73"),
    Sollwerte(datei: "beispiel-2026-06-01-daily", geschlossen: 8, geloescht: 6, offen: 0, closedTradePL: "13.20", floatingPL: "0", balance: "1246.93", equity: "1246.93"),
    Sollwerte(datei: "beispiel-2026-06-03-daily", geschlossen: 1, geloescht: 0, offen: 0, closedTradePL: "0.80", floatingPL: "0", balance: "1247.73", equity: "1247.73"),
    Sollwerte(datei: "beispiel-2026-06-04-daily", geschlossen: 6, geloescht: 14, offen: 1, closedTradePL: "2.28", floatingPL: "-0.95", balance: "1250.01", equity: "1249.06"),
    Sollwerte(datei: "beispiel-2026-06-05-daily", geschlossen: 2, geloescht: 0, offen: 1, closedTradePL: "1.26", floatingPL: "-4.65", balance: "1251.27", equity: "1246.62"),
    Sollwerte(datei: "beispiel-2026-06-06-daily", geschlossen: 0, geloescht: 0, offen: 1, closedTradePL: "0", floatingPL: "-4.58", balance: "1251.27", equity: "1246.69"),
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
    #expect(a.broker == "Beispiel Broker Ltd.")
    #expect(a.accountNumber == "12345678")
    #expect(a.accountName == "Max Muster")
}

@Test func monatsauszugHatSummenAberKeinenVortag() throws {
    let a = try auszug("beispiel-2026-05-31-monthly")
    #expect(a.kind == .monthly)
    #expect(a.summary.previousBalance == nil)
    #expect(a.closedTotals == Totals(commission: d("-7.20"), swap: d("-2.30"), profit: d("55.83")))
    #expect(a.reportTime == utcZeit("2026-05-31T23:59:00Z"))
    #expect(Set(a.closedPositions.map(\.ticket)).count == 110)
}

@Test func geschlossenePositionVollstaendigGelesen() throws {
    let a = try auszug("beispiel-2026-05-13-daily", zeitzone: utcPlus3)
    #expect(a.kind == .daily)
    #expect(a.summary.previousBalance == d("1187.95"))
    #expect(a.serverZeitzone == utcPlus3)
    let p = try #require(a.closedPositions.first)
    #expect(p.ticket == "51756927")
    #expect(p.rohzeile == ["51756927", "2026.05.12 08:47:41", "buy", "0.01", "audusd", "0.66472", "0.64572",
                           "0.66682", "2026.05.13 12:57:19", "0.65845", "-0.06", "-0.02", "-5.39"])
    #expect(p.side == .buy)
    #expect(p.lots == d("0.01"))
    #expect(p.symbol == "audusd")
    #expect(p.openPrice == d("0.66472"))
    #expect(p.stopLoss == d("0.64572"))
    #expect(p.takeProfit == d("0.66682"))
    #expect(p.closePrice == d("0.65845"))
    #expect(p.netProfit == d("-5.47"))
    // Serverzeit UTC+3: 08:47:41 auf dem Server ist 05:47:41 UTC.
    #expect(p.openTime == utcZeit("2026-05-12T05:47:41Z"))
    #expect(p.closeTime == utcZeit("2026-05-13T09:57:19Z"))
}

@Test func geloeschteOrderZaehltNichtAlsTrade() throws {
    let a = try auszug("beispiel-2026-05-13-daily")
    let o = try #require(a.cancelledOrders.first)
    #expect(o.ticket == "51764889")
    #expect(o.rohzeile.last == "cancelled")
    #expect(o.type == .buyStop)
    #expect(o.type.side == .buy)
    #expect(o.takeProfit == nil)
    #expect(o.marketPrice == d("22931.23"))
    #expect(!a.closedPositions.contains { $0.ticket == o.ticket })
}

@Test func offenePositionMitAktuellemKurs() throws {
    let p = try #require(try auszug("beispiel-2026-05-21-daily").openPositions.first)
    #expect(p.ticket == "51775217")
    #expect(p.side == .sell)
    #expect(p.symbol == "eurgbp")
    #expect(p.currentPrice == d("0.87155"))
    #expect(p.netProfit == d("0.01"))
}

@Test func veraenderteZahlFaelltBeiPruefungAuf() throws {
    let text = try html("beispiel-2026-05-13-daily").replacingOccurrences(of: "<td>-5.39</td>", with: "<td>-5.40</td>")
    let a = try MT4Statement.parse(html: text, serverZeitzone: utc)
    #expect(a.pruefe().map(\.pruefung) == ["Kursergebnis geschlossen"])
}

@Test func unbekannteZeileBrichtImportAb() throws {
    let text = try html("beispiel-2026-05-13-daily")
        .replacingOccurrences(of: "<td>buy</td><td>0.01</td><td>audusd</td>", with: "<td>balance</td><td>0.01</td><td>audusd</td>")
    #expect(throws: MT4ImportFehler.unbekannteAuftragsart("balance")) {
        try MT4Statement.parse(html: text, serverZeitzone: utc)
    }
}

@Test func geaenderterSpaltenkopfBrichtImportAb() throws {
    let text = try html("beispiel-2026-05-13-daily").replacingOccurrences(of: "<td>R/O Swap</td>", with: "<td>Swap</td>")
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
    #expect(throws: MT4ImportFehler.self) { try MT4Werte.zeit("2026.02.30 00:00:00", zeitzone: utc) }
    #expect(try MT4Werte.berichtszeit("2026 June 6, 23:59", zeitzone: utc) == utcZeit("2026-06-06T23:59:00Z"))
}
