import Foundation
import TradingCore

// Gemeinsame Hilfen der App-Tests. Alle Testdaten sind synthetisch (Kennungen APPT…, Wert „Testwert AG“);
// keine echten Broker-Dateien, keine Fixtures der Pakete.

enum AppTestdaten {
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    static var utcKalender: Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = utc
        return kalender
    }

    /// Zeitpunkt in UTC, z. B. `zeit(2026, 10, 1, 12)`.
    static func zeit(_ jahr: Int, _ monat: Int, _ tag: Int, _ stunde: Int = 0, _ minute: Int = 0) -> Date {
        utcKalender.date(from: DateComponents(year: jahr, month: monat, day: tag, hour: stunde, minute: minute))!
    }

    static func d(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    static func tag(_ jahr: Int, _ monat: Int, _ tag: Int) -> Journaltag { Journaltag(jahr: jahr, monat: monat, tag: tag)! }

    /// Scalable-Export im Aufbau der Broker-Datei: Einzahlung, Kauf und Verkauf desselben Werts.
    /// Kursergebnis +50, Gebühren 2 × −1: netto +48 EUR.
    static let scalable = """
        date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency
        2026-04-01;09:00:00;Executed;APPT0001;Einzahlung;Cash;Ein-/Auszahlung;;;;2.000,00;0,00;0,00;EUR
        2026-04-01;10:00:00;Executed;APPT0002;Testwert AG;Security;Order;DE000TEST001;10;50,00;-500,00;-1,00;0,00;EUR
        2026-04-02;15:00:00;Executed;APPT0003;Testwert AG;Security;Order;DE000TEST001;-10;55,00;550,00;-1,00;0,00;EUR

        """

    /// Kraken-Handelsverlauf mit einem Paar in US-Dollar: Kauf und Verkauf von 0,5 ETH.
    /// Kursergebnis +50, Gebühren 3,00 und 3,10: netto +43,90 USD. `kennung` macht die Datei unterscheidbar.
    static func kraken(kennung: String = "A") -> String {
        let kopf = #""txid","ordertxid","pair","aclass","subclass","time","type","ordertype","price","cost","fee","vol","margin","misc","ledgers","posttxid","posstatuscode","cprice","ccost","cfee","cvol","cmargin","net","trades""#
        func zeile(_ nr: Int, _ zeit: String, _ art: String, _ preis: String, _ kosten: String, _ gebuehr: String) -> String {
            #""TAPP\#(kennung)\#(nr)-AAAAA-00000\#(nr)","OAPP\#(kennung)\#(nr)-AAAAA-00000\#(nr)","XETHZUSD","forex","crypto","\#(zeit)","\#(art)","limit","\#(preis)","\#(kosten)","\#(gebuehr)","0.50000000","0.00000","","LAPP\#(kennung)\#(nr)-AAAAA-00000\#(nr)","","","","","","","","","""#
        }
        return [kopf,
                zeile(1, "2026-04-01 10:00:00.0000", "buy", "3000.00", "1500.00000", "3.00000"),
                zeile(2, "2026-04-03 10:00:00.0000", "sell", "3100.00", "1550.00000", "3.10000"),
                ""].joined(separator: "\n")
    }
}
