import Foundation
import Testing
@testable import TradingCore

/// Sechs ausgedachte Trades, alle Sollwerte von Hand gerechnet (Rechenweg im Kommentar).
/// Mo 02.06.2025 bis Fr 06.06.2025, Zeiten in UTC.
private func zeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

let handTrades: [Trade] = [
    // Gewinn: netto 20 − 1 = 19; Risiko 10 → +1,9 R; 60 Min.
    Trade(id: "1", symbol: "de40", side: .buy, lots: 1, openTime: zeit("2025-06-02T09:00:00"), closeTime: zeit("2025-06-02T10:00:00"),
          openPrice: 100, closePrice: 120, stopLoss: 90, commission: -1, profit: 20),
    // Verlust: netto −4 − 1 = −5; Risiko 5 → −1 R; 30 Min.
    Trade(id: "2", symbol: "de40", side: .sell, lots: 1, openTime: zeit("2025-06-02T11:00:00"), closeTime: zeit("2025-06-02T11:30:00"),
          openPrice: 100, closePrice: 104, stopLoss: 105, commission: -1, profit: -4),
    // Verlust ohne Stop: netto −11, kein R; 20 Min.
    Trade(id: "3", symbol: "xauusd", side: .buy, lots: 2, openTime: zeit("2025-06-02T11:40:00"), closeTime: zeit("2025-06-02T12:00:00"),
          openPrice: 50, closePrice: 45, commission: -1, profit: -10),
    // Gewinn: netto 30 − 2 = 28; Risiko 10 → +2,8 R; 4 Std.
    Trade(id: "4", symbol: "de40", side: .buy, lots: 1, openTime: zeit("2025-06-03T14:00:00"), closeTime: zeit("2025-06-03T18:00:00"),
          openPrice: 200, closePrice: 230, stopLoss: 190, takeProfit: 230, commission: -1, swap: -1, profit: 30),
    // Verlust: netto −4 − 3 = −7; Wert je Punkt 2, Risiko 2 × 2 = 4 → −1,75 R; 24 Std.
    Trade(id: "5", symbol: "xauusd", side: .sell, lots: 2, openTime: zeit("2025-06-04T09:00:00"), closeTime: zeit("2025-06-05T09:00:00"),
          openPrice: 80, closePrice: 82, stopLoss: 82, commission: -1, swap: -2, profit: -4),
    // Verlust nur durch Kosten: netto −1; ohne Kursbewegung kein R; 5 Min.
    Trade(id: "6", symbol: "de40", side: .buy, lots: 1, openTime: zeit("2025-06-06T10:00:00"), closeTime: zeit("2025-06-06T10:05:00"),
          openPrice: 10, closePrice: 10, stopLoss: 9, commission: -1, profit: 0),
]

@Test func rMultipleJeTrade() {
    #expect(handTrades.map(\.rMultiple) == [d("1.9"), -1, nil, d("2.8"), d("-1.75"), nil])
    // Stop auf der Gewinnseite (nachgezogen): kein R.
    var nachgezogen = handTrades[0]
    nachgezogen.stopLoss = 110
    #expect(nachgezogen.risk == nil)
}

@Test func basiskennzahlenVonHand() {
    let k = Kennzahlen(trades: handTrades)
    #expect(k.anzahl == 6 && k.gewinner == 2 && k.verlierer == 4 && k.breakeven == 0)
    #expect(k.netto == 23)                                  // 19 − 5 − 11 + 28 − 7 − 1
    #expect(k.brutto == 32)                                 // 20 − 4 − 10 + 30 − 4 + 0
    #expect(k.kosten == -9)                                 // 6 × −1 Kommission, −1 und −2 Swap
    #expect(k.kostenquote == d("0.18"))                     // 9 ÷ (20 + 30)
    #expect(k.trefferquote?.gerundet(4) == d("0.3333"))     // 2 ÷ 6
    #expect(k.durchschnittGewinn == d("23.5"))              // (19 + 28) ÷ 2
    #expect(k.durchschnittVerlust == -6)                    // −24 ÷ 4
    #expect(k.payoff?.gerundet(4) == d("3.9167"))           // 23,5 ÷ 6
    #expect(k.erwartungswert?.gerundet(4) == d("3.8333"))   // 23 ÷ 6
    #expect(k.profitfaktor?.gerundet(4) == d("1.9583"))     // 47 ÷ 24
    #expect(k.breakevenTrefferquote?.gerundet(4) == d("0.2034")) // 1 ÷ (1 + 47/12) = 12/59
    #expect(k.anzahlMitR == 4)
    #expect(k.erwartungswertR == d("0.4875"))               // (1,9 − 1 + 2,8 − 1,75) ÷ 4
    #expect(k.haltedauerGewinner == 9000)                   // (3600 + 14400) ÷ 2
    #expect(k.haltedauerVerlierer == 22425)                 // (1800 + 1200 + 86400 + 300) ÷ 4
    #expect(!k.genugDaten)
}

@Test func leereMengeOhneDivisionDurchNull() {
    let k = Kennzahlen(trades: [])
    #expect(k.anzahl == 0 && k.netto == 0)
    #expect(k.trefferquote == nil && k.profitfaktor == nil && k.erwartungswertR == nil)
}

@Test func kapitalverlaufVonHand() {
    let v = Kapitalverlauf(trades: handTrades.reversed(), startkapital: 100)
    #expect(v.punkte == [119, 114, 103, 131, 124, 123])
    #expect(v.maxDrawdown == 16)                            // Hoch 119, Tief 103
    #expect(v.maxDrawdownProzent?.gerundet(4) == d("0.1345")) // 16 ÷ 119
    #expect(v.laengsteGewinnserie == 1)                     // G V V G V V
    #expect(v.laengsteVerlustserie == 2)
}

@Test func stornoquote() {
    #expect(Kennzahlen.stornoquote(ausgefuehrt: 83, geloescht: 57)?.gerundet(4) == d("0.4071"))
    #expect(Kennzahlen.stornoquote(ausgefuehrt: 0, geloescht: 0) == nil)
}

private func netto(_ gruppen: [Gruppe]) -> [String: Decimal] {
    Dictionary(uniqueKeysWithValues: gruppen.map { ($0.schluessel, $0.kennzahlen.netto) })
}

@Test func aufschluesselungVonHand() {
    let utc = TimeZone(secondsFromGMT: 0)!
    let a = Kennzahlen.aufschluesseln
    #expect(a(handTrades, .wochentag, utc).map(\.schluessel) == ["1", "2", "3", "5"])
    #expect(netto(a(handTrades, .wochentag, utc)) == ["1": 3, "2": 28, "3": -7, "5": -1])
    #expect(netto(a(handTrades, .stunde, utc)) == ["9": 12, "10": -1, "11": -16, "14": 28])
    #expect(netto(a(handTrades, .richtung, utc)) == ["buy": 35, "sell": -12])
    #expect(netto(a(handTrades, .tradeNummerAmTag, utc)) == ["1": 39, "2": -5, "3": -11])
    #expect(netto(a(handTrades, .nachVorherigem, utc)) == ["erster": 19, "nachGewinn": -12, "nachVerlust": 16])
    #expect(a(handTrades, .haltedauer, utc).first { $0.schluessel == "unter1Stunde" }?.kennzahlen.anzahl == 3)
    // UTC−10: Trade 1 (Mo 09:00 UTC) liegt am Sonntag 23:00.
    let westen = TimeZone(secondsFromGMT: -10 * 3600)!
    #expect(a(handTrades, .wochentag, westen).first?.schluessel == "1")
    #expect(a(handTrades, .wochentag, westen).last?.schluessel == "7")
}

/// Echter Monat (GBE, Mai 2025). Sollwerte unabhängig mit Python gerechnet (01.10.2026).
@Test func kennzahlenGBEMai2025() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MT4/gbe-2025-05-31-monthly.html")
    let auszug = try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                        serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    let trades = auszug.closedPositions.map { Trade($0) }
    let k = Kennzahlen(trades: trades)
    #expect(k.anzahl == 83 && k.gewinner == 54 && k.verlierer == 29)
    #expect(k.netto == d("7.14") && k.brutto == d("12.73") && k.kosten == d("-5.59"))
    #expect(k.kostenquote?.gerundet(4) == d("0.0423"))
    #expect(k.trefferquote?.gerundet(4) == d("0.6506"))
    #expect(k.payoff?.gerundet(4) == d("0.5685"))
    #expect(k.profitfaktor?.gerundet(4) == d("1.0587"))
    #expect(k.erwartungswert?.gerundet(4) == d("0.0860"))
    #expect(k.anzahlMitR == 83)
    #expect(k.erwartungswertR?.gerundet(4) == d("-0.0398"))
    #expect(k.genugDaten)

    let v = Kapitalverlauf(trades: trades, startkapital: auszug.summary.balance - auszug.closedTradePL)
    #expect(v.punkte.last == d("568.63"))
    #expect(v.maxDrawdown == d("37.20"))
    #expect(v.maxDrawdownProzent?.gerundet(4) == d("0.0653"))
    #expect(v.laengsteGewinnserie == 8 && v.laengsteVerlustserie == 4)
    #expect(Kennzahlen.aufschluesseln(trades, nach: .symbol, zeitzone: .init(secondsFromGMT: 0)!)
        .first { $0.schluessel == "de40.c" }?.kennzahlen.anzahl == 30)
}
