import Foundation
import Testing
@testable import TradingCore

/// Die anonymisierte Probe bleibt lesbar und verliert die persönlichen Angaben (03.10.2026, synthetische Daten).
private func fixture(_ pfad: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try String(contentsOf: url, encoding: .utf8)
}

private let berlin = TimeZone(identifier: "Europe/Berlin")!

@Test func probenBleibenLesbar() throws {
    let tr = try fixture("Sonderfaelle/trade_republic_sonderfaelle.csv")
    #expect(try TradeRepublicCSV.lies(AnonymeProbe.erstelle(tr).text) == TradeRepublicCSV.lies(tr))

    let scalable = try fixture("R2/scalable_2026.csv")
    let scalableProbe = AnonymeProbe.erstelle(scalable).text
    #expect(try ScalableCSV.lies(scalableProbe, zeitzone: berlin) == ScalableCSV.lies(scalable, zeitzone: berlin))

    for datei in ["coinbase_v1", "coinbase_v3", "coinbase_v4"] {
        let text = try fixture("Krypto/Coinbase/\(datei).csv")
        let probe = AnonymeProbe.erstelle(text).text
        #expect(CoinbaseCSV.erkennt(probe), "\(datei)")
        #expect(try CoinbaseCSV.lies(probe).ausfuehrungen.count == CoinbaseCSV.lies(text).ausfuehrungen.count, "\(datei)")
    }
    for datei in ["bitpanda_alt", "bitpanda_neu"] {
        let text = try fixture("Krypto/Bitpanda/\(datei).csv")
        let probe = AnonymeProbe.erstelle(text)
        #expect(!probe.text.contains("SYNTHETISCH"), "\(datei)")
        #expect(try BitpandaCSV.lies(probe.text) == BitpandaCSV.lies(text), "\(datei)")
    }
    for datei in ["kraken_einfach", "kraken_sonderfaelle"] {
        let text = try fixture("Krypto/Kraken/\(datei).csv")
        #expect(try KrakenCSV.lies(AnonymeProbe.erstelle(text).text).ausfuehrungen.count
            == KrakenCSV.lies(text).ausfuehrungen.count, "\(datei)")
    }
    for datei in ["binance_einfach", "binance_sonderfaelle"] {
        let text = try fixture("Krypto/Binance/\(datei).csv")
        #expect(try BinanceCSV.lies(AnonymeProbe.erstelle(text).text).ausfuehrungen.count
            == BinanceCSV.lies(text).ausfuehrungen.count, "\(datei)")
    }
}

@Test func tradeRepublicGegenparteiUndIBAN() throws {
    let kopf = "datetime,date,account_type,category,type,asset_class,name,symbol,shares,price,amount,fee,tax,currency,"
        + "original_amount,original_currency,fx_rate,description,transaction_id,counterparty_name,counterparty_iban,"
        + "payment_reference,mcc_code"
    let zeile = "2026-03-02T08:00:00.000Z,2026-03-02,DEFAULT,CASH,CUSTOMER_INPAYMENT,,,,,,1000.000000,,,EUR,,,,"
        + "\"Überweisung von Erika Mustermann, DE89 3704 0044 0532 0130 00\",tr-0001,Erika Mustermann,"
        + "DE89370400440532013000,Miete erika@example.com,"
    let text = kopf + "\n" + zeile + "\n"
    let probe = AnonymeProbe.erstelle(text)
    #expect(!probe.text.contains("Mustermann"))
    #expect(!probe.text.contains("DE89"))
    #expect(!probe.text.contains("erika@"))
    #expect(probe.text.contains("XX00 0000 0000 0000 0000 00"))
    #expect(probe.ersetzt["Name"] == 3)
    // Die Zeile bleibt eine Einzahlung über 1000.
    let k = try TradeRepublicCSV.lies(probe.text)
    #expect(k.geldbewegungen.map(\.betrag) == [1000])
}

@Test func ibkrKontoinformation() throws {
    let text = """
    Statement,Header,Field Name,Field Value
    Statement,Data,BrokerName,Interactive Brokers Ireland Limited
    Account Information,Header,Field Name,Field Value
    Account Information,Data,Name,Max Muster
    Account Information,Data,Account,U1234567
    Account Information,Data,Base Currency,EUR
    Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,Proceeds,\
    Comm/Fee,Basis,Realized P/L,MTM P/L,Code
    Trades,Data,Order,Stocks,USD,AAPL,"2025-05-02, 10:15:30",10,170.5,171,-1705,-1,1706,0,5,O
    """
    let probe = AnonymeProbe.erstelle(text).text
    #expect(!probe.contains("Max Muster"))
    #expect(!probe.contains("1234567"))
    #expect(probe.contains("Account Information,Data,Base Currency,EUR"))
    #expect(IBKRCSV.erkennt(probe))
    #expect(try IBKRCSV.lies(probe).ausfuehrungen.count == IBKRCSV.lies(text).ausfuehrungen.count)
}

@Test func metaTraderNameUndKonto() throws {
    let html = try fixture("MT4/beispiel-2026-05-31-monthly.html")
    let zone = TimeZone(secondsFromGMT: 3 * 3600)!
    let soll = try MT4Statement.parse(html: html, serverZeitzone: zone)
    let probe = AnonymeProbe.erstelle(html).text
    let ist = try MT4Statement.parse(html: probe, serverZeitzone: zone)
    #expect(ist.accountNumber != soll.accountNumber)
    #expect(ist.accountName == "Anonym" || soll.accountName.isEmpty)
    #expect(ist.closedPositions.count == soll.closedPositions.count)
    #expect(ist.closedTotals == soll.closedTotals)

    let mt5 = """
    <html><head><title>12345678: Max Muster - Trade History Report</title></head><body><table>
    <tr align="left"><th colspan="3">Name:</th><th colspan="10"><b>Max Muster</b></th></tr>
    <tr align="left"><th colspan="3">Account:</th><th colspan="10"><b>12345678&nbsp;(USD, Server, real, Hedge)</b></th></tr>
    <tr align="left"><th colspan="3">Company:</th><th colspan="10"><b>Beispiel Broker Ltd.</b></th></tr>
    """
    let mt5Probe = AnonymeProbe.erstelle(mt5).text
    #expect(!mt5Probe.contains("Muster"))
    #expect(!mt5Probe.contains("12345678"))
    #expect(mt5Probe.contains("<title>90000001: Anonym - Trade History Report</title>"))
    #expect(mt5Probe.contains("Beispiel Broker Ltd."))
}

@Test func langeNummernGleichErsetztDezimalzahlenBleiben() {
    let text = "Order;Betrag;ISIN\n123456789;0,123456789;DE0007164600\n123456789;1234,5;US0378331005\n987654321;2;X\n"
    let probe = AnonymeProbe.erstelle(text)
    let zeilen = probe.text.split(separator: "\n").map { $0.split(separator: ";", omittingEmptySubsequences: false) }
    #expect(zeilen[1][0] == zeilen[2][0])
    #expect(zeilen[1][0] != zeilen[3][0])
    #expect(zeilen[1][0] != "123456789")
    #expect(zeilen[1][1] == "0,123456789")
    #expect(zeilen[1][2] == "DE0007164600")
    #expect(probe.ersetzt["Nummer"] == 2)
}

@Test func probeKuerzen() {
    let text = (["a,b,c"] + (1...100).map { "\($0),x,y" }).joined(separator: "\n")
    let probe = AnonymeProbe.erstelle(text, hoechstensZeilen: 10)
    #expect(probe.weggelassen == 71)
    #expect(probe.text.split(separator: "\n").count == 30)
}
