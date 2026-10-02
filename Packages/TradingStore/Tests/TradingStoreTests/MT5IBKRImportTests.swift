import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

/// Synthetischer MetaTrader-5-Bericht wie in den TradingCore-Tests (Aufbau aus der MT5-Hilfe, kein echtes Konto).
private let mt5HTML = """
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

/// Synthetischer IBKR-Kontoauszug wie in den TradingCore-Tests (Aufbau aus der IBKR-Hilfe, kein echtes Konto).
private let ibkrCSV = """
\u{FEFF}Statement,Header,Field Name,Field Value
Statement,Data,BrokerName,Interactive Brokers Ireland Limited
Account Information,Header,Field Name,Field Value
Account Information,Data,Name,Max Muster
Account Information,Data,Account,U1234567
Account Information,Data,Base Currency,EUR
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
Trades,Data,Order,Stocks,USD,AAPL,"2025-05-09, 15:59:01",-10,180,180,1800,-1.02,-1706,92.98,0,C
Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,,Proceeds,Comm in EUR,,,MTM in EUR,Code
Trades,Data,Order,Forex,USD,EUR.USD,"2025-05-02, 10:00:00",-1600,1.12,,1792,-1.7,,,0,
Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount
Deposits & Withdrawals,Data,EUR,2025-05-01,Electronic Fund Transfer,2000
Dividends,Header,Currency,Date,Description,Amount
Dividends,Data,USD,2025-05-15,AAPL(US0378331005) Cash Dividend USD 0.25 per Share (Ordinary Dividend),2.5
"""

private let server = TimeZone(secondsFromGMT: 3 * 3600)!

private func nurKonto(_ journal: Journal) throws -> Konto {
    let konten = try journal.konten()
    try #require(konten.count == 1)
    return konten[0]
}

@Test func mt5BerichtWirdGespeichert() throws {
    let journal = try Journal.imSpeicher()
    // MetaTrader 5 speichert UTF-16 mit BOM.
    var datei = Data([0xFF, 0xFE])
    datei.append(mt5HTML.data(using: .utf16LittleEndian)!)
    let erster = try journal.importiereMT5(datei: datei, dateiname: "ReportHistory-12345678.html",
                                           serverZeitzone: server)
    #expect(erster.status == .gespeichert)
    #expect(erster.geschlosseneNeu == 2)
    #expect(erster.csv.geldbewegungenNeu == 2)
    #expect(erster.csv.hinweise == 1)

    let konto = try nurKonto(journal)
    #expect(konto.broker == "Beispiel Broker Ltd.")
    #expect(konto.kontonummer == "12345678")
    #expect(konto.waehrung == "USD")
    let positionen = try journal.geschlossenePositionen(konto: konto)
    #expect(positionen.map(\.ticket).sorted() == ["1001", "1002"])
    let bericht = try MT5Bericht.lies(mt5HTML, serverZeitzone: server)
    #expect(positionen.sorted { $0.ticket < $1.ticket }.map(\.netProfit) == bericht.positionen.map(\.netProfit))
    let geld = try journal.kontobewegungen(konto: konto).geldbewegungen
    #expect(geld.map(\.id).sorted() == ["9001", "9003"])
    #expect(geld.allSatisfy { $0.waehrung == "USD" })
    let lauf = try #require(journal.importe(konto: konto).first)
    #expect(lauf.importer == Journal.mt5Importer)
    #expect(lauf.serverZeitzone == server.identifier)

    // Dieselbe Datei: übersprungen. Derselbe Inhalt als UTF-8: alles bekannt, nichts doppelt.
    #expect(try journal.importiereMT5(datei: datei, dateiname: "x.html", serverZeitzone: server).status
        == .dateiBereitsImportiert)
    let zweiter = try journal.importiereMT5(datei: Data(mt5HTML.utf8), dateiname: "utf8.html",
                                            serverZeitzone: server)
    #expect(zweiter.geschlosseneNeu == 0 && zweiter.geschlosseneBekannt == 2)
    #expect(zweiter.csv.geldbewegungenBekannt == 2)
    #expect(try journal.geschlossenePositionen(konto: konto).count == 2)
}

@Test func mt5BerichtMitFalscherSummeOderFremderKontonummer() throws {
    let journal = try Journal.imSpeicher()
    let falsch = mt5HTML.replacingOccurrences(of: "<td>-2.50</td><td>-20.00</td>",
                                              with: "<td>-2.50</td><td>-21.00</td>")
    #expect(falsch != mt5HTML)
    #expect(throws: SpeicherFehler.auszugWidersprichtSeinenSummen(["Positionen Ergebnis: Summe -21, Zeilen -20"])) {
        try journal.importiereMT5(datei: Data(falsch.utf8), dateiname: "a.html", serverZeitzone: server)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Kontonummer laut Datei 12345678, angegeben 999")) {
        try journal.importiereMT5(datei: Data(mt5HTML.utf8), dateiname: "a.html", kontonummer: "999",
                                  serverZeitzone: server)
    }
    #expect(try journal.konten().isEmpty)

    // Ohne „Company:“ heißt der Broker „MetaTrader 5“; die Produktart-Vorgabe füllt nur Lücken.
    let ohneFirma = mt5HTML.replacingOccurrences(of: "<b>Beispiel Broker Ltd.</b>", with: "<b></b>")
    try journal.importiereMT5(datei: Data(ohneFirma.utf8), dateiname: "b.html", serverZeitzone: server,
                              produktartVorgabe: .cfd)
    let konto = try nurKonto(journal)
    #expect(konto.broker == Journal.mt5BrokerVorgabe)
    let soll = try MT5Bericht.lies(ohneFirma, serverZeitzone: server).positionen
    let arten = try journal.geschlossenePositionen(konto: konto).map(\.produktart)
    #expect(arten == soll.map { $0.produktart == .unbekannt ? .cfd : $0.produktart })
}

@Test func ibkrAuszugUeberImportiereCSV() throws {
    let journal = try Journal.imSpeicher()
    // Die App gibt eine feste Bezeichnung mit; Konto und Basiswährung aus dem Auszug gelten.
    let erster = try journal.importiereCSV(datei: Data(ibkrCSV.utf8), dateiname: "U1234567.csv",
                                           kontonummer: "Depot", kontowaehrung: "USD")
    #expect(erster.status == .gespeichert)
    #expect(erster.csv.ausfuehrungenNeu == 2)
    #expect(erster.csv.geldbewegungenNeu == 2)
    #expect(erster.csv.hinweise == 1)
    let konto = try nurKonto(journal)
    #expect(konto.broker == "Interactive Brokers")
    #expect(konto.kontonummer == "U1234567")
    #expect(konto.waehrung == "EUR")
    let bewegungen = try journal.kontobewegungen(konto: konto)
    #expect(bewegungen.ausfuehrungen.map(\.kennung) == ["AAPL", "AAPL"])
    #expect(bewegungen.ausfuehrungen.allSatisfy { $0.produktart == .aktie })
    #expect(try journal.importe(konto: konto).first?.importer == Journal.ibkrImporter)

    // Zweiter Auszug mit überlappendem Zeitraum (ohne BOM, anderer Hash): nichts doppelt.
    let zweiter = try journal.importiereCSV(datei: Data(String(ibkrCSV.dropFirst()).utf8), dateiname: "b.csv",
                                            kontonummer: "Depot")
    #expect(zweiter.csv.ausfuehrungenNeu == 0 && zweiter.csv.ausfuehrungenBekannt == 2)
    #expect(zweiter.csv.geldbewegungenBekannt == 2)
    #expect(try journal.kontobewegungen(konto: konto).ausfuehrungen.count == 2)
}
