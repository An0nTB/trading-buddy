import Foundation
import Testing
@testable import TradingCore

/// Kernbefunde H2, H3, H4 aus dem vierten Gegencheck (Doc 52, 03.10.2026). Synthetische Daten.
private func fixture(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try String(contentsOf: url, encoding: .utf8)
}

private let berlin = TimeZone(identifier: "Europe/Berlin")!

/// „1.000,00“ → „1,000.00“ (mit Tausendertrenner) oder „1000.00“ (ohne).
private func englisch(_ wert: String, tausender: Bool) -> String {
    let ohne = wert.replacingOccurrences(of: ".", with: "")
    let teile = ohne.split(separator: ",", omittingEmptySubsequences: false)
    var ganz = String(teile[0])
    if tausender {
        let minus = ganz.hasPrefix("-")
        var ziffern = Array(minus ? ganz.dropFirst() : Substring(ganz))
        var gruppen: [String] = []
        while ziffern.count > 3 { gruppen.insert(String(ziffern.suffix(3)), at: 0); ziffern.removeLast(3) }
        gruppen.insert(String(ziffern), at: 0)
        ganz = (minus ? "-" : "") + gruppen.joined(separator: ",")
    }
    return teile.count > 1 ? ganz + "." + teile[1] : ganz
}

private func ohneRohzeile(_ k: Kontobewegungen) -> Kontobewegungen {
    var k = k
    for i in k.ausfuehrungen.indices { k.ausfuehrungen[i].rohzeile = [] }
    for i in k.geldbewegungen.indices { k.geldbewegungen[i].rohzeile = [] }
    for i in k.kapitalmassnahmen.indices { k.kapitalmassnahmen[i].rohzeile = [] }
    return k
}

@Test(arguments: [false, true])
func h2ScalableMitPunktAlsDezimalzeichen(tausender: Bool) throws {
    let original = try fixture("R2/scalable_2026.csv")
    let tabelle = CSVTabelle(text: original)
    let zahlen = Set(["shares", "price", "amount", "fee", "tax"].compactMap { tabelle.kopf.firstIndex(of: $0) })
    // Trennzeichen bleibt das Semikolon; das Tausenderkomma braucht deshalb keine Anführungszeichen.
    let zeilen = tabelle.zeilen.map { z in
        z.enumerated().map { i, wert in zahlen.contains(i) ? englisch(wert, tausender: tausender) : wert }
            .joined(separator: ";")
    }
    let text = ([tabelle.kopf.joined(separator: ";")] + zeilen).joined(separator: "\n")
    #expect(text.contains("1000.00") || text.contains("1,000.00"))
    let soll = try ScalableCSV.lies(original, zeitzone: berlin)
    let ist = try ScalableCSV.lies(text, zeitzone: berlin)
    #expect(ohneRohzeile(ist) == ohneRohzeile(soll))
}

@Test func h2DeutschesFormatBleibtKomma() {
    let tabelle = CSVTabelle(text: "shares;price;amount;fee;tax\n2;200,00;-400,00;-0,99;0,00\n1.000;1;1.000;0;0\n")
    let spalten = ["shares": 0, "price": 1, "amount": 2, "fee": 3, "tax": 4]
    #expect(ScalableCSV.zahlformat(tabelle, spalten: spalten) == .komma)
    // Nur „1.000“ (drei Ziffern) ist mehrdeutig: Es bleibt beim Komma wie bisher.
    let mehrdeutig = CSVTabelle(text: "shares;price;amount;fee;tax\n1.000;1;1.000;0;0\n")
    #expect(ScalableCSV.zahlformat(mehrdeutig, spalten: spalten) == .komma)
    let englisch = CSVTabelle(text: "shares;price;amount;fee;tax\n2;200.5;-401;-0.99;0\n")
    #expect(ScalableCSV.zahlformat(englisch, spalten: spalten) == .punkt)
}

@Test func h3IbkrGleicheOrdersBleibenGetrennt() throws {
    let text = """
    Statement,Header,Field Name,Field Value
    Account Information,Header,Field Name,Field Value
    Account Information,Data,Account,U0000001
    Account Information,Data,Base Currency,EUR
    Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,\
    Comm/Fee,Basis,Realized P/L,MTM P/L,Code
    Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
    Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
    Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
    Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount
    Deposits & Withdrawals,Data,EUR,2025-05-01,Electronic Fund Transfer,2000
    Deposits & Withdrawals,Data,EUR,2025-05-01,Electronic Fund Transfer,2000
    """
    let k = try IBKRCSV.lies(text)
    let ids = k.ausfuehrungen.map(\.id)
    #expect(ids.count == 3)
    #expect(Set(ids).count == 3)
    #expect(ids[1] == ids[0] + "#2" && ids[2] == ids[0] + "#3")
    #expect(Set(k.geldbewegungen.map(\.id)).count == 2)
    // Dieselbe Datei nochmal gelesen ergibt dieselben IDs (Dublettenprüfung beim zweiten Import).
    #expect(try IBKRCSV.lies(text).ausfuehrungen.map(\.id) == ids)
}

@Test func h4DisziplinZaehltTradesOhneKursOhneBetrag() {
    let zeit = Date(timeIntervalSince1970: 1_772_440_000)
    let euro = Trade(id: "E", symbol: "DAX", side: .buy, lots: 1, openTime: zeit, closeTime: zeit + 60,
                     openPrice: 100, closePrice: 110, profit: 10)
    let dollar = Trade(id: "U", symbol: "AAPL", side: .buy, lots: 1, openTime: zeit + 120, closeTime: zeit + 180,
                       openPrice: 100, closePrice: 200, profit: 100)
    let verstoss = Regelverstoss(art: .manuell, trade: "U", tag: zeit)
    let d = Disziplin(trades: [euro, dollar], verstoesse: [verstoss], ohneBetrag: ["U"])
    #expect(d.regeltreu == 1)
    #expect(d.verletzt == 1)
    #expect(d.nettoVerletzt == 0)
    #expect(d.nettoRegeltreu == 10)
    #expect(d.punkte.map(\.kapital) == [10, 10])
    #expect(d.punkte.map(\.wert) == [1, 0])
}
