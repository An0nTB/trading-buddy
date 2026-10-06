import Foundation

/// Index-CFDs der Broker (MT4/MT5) heißen „DE40.c“, „US500“ oder „NAS100“; Meldungen schreiben „DAX“, „S&P 500“
/// oder „Nasdaq 100“. Gleiche Tabelle wie der Connector (ConnectorKern `Ausgabe.indexnamen`, 0.16.1), damit App
/// und Claude dieselben Meldungen finden.
public enum Indizes {
    /// Kürzel klein geschrieben → Indexnamen, der erste ist die übliche Schreibweise für die Suche.
    static let tabelle: [String: [String]] = {
        let gruppen: [([String], [String])] = [
            (["de40", "ger40", "dax40", "deu40", "de30", "ger30", "dax30", "gdaxi", "dax"], ["dax"]),
            (["us500", "spx500", "sp500", "spx", "usa500"], ["s&p 500", "s&p500", "sp500"]),
            (["nas100", "ustec", "us100", "nasdaq100", "nsdq100", "ndx", "ustech100"], ["nasdaq 100", "nasdaq100", "nasdaq"]),
            (["us30", "dj30", "dji", "dow30", "usa30", "wallstreet30"], ["dow jones", "dow"]),
            (["uk100", "ftse100", "gbr100"], ["ftse 100", "ftse"]),
            (["jp225", "jpn225", "nikkei225", "ni225", "jap225"], ["nikkei 225", "nikkei"]),
            (["eu50", "eustx50", "stoxx50", "estx50", "euro50", "eustoxx50"], ["euro stoxx 50", "euro stoxx", "eurostoxx"]),
            (["fra40", "f40", "cac40", "fr40"], ["cac 40", "cac"]),
            (["us2000", "rus2000", "rty"], ["russell 2000", "russell"]),
            (["aus200", "asx200"], ["asx 200", "asx"]),
            (["hk50", "hsi", "hk33"], ["hang seng"]),
            (["esp35", "spa35", "es35", "ibex35"], ["ibex 35", "ibex"])
        ]
        var namen: [String: [String]] = [:]
        for (kuerzel, indexname) in gruppen {
            for k in kuerzel { namen[k] = indexname }
        }
        return namen
    }()

    /// Indexnamen zu einem Symbol, `nil`, wenn es kein bekanntes Index-Kürzel ist. Broker-Zusätze fallen weg:
    /// vorn „#“ oder „.“, nach Punkt, Doppelpunkt, Schrägstrich, Unterstrich oder Bindestrich alles, angehängt
    /// „cash“, „spot“, „usd“, „eur“, „c“ oder „m“ („#GER40_cash“, „DE40.c“, „US500cash“ → Index).
    public static func namen(fuer symbol: String) -> [String]? {
        let ohnePraefix = symbol.lowercased().drop(while: { $0 == "#" || $0 == "." })
        guard let basis = ohnePraefix.split(whereSeparator: { ".:/_-".contains($0) }).first.map(String.init),
              basis.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        if let gefunden = tabelle[basis] { return gefunden }
        for zusatz in ["cash", "spot", "usd", "eur", "c", "m"] where basis.hasSuffix(zusatz) {
            if let gefunden = tabelle[String(basis.dropLast(zusatz.count))] { return gefunden }
        }
        return nil
    }
}
