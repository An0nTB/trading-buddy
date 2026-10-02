import Foundation

/// Trade-Export von Kraken (Documents Center → Export → Trades, CSV; Kraken Support 2025/2026).
/// Zeiten in UTC, `cost` ist der Gegenwert ohne Gebühr, `fee` steht in der Gegenwährung.
/// Paare mit alten Präfixen („XXBTZEUR“) und XBT statt BTC (Kraken Support 2026).
/// Margin-Trades und Krypto gegen Krypto werden Hinweise. Der Ledger-Export ist noch nicht angebunden.
/// Status: ungeprüft, bis eine echte Datei durchgelaufen ist.
public enum KrakenCSV {
    static let pflichtspalten = ["txid", "ordertxid", "pair", "time", "type", "ordertype", "price", "cost",
                                 "fee", "vol", "margin"]
    /// Gegenwährungen in der Schreibweise von Kraken, längste zuerst geprüft.
    static let gegenwaehrungen = ["ZEUR", "ZUSD", "ZGBP", "ZCHF", "USDT", "USDC", "XXBT", "XETH",
                                  "EUR", "USD", "GBP", "CHF", "XBT", "ETH"]

    /// Alte Kraken-Kürzel mit X- oder Z-Präfix; neuere Werte haben keins (Kraken Support 2026).
    static let altKuerzel: [String: String] = [
        "XXBT": "BTC", "XBT": "BTC", "XETH": "ETH", "XXRP": "XRP", "XLTC": "LTC", "XXLM": "XLM", "XXMR": "XMR",
        "XETC": "ETC", "XZEC": "ZEC", "XXDG": "DOGE", "XDG": "DOGE", "XREP": "REP", "XMLN": "MLN",
        "ZEUR": "EUR", "ZUSD": "USD", "ZGBP": "GBP", "ZCHF": "CHF", "ZCAD": "CAD", "ZJPY": "JPY", "ZAUD": "AUD",
    ]

    /// Kraken-Kürzel → übliches Kürzel: XXBT → BTC, ZEUR → EUR, „ETH.S“ (Staking) → ETH.
    static func kuerzel(_ roh: String) -> String {
        var k = roh.uppercased()
        if let punkt = k.firstIndex(of: ".") { k = String(k[..<punkt]) }
        return altKuerzel[k] ?? k
    }

    /// „XXBTZEUR“ → ("BTC", "EUR"), „SOL/EUR“ → ("SOL", "EUR"); `nil`, wenn keine Gegenwährung passt.
    static func paar(_ text: String) -> (basis: String, gegen: String)? {
        let roh = text.uppercased()
        if roh.contains("/") {
            let teile = roh.split(separator: "/")
            return teile.count == 2 ? (kuerzel(String(teile[0])), kuerzel(String(teile[1]))) : nil
        }
        for gegen in gegenwaehrungen where roh.hasSuffix(gegen) && roh.count > gegen.count {
            return (kuerzel(String(roh.dropLast(gegen.count))), kuerzel(gegen))
        }
        return nil
    }

    public static func erkennt(_ text: String) -> Bool {
        (try? CSVTabelle(text: text).spalten(pflichtspalten)) != nil
    }

    public static func lies(_ text: String) throws -> Kontobewegungen {
        let tabelle = CSVTabelle(text: text)
        let spalten = try tabelle.spalten(pflichtspalten)
        var ergebnis = Kontobewegungen()
        for (n, z) in tabelle.zeilen.enumerated() {
            let zeile = n + 2
            func feld(_ name: String) -> String {
                let i = spalten[name]!
                return i < z.count ? z[i].trimmingCharacters(in: .whitespaces) : ""
            }
            func zahl(_ name: String) throws -> Decimal { try KryptoWerte.zahl(feld(name), zeile: zeile) }
            let typ = feld("type").lowercased()
            guard typ == "buy" || typ == "sell", let paar = paar(feld("pair")),
                  KryptoWerte.geldwaehrungen.contains(paar.gegen), try zahl("margin") == 0
            else {
                ergebnis.hinweise.append(Importhinweis(zeile: zeile, vorgang: "\(feld("pair")) \(feld("type"))",
                                                       folge: .nichtVerbucht))
                continue
            }
            let kosten = try zahl("cost")
            ergebnis.ausfuehrungen.append(Ausfuehrung(
                id: feld("txid"), zeit: try KryptoWerte.utc(feld("time"), zeile: zeile),
                kennung: KryptoWerte.kennung(paar.basis, paar.gegen), name: paar.basis,
                seite: typ == "buy" ? .buy : .sell, menge: try zahl("vol"), preis: try zahl("price"),
                betrag: typ == "buy" ? -kosten : kosten, gebuehr: -abs(try zahl("fee")),
                waehrung: paar.gegen, produktart: .krypto, rohzeile: z))
        }
        return ergebnis
    }
}
