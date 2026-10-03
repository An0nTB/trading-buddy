import Foundation

/// Reproduzierbare Zufallszahlen (SplitMix64): Jeder Lauf erzeugt dieselben Daten.
struct Wuerfel {
    var zustand: UInt64

    mutating func naechste() -> UInt64 {
        zustand &+= 0x9E37_79B9_7F4A_7C15
        var z = zustand
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func zahl(_ bereich: ClosedRange<Int>) -> Int {
        bereich.lowerBound + Int(naechste() % UInt64(bereich.count))
    }
}

/// Synthetische Historie eines Testers für Lasttests (kein echtes Konto): drei Jahre, drei Konten,
/// EUR, USD und gemischt. Scalable (EUR) und Interactive Brokers (Basis EUR, Aktien in USD und EUR) mit je
/// 3 400 Ausführungen, MetaTrader 5 (USD) mit 1 600 Positionen; zusammen 10 000 Ausführungen bzw. 5 000 Trades.
/// `zusatz` hängt an jede Datei einen Vorgang an: der nächste, überlappende Export desselben Kontos.
struct Lastdaten {
    static let handelstageAnzahl = 783
    static let roundtripsJeBroker = 1_700
    static let mt5Positionen = 1_600
    static let monate = 36

    var scalable: Data
    var ibkr: Data
    var mt5: Data
    /// Erwartete Zahlen ohne Zusatz.
    var scalableGeld: Int
    var ibkrGeld: Int
    var mt5Geld: Int
    /// Werktage 2023 bis 2025 (UTC), an denen gehandelt wird.
    var handelstage: [Date]

    static func erzeuge(zusatz: Bool = false) -> Lastdaten {
        let tage = handelstage()
        var w = Wuerfel(zustand: 20_261_003)
        let s = scalableCSV(tage, &w, zusatz: zusatz)
        let i = ibkrCSV(tage, &w, zusatz: zusatz)
        let m = mt5HTML(tage, &w, zusatz: zusatz)
        return Lastdaten(scalable: Data(s.text.utf8), ibkr: Data(i.text.utf8), mt5: Data(m.text.utf8),
                         scalableGeld: s.geld, ibkrGeld: i.geld, mt5Geld: m.geld, handelstage: tage)
    }

    // MARK: Kalender und Zahlen

    static let utc = TimeZone(secondsFromGMT: 0)!
    static let kalender: Calendar = {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = utc
        return k
    }()

    static func handelstage() -> [Date] {
        var tag = kalender.date(from: DateComponents(year: 2023, month: 1, day: 2))!
        let ende = kalender.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        var tage: [Date] = []
        while tag <= ende {
            let wochentag = kalender.component(.weekday, from: tag)
            if wochentag != 1 && wochentag != 7 { tage.append(tag) }
            tag = tag.addingTimeInterval(86_400)
        }
        return tage
    }

    static func teile(_ tag: Date) -> (jahr: Int, monat: Int, tag: Int) {
        let t = kalender.dateComponents([.year, .month, .day], from: tag)
        return (t.year!, t.month!, t.day!)
    }

    static func zwei(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Tag `tag` im Format JJJJ-MM-TT (oder mit anderem Trenner).
    static func datum(_ tag: Date, _ trenner: String = "-") -> String {
        let t = teile(tag)
        return "\(t.jahr)\(trenner)\(zwei(t.monat))\(trenner)\(zwei(t.tag))"
    }

    static func uhrzeit(_ sekunden: Int) -> String {
        "\(zwei(sekunden / 3600)):\(zwei(sekunden / 60 % 60)):\(zwei(sekunden % 60))"
    }

    /// Ganzzahl in kleinsten Einheiten als Dezimaltext: `zahl(-12345, 2)` ergibt „-123.45“.
    static func zahl(_ wert: Int, _ stellen: Int, komma: Bool = false) -> String {
        var faktor = 1
        for _ in 0..<stellen { faktor *= 10 }
        let betrag = abs(wert)
        var rest = String(betrag % faktor)
        while rest.count < stellen { rest = "0" + rest }
        let ganz = "\(wert < 0 ? "-" : "")\(betrag / faktor)"
        return stellen == 0 ? ganz : ganz + (komma ? "," : ".") + rest
    }

    /// Erster Handelstag jedes Monats.
    static func monatsanfaenge(_ tage: [Date]) -> [Date] {
        var gesehen = Set<Int>()
        return tage.filter { let t = teile($0); return gesehen.insert(t.jahr * 100 + t.monat).inserted }
    }

    // MARK: Scalable Capital (EUR)

    static let scalableWerte = [
        ("DE0007164600", "SAP SE"), ("DE0008404005", "Allianz SE"), ("DE0007236101", "Siemens AG"),
        ("DE0005557508", "Deutsche Telekom AG"), ("DE0007100000", "Mercedes-Benz Group AG"),
        ("DE000BASF111", "BASF SE"), ("NL0010273215", "ASML Holding N.V."),
        ("IE00B4L5Y983", "iShares Core MSCI World UCITS ETF"),
    ]

    static func scalableCSV(_ tage: [Date], _ w: inout Wuerfel, zusatz: Bool) -> (text: String, geld: Int) {
        var zeilen: [(sortierung: String, zeile: String)] = []
        func zeile(_ tag: Date, _ sekunden: Int, _ ref: String, _ name: String, _ art: String, _ typ: String,
                   _ isin: String, _ stueck: String, _ preis: String, _ betrag: Int, _ gebuehr: Int) {
            let z = [datum(tag), uhrzeit(sekunden), "Executed", ref, name, art, typ, isin, stueck, preis,
                     zahl(betrag, 2, komma: true), zahl(gebuehr, 2, komma: true), "0,00", "EUR"]
            zeilen.append((datum(tag) + uhrzeit(sekunden) + ref, z.joined(separator: ";")))
        }
        for n in 0..<roundtripsJeBroker {
            let auf = n * tage.count / roundtripsJeBroker
            let zu = min(auf + w.zahl(0...6), tage.count - 1)
            let (isin, name) = scalableWerte[w.zahl(0...scalableWerte.count - 1)]
            let stueck = w.zahl(1...40), kaufpreis = w.zahl(2_000...40_000)
            let verkaufspreis = kaufpreis * w.zahl(88...116) / 100
            zeile(tage[auf], 32_400 + n % 600 * 37 % 30_000, "LAST-S-\(n)-K", name, "Security", "Buy", isin,
                  "\(stueck)", zahl(kaufpreis, 2, komma: true), -stueck * kaufpreis, -99)
            zeile(tage[zu], 54_000 + n % 400 * 23 % 7_000, "LAST-S-\(n)-V", name, "Security", "Sell", isin,
                  "\(stueck)", zahl(verkaufspreis, 2, komma: true), stueck * verkaufspreis, -99)
        }
        var geld = 0
        for (m, tag) in monatsanfaenge(tage).enumerated() {
            zeile(tag, 28_800, "LAST-S-E\(m)", "Einzahlung", "Cash", "Deposit", "", "", "", 100_000, 0)
            geld += 1
            if m % 3 != 2 {
                zeile(tag, 0, "LAST-S-D\(m)", "Allianz SE", "Security", "Distribution", "DE0008404005", "", "",
                      w.zahl(500...5_000), 0)
                geld += 1
            }
        }
        if zusatz {
            zeile(tage[tage.count - 1], 64_800, "LAST-S-ZUSATZ", "Einzahlung", "Cash", "Deposit", "", "", "",
                  50_000, 0)
        }
        let kopf = "date;time;status;reference;description;assetType;type;isin;shares;price;amount;fee;tax;currency"
        return ([kopf] + zeilen.sorted { $0.sortierung < $1.sortierung }.map { $0.zeile }).joined(separator: "\n"), geld)
    }

    // MARK: Interactive Brokers (Basis EUR, Aktien in USD und EUR)

    static let ibkrWerte = [
        ("AAPL", "USD"), ("MSFT", "USD"), ("NVDA", "USD"), ("AMZN", "USD"), ("JPM", "USD"),
        ("SAP", "EUR"), ("SIE", "EUR"), ("ALV", "EUR"),
    ]

    static func ibkrCSV(_ tage: [Date], _ w: inout Wuerfel, zusatz: Bool) -> (text: String, geld: Int) {
        var zeilen = [
            "Statement,Header,Field Name,Field Value",
            "Statement,Data,BrokerName,Interactive Brokers Ireland Limited",
            "Account Information,Header,Field Name,Field Value",
            "Account Information,Data,Name,Test Person",
            "Account Information,Data,Account,U7654321",
            "Account Information,Data,Base Currency,EUR",
            "Trades,Header,DataDiscriminator,Asset Category,Currency,Symbol,Date/Time,Quantity,T. Price,C. Price,"
                + "Proceeds,Comm/Fee,Basis,Realized P/L,MTM P/L,Code",
        ]
        func handel(_ symbol: String, _ waehrung: String, _ tag: Date, _ sekunden: Int, _ menge: Int, _ preis: Int,
                    _ code: String) {
            let p = zahl(preis, 2)
            zeilen.append(["Trades", "Data", "Order", "Stocks", waehrung, symbol,
                           "\"\(datum(tag)), \(uhrzeit(sekunden))\"", "\(menge)", p, p, zahl(-menge * preis, 2),
                           "-1.00", "0", "0", "0", code].joined(separator: ","))
        }
        // Uhrzeiten aus der laufenden Nummer: eindeutig, weil die Kennung aus Symbol, Zeit, Menge und Preis entsteht.
        for n in 0..<roundtripsJeBroker {
            let auf = n * tage.count / roundtripsJeBroker
            let zu = min(auf + w.zahl(0...8), tage.count - 1)
            let (symbol, waehrung) = ibkrWerte[w.zahl(0...ibkrWerte.count - 1)]
            let menge = w.zahl(1...100), kaufpreis = w.zahl(5_000...90_000)
            handel(symbol, waehrung, tage[auf], 34_200 + n * 7 % 23_000, menge, kaufpreis, "O")
            handel(symbol, waehrung, tage[zu], 34_200 + (n * 11 + 5) % 23_000, -menge,
                   kaufpreis * w.zahl(85...120) / 100, "C")
        }
        var geld = 0
        zeilen.append("Deposits & Withdrawals,Header,Currency,Settle Date,Description,Amount")
        for tag in monatsanfaenge(tage) {
            zeilen.append("Deposits & Withdrawals,Data,EUR,\(datum(tag)),Electronic Fund Transfer,2000")
            geld += 1
        }
        zeilen.append("Dividends,Header,Currency,Date,Description,Amount")
        for (m, tag) in monatsanfaenge(tage).enumerated() where m % 3 == 1 {
            zeilen.append("Dividends,Data,USD,\(datum(tag)),AAPL(US0378331005) Cash Dividend USD 0.24 per Share "
                + "(Ordinary Dividend),\(zahl(w.zahl(500...4_000), 2))")
            geld += 1
        }
        if zusatz {
            zeilen.append("Dividends,Data,USD,\(datum(tage[tage.count - 1])),MSFT(US5949181045) Cash Dividend USD "
                + "0.83 per Share (Ordinary Dividend),12.45")
        }
        return (zeilen.joined(separator: "\n"), geld)
    }

    // MARK: MetaTrader 5 (USD)

    /// Symbol und Nachkommastellen des Kurses.
    static let mt5Werte = [("EURUSD", 5, 108_000), ("GBPUSD", 5, 126_000), ("USDJPY", 3, 148_000),
                           ("XAUUSD", 2, 230_000), ("US500", 2, 480_000)]

    static func mt5HTML(_ tage: [Date], _ w: inout Wuerfel, zusatz: Bool) -> (text: String, geld: Int) {
        var html = """
        <html><head><title>87654321: Test - Trade History Report</title></head><body>
        <table>
        <tr align="center"><th colspan="13"><div><b>Trade History Report</b></div></th></tr>
        <tr align="left"><th colspan="3">Name:</th><th colspan="10"><b>Test Person</b></th></tr>
        <tr align="left"><th colspan="3">Account:</th><th colspan="10"><b>87654321&nbsp;(USD, Test-Server, real, Hedge)</b></th></tr>
        <tr align="left"><th colspan="3">Company:</th><th colspan="10"><b>Beispiel Broker Ltd.</b></th></tr>
        <tr align="left"><th colspan="3">Date:</th><th colspan="10"><b>2026.01.02 12:00</b></th></tr>
        <tr align="center"><th colspan="13"><div><b>Positions</b></div></th></tr>
        <tr align="center" bgcolor="#E5F0FC"><td><b>Time</b></td><td><b>Position</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td class="hidden" colspan="8"></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>S / L</b></td><td><b>T / P</b></td><td><b>Time</b></td><td><b>Price</b></td><td><b>Commission</b></td><td><b>Swap</b></td><td><b>Profit</b></td></tr>

        """
        var kommission = 0, swaps = 0, gewinne = 0
        func zeit(_ tag: Date, _ sekunden: Int) -> String { "\(datum(tag, ".")) \(uhrzeit(sekunden))" }
        let anzahl = mt5Positionen + (zusatz ? 1 : 0)
        for n in 0..<anzahl {
            let auf = min(n * tage.count / mt5Positionen, tage.count - 1)
            let zu = min(auf + w.zahl(0...2), tage.count - 1)
            let (symbol, stellen, basis) = mt5Werte[w.zahl(0...mt5Werte.count - 1)]
            let kauf = w.zahl(0...1) == 0
            let einstieg = basis + w.zahl(-5_000...5_000), ausstieg = einstieg + w.zahl(-900...1_000)
            let stop = w.zahl(0...2) == 0 ? "" : zahl(kauf ? einstieg - 600 : einstieg + 600, stellen)
            let k = -w.zahl(0...300), s = w.zahl(0...3) == 0 ? -w.zahl(1...500) : 0, g = w.zahl(-8_000...9_000)
            kommission += k
            swaps += s
            gewinne += g
            let farbe = n % 2 == 0 ? "#FFFFFF" : "#F7F7F7"
            html += "<tr bgcolor=\"\(farbe)\" align=\"right\"><td>\(zeit(tage[auf], 25_200 + n * 13 % 30_000))</td>"
                + "<td>\(500_000 + n)</td><td>\(symbol)</td><td>\(kauf ? "buy" : "sell")</td>"
                + "<td class=\"hidden\" colspan=\"8\"></td><td>0.\(zwei(w.zahl(1...50)))</td>"
                + "<td>\(zahl(einstieg, stellen))</td><td>\(stop)</td><td></td>"
                + "<td>\(zeit(tage[zu], 57_600 + n * 17 % 14_000))</td><td>\(zahl(ausstieg, stellen))</td>"
                + "<td>\(zahl(k, 2))</td><td>\(zahl(s, 2))</td><td>\(zahl(g, 2))</td></tr>\n"
        }
        html += "<tr align=\"right\"><td colspan=\"10\"></td><td>\(zahl(kommission, 2))</td><td>\(zahl(swaps, 2))</td>"
            + "<td>\(zahl(gewinne, 2))</td></tr>\n"
        html += """
        <tr align="center"><th colspan="13"><div><b>Deals</b></div></th></tr>
        <tr align="center"><td><b>Time</b></td><td><b>Deal</b></td><td><b>Symbol</b></td><td><b>Type</b></td><td><b>Direction</b></td><td><b>Volume</b></td><td><b>Price</b></td><td><b>Order</b></td><td><b>Commission</b></td><td><b>Fee</b></td><td><b>Swap</b></td><td><b>Profit</b></td><td><b>Balance</b></td><td><b>Comment</b></td></tr>

        """
        var geld = 0
        for (m, tag) in monatsanfaenge(tage).enumerated() {
            html += "<tr align=\"right\"><td>\(zeit(tag, 21_600))</td><td>\(900_000 + m)</td><td></td><td>balance</td>"
                + "<td></td><td></td><td></td><td></td><td>0.00</td><td>0.00</td><td>0.00</td><td>500.00</td>"
                + "<td>0.00</td><td>Deposit</td></tr>\n"
            geld += 1
        }
        html += """
        <tr align="center"><th colspan="13"><div><b>Results</b></div></th></tr>
        <tr align="right"><td>Total Net Profit:</td><td>\(zahl(gewinne + kommission + swaps, 2))</td></tr>
        </table></body></html>
        """
        return (html, geld)
    }
}
