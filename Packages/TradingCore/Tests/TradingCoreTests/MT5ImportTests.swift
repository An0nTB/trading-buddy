import Foundation
import Testing
@testable import TradingCore

/// Synthetischer MetaTrader-5-Bericht nach dem Aufbau aus der MT5-Hilfe, kein echtes Konto.
/// Sollwerte von Hand (02.10.2026). Server in UTC+3 (übliche Sommerzeit der MT-Server).
let mt5HTML = """
<html><head><title>12345678: Muster - Trade History Report</title></head><body>
<table>
<tr align="center"><th colspan="13"><div><b>Trade History Report</b></div></th></tr>
<tr align="left"><th colspan="3">Name:</th><th colspan="10"><b>Max Muster</b></th></tr>
<tr align="left"><th colspan="3">Account:</th><th colspan="10"><b>12345678&nbsp;(USD, Beispiel-Server, real, Hedge)</b></th></tr>
<tr align="left"><th colspan="3">Company:</th><th colspan="10"><b>Beispiel Broker Ltd.</b></th></tr>
<tr align="left"><th colspan="3">Date:</th><th colspan="10"><b>2025.06.01 12:00</b></th></tr>
<tr><td colspan="13" style="height: 10px"></td></tr>
<tr align="center"><th colspan="13"><div><b>Positions</b></div></th></tr>
<tr align="center" bgcolor="#E5F0FC"><td><b>Time</b></td><td><b>Position</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td class="hidden" colspan="8"></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>S / L</b></td><td><b>T / P</b></td><td><b>Time</b></td><td><b>Price</b></td><td><b>Commission</b></td><td><b>Swap</b></td><td><b>Profit</b></td></tr>
<tr bgcolor="#FFFFFF" align="right"><td>2025.05.02 10:15:30</td><td>1001</td><td>EURUSD</td><td>buy</td><td class="hidden" colspan="8"></td><td>0.10</td><td>1.12000</td><td>1.11500</td><td></td><td>2025.05.02 11:00:00</td><td>1.12300</td><td>-0.70</td><td>0.00</td><td>30.00</td></tr>
<tr bgcolor="#F7F7F7" align="right"><td>2025.05.05 09:00:00</td><td>1002</td><td>XAUUSD</td><td>sell</td><td class="hidden" colspan="8"></td><td>0.05 / 0.10</td><td>3 250.00</td><td>0</td><td>3 200.00</td><td>2025.05.06 15:30:00</td><td>3 260.00</td><td>-1.00</td><td>-2.50</td><td>-50.00</td></tr>
<tr align="right"><td colspan="10"></td><td>-1.70</td><td>-2.50</td><td>-20.00</td></tr>
<tr><td colspan="13" style="height: 10px"></td></tr>
<tr align="center"><th colspan="13"><div><b>Orders</b></div></th></tr>
<tr align="center"><td><b>Open Time</b></td><td><b>Order</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td><b>State</b></td></tr>
<tr align="right"><td>2025.05.02 10:15:30</td><td>5001</td><td>EURUSD</td><td>buy</td><td>filled</td></tr>
<tr align="center"><th colspan="13"><div><b>Deals</b></div></th></tr>
<tr align="center"><td><b>Time</b></td><td><b>Deal</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td><b>Direction</b></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>Order</b></td><td><b>Commission</b></td><td><b>Fee</b></td><td><b>Swap</b></td><td><b>Profit</b></td><td><b>Balance</b></td><td><b>Comment</b></td></tr>
<tr align="right"><td>2025.05.01 08:00:00</td><td>9001</td><td></td><td>balance</td><td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>0.00</td><td>1 000.00</td><td>1 000.00</td><td>Deposit</td></tr>
<tr align="right"><td>2025.05.02 10:15:30</td><td>9002</td><td>EURUSD</td><td>buy</td><td>in</td><td>0.10</td><td>1.12000</td><td>5001</td><td>-0.35</td><td>0.00</td><td>0.00</td><td>0.00</td><td>999.65</td><td></td></tr>
<tr align="right"><td>2025.05.20 12:00:00</td><td>9003</td><td></td><td>credit</td><td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>0.00</td><td>50.00</td><td>1 029.65</td><td>Bonus</td></tr>
<tr align="right"><td colspan="8"></td><td>-0.35</td><td>0.00</td><td>0.00</td><td>1 050.00</td><td>1 029.65</td></tr>
<tr align="center"><th colspan="13"><div><b>Results</b></div></th></tr>
<tr align="right"><td>Total Net Profit:</td><td>-24.20</td></tr>
</table></body></html>
"""

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

private let server = TimeZone(secondsFromGMT: 3 * 3600)!

@Test func mt5BerichtPositionenUndKopf() throws {
    #expect(MT5Bericht.erkennt(mt5HTML))
    let bericht = try MT5Bericht.lies(mt5HTML, serverZeitzone: server)
    #expect(bericht.konto == "12345678")
    #expect(bericht.waehrung == "USD")
    #expect(bericht.broker == "Beispiel Broker Ltd.")
    #expect(bericht.positionen.count == 2)

    let erste = bericht.positionen[0]
    #expect(erste.ticket == "1001")
    #expect(erste.side == .buy)
    #expect(erste.lots == Decimal(string: "0.1")!)
    #expect(erste.openTime == utc("2025-05-02T07:15:30Z"))
    #expect(erste.closeTime == utc("2025-05-02T08:00:00Z"))
    #expect(erste.openPrice == Decimal(string: "1.12")!)
    #expect(erste.closePrice == Decimal(string: "1.123")!)
    #expect(erste.stopLoss == Decimal(string: "1.115")!)
    #expect(erste.takeProfit == nil)
    #expect(erste.netProfit == Decimal(string: "29.3")!)

    let zweite = bericht.positionen[1]
    #expect(zweite.side == .sell)
    #expect(zweite.lots == Decimal(string: "0.05")!)  // Teilschluss: geschlossene Menge
    #expect(zweite.openPrice == 3250)
    #expect(zweite.stopLoss == nil)  // 0 heißt: kein Stop
    #expect(zweite.takeProfit == 3200)
    #expect(zweite.netProfit == Decimal(string: "-53.5")!)

    let summe = try #require(bericht.positionenLautSumme)
    #expect(summe.commission == Decimal(string: "-1.7")!)
    #expect(summe.swap == Decimal(string: "-2.5")!)
    #expect(summe.profit == -20)
    #expect(bericht.trades.count == 2)
}

@Test func mt5BerichtKassenzeilen() throws {
    let bericht = try MT5Bericht.lies(mt5HTML, serverZeitzone: server)
    let geld = bericht.kasse.geldbewegungen
    #expect(geld.count == 2)
    #expect(geld[0].id == "9001")
    #expect(geld[0].art == .einzahlung)
    #expect(geld[0].betrag == 1000)
    #expect(geld[0].waehrung == "USD")
    #expect(geld[0].zeit == utc("2025-05-01T05:00:00Z"))
    // Gutschrift (Bonus) ist kein eigenes Geld: als „sonstiges“ mit Hinweis.
    #expect(geld[1].art == .sonstiges)
    #expect(geld[1].betrag == 50)
    #expect(bericht.hinweise == [Importhinweis(zeile: 20, vorgang: "Deal 9003 credit", folge: .alsSonstiges)])
}

@Test func mt5BerichtUTF16UndAbgrenzung() throws {
    var daten = Data([0xFF, 0xFE])
    daten.append(mt5HTML.data(using: .utf16LittleEndian)!)
    let text = try #require(MT5Bericht.text(daten))
    #expect(try MT5Bericht.lies(text, serverZeitzone: server).positionen.count == 2)
    // Ohne BOM erkennt die Nullbyte-Probe UTF-16, UTF-8 bleibt UTF-8.
    #expect(MT5Bericht.text(mt5HTML.data(using: .utf16LittleEndian)!) == mt5HTML)
    #expect(MT5Bericht.text(Data(mt5HTML.utf8)) == mt5HTML)

    // MetaTrader-4-Auszüge und fremdes HTML sind kein MT5-Bericht.
    #expect(!MT5Bericht.erkennt("<html><title>Daily Confirmation</title><table><tr><td>Positions</td></tr></table>"))
    #expect(throws: MT4ImportFehler.keinMT4Auszug) {
        try MT5Bericht.lies("<html>Trade History Report</html>", serverZeitzone: server)
    }
}

@Test func mt5BerichtUnbekannteSpaltenBrechenAb() throws {
    let kaputt = mt5HTML.replacingOccurrences(of: "<td><b>Profit</b></td></tr>\n<tr bgcolor=\"#FFFFFF\"",
                                              with: "<td><b>Gewinn</b></td></tr>\n<tr bgcolor=\"#FFFFFF\"")
    #expect(kaputt != mt5HTML)
    #expect(throws: MT4ImportFehler.self) { try MT5Bericht.lies(kaputt, serverZeitzone: server) }
}

/// Fehlt einer Kassenzeile eine Zelle, bricht der Import ab, statt die Einzahlung still zu verlieren (Codex H4).
@Test func mt5BerichtBeschaedigteKassenzeileBrichtAb() throws {
    let ganz = "<td>9001</td><td></td><td>balance</td><td></td><td></td><td></td><td></td><td>0.00</td>"
    let kaputt = mt5HTML.replacingOccurrences(of: ganz,
                                              with: "<td>9001</td><td></td><td>balance</td><td></td><td></td><td></td><td>0.00</td>")
    #expect(kaputt != mt5HTML)
    #expect(throws: MT4ImportFehler.self) { try MT5Bericht.lies(kaputt, serverZeitzone: server) }
}

