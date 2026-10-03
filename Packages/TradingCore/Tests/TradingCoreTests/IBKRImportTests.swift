import Foundation
import Testing
@testable import TradingCore

/// Synthetischer IBKR-Kontoauszug (Activity Statement, CSV) nach dem Aufbau aus der IBKR-Hilfe, kein echtes Konto.
/// Sollwerte von Hand (02.10.2026).
let ibkrCSV = """
\u{FEFF}Statement,Header,Field Name,Field Value
Statement,Data,BrokerName,Interactive Brokers Ireland Limited
Statement,Data,Title,Activity Statement
Account Information,Header,Field Name,Field Value
Account Information,Data,Name,Max Muster
Account Information,Data,Account,U1234567
Account Information,Data,Base Currency,EUR
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
Trades,Data,Trade,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-09, 15:59:01",-10,180,180,1800,-1.02,-1706,92.98,0,C
Trades,Data,ClosedLot,Stocks,USD,AAPL,2025-05-02,10,170.6,,,,1706,92.98,,
Trades,Data,Order,Stocks,USD,BRK B,"2025-05-12, 09:31:00","1,000",0.5,0.5,-500,-2,502,0,0,O
Trades,SubTotal,,Stocks,USD,AAPL,,0,,,95,-2.02,0,92.98,5,
Trades,Total,,Stocks,EUR,,,,,,85,-1.8,,,,
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,,Proceeds,Comm in EUR,,,MTM in EUR,Code
Trades,Data,Order,Forex,USD,EUR.USD,"2025-05-02, 10:00:00",-1600,1.12,,1792,-1.7,,,0,
Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount
Deposits & Withdrawals,Data,EUR,2025-05-01,Electronic Fund Transfer,2000
Deposits & Withdrawals,Data,Total,,,2000
Dividends,Header,Currency,Date,Description,Amount
Dividends,Data,USD,2025-05-15,AAPL(US0378331005) Cash Dividend USD 0.25 per Share (Ordinary Dividend),2.5
Dividends,Data,Total,,,2.5
Withholding Tax,Header,Currency,Date,Description,Amount,Code
Withholding Tax,Data,USD,2025-05-15,AAPL(US0378331005) Cash Dividend USD 0.25 per Share - US Tax,-0.38,
Interest,Header,Currency,Date,Description,Amount
Interest,Data,EUR,2025-05-31,EUR Credit Interest for May-2025,1.23
Fees,Header,Subtitle,Currency,Date,Description,Amount
Fees,Data,Other Fees,USD,2025-05-03,Market data fee,-1.5
"""

private func utc(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

@Test func ibkrErkennungUndKonto() throws {
    #expect(IBKRCSV.erkennt(ibkrCSV))
    #expect(!IBKRCSV.erkennt("date,time,status,reference\n2026-01-01,10:00:00,Executed,x"))
    let konto = IBKRCSV.konto(ibkrCSV)
    #expect(konto.nummer == "U1234567")
    #expect(konto.waehrung == "EUR")
    #expect(throws: CSVImportFehler.self) { try IBKRCSV.lies("a,b\n1,2") }
}

@Test func ibkrTrades() throws {
    let b = try IBKRCSV.lies(ibkrCSV)
    #expect(b.ausfuehrungen.count == 3)  // nur „Order“, kein „Trade“, kein „ClosedLot“, kein Forex
    let kauf = b.ausfuehrungen[0]
    #expect(kauf.seite == .buy)
    #expect(kauf.menge == 10)
    #expect(kauf.preis == Decimal(string: "170.5")!)
    #expect(kauf.betrag == -1705)
    #expect(kauf.gebuehr == -1)
    #expect(kauf.waehrung == "USD")
    #expect(kauf.produktart == .aktie)
    #expect(kauf.kennung == "AAPL")
    #expect(kauf.id == "AAPL|2025-05-02, 10:15:30|10|170.5")
    // US-Ostküste im Mai: UTC-4.
    #expect(kauf.zeit == utc("2025-05-02T14:15:30Z"))
    #expect(!kauf.nurDatum)

    let verkauf = b.ausfuehrungen[1]
    #expect(verkauf.seite == .sell)
    #expect(verkauf.menge == 10)
    #expect(verkauf.betrag == 1800)
    #expect(verkauf.gebuehr == Decimal(string: "-1.02")!)
    // Tausendertrenner in Anführungszeichen.
    #expect(b.ausfuehrungen[2].menge == 1000)
    #expect(b.ausfuehrungen[2].kennung == "BRK B")
    #expect(b.hinweise == [Importhinweis(zeile: 17, vorgang: "Forex EUR.USD", folge: .nichtVerbucht)])
}

@Test func ibkrGeldbewegungen() throws {
    let geld = try IBKRCSV.lies(ibkrCSV, zeitzone: TimeZone(identifier: "Europe/Berlin")!).geldbewegungen
    #expect(geld.map(\.art) == [.einzahlung, .dividende, .steuer, .zinsen, .gebuehr])
    #expect(geld.map(\.betrag) == [2000, Decimal(string: "2.5")!, Decimal(string: "-0.38")!,
                                   Decimal(string: "1.23")!, Decimal(string: "-1.5")!])
    #expect(geld.map(\.waehrung) == ["EUR", "USD", "USD", "EUR", "USD"])
    // Keypath als Argument in #expect baut nicht (rethrows im Makro), deshalb vorher auswerten.
    let alleNurDatum = geld.allSatisfy(\.nurDatum)
    #expect(alleNurDatum)
    #expect(geld[0].zeit == utc("2025-04-30T22:00:00Z"))
    #expect(geld[1].kennung == "US0378331005")
    #expect(geld[3].kennung == nil)
    #expect(Set(geld.map(\.id)).count == 5)
    #expect(IBKRCSV.produktart("Equity and Index Options") == .derivat)
    #expect(IBKRCSV.kennung("XYZ(ABC) Dividend") == "XYZ")
}
