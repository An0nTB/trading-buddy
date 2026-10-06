import Foundation

/// Ein Eintrag der Merkliste, wie dieses Paket ihn braucht. Den gespeicherten Typ (Merkposten)
/// führt TradingCore; die App bildet ihn hierauf ab.
public struct Merkbegriff: Codable, Hashable, Sendable {
    public enum Art: String, Codable, Sendable, CaseIterable {
        /// Börsenkürzel, z. B. `AAPL` oder `SAP.DE`.
        case symbol
        /// ISIN, z. B. `DE0007164600`.
        case isin
        /// Firmenname als zusammenhängende Wortfolge, z. B. „Deutsche Bank“.
        case name
        /// Freie Stichworte; alle Wörter müssen vorkommen, Reihenfolge egal, z. B. „Nvidia Zölle“.
        case stichwort
    }

    public var art: Art
    public var text: String

    public init(art: Art, text: String) {
        self.art = art
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Ordnet Meldungen der Merkliste zu.
/// Symbole: Treffer in den Symbolen der Meldung (Alpaca, Marketaux), sonst als ganzes Wort in Großschreibung
/// in Überschrift oder Anriss, aber nur ab drei Zeichen (sonst zu viele Zufallstreffer wie „A“ oder „T“).
/// Index-CFDs („DE40.c“, „US500“) zusätzlich über den Indexnamen (`Indizes`).
/// Name und Stichwort: ganze Wörter, Groß- und Kleinschreibung egal. Die Trefferquote für DE-Werte ist
/// unbekannt und wird im Test gemessen (R6 Abschnitt 7).
public enum Zuordnung {
    public static func trifft(_ meldung: Meldung, _ begriff: Merkbegriff) -> Bool {
        let text = meldung.titel + " " + (meldung.anriss ?? "")
        switch begriff.art {
        case .symbol:
            let gesucht = begriff.text.uppercased()
            guard !gesucht.isEmpty else { return false }
            let basis = basisSymbol(gesucht)
            if meldung.symbole.contains(where: { $0.uppercased() == gesucht || basisSymbol($0.uppercased()) == basis }) {
                return true
            }
            // Index-CFDs: Meldungen nennen den Index beim Namen, als ganze Wortfolge („S&P 500“, nicht „Dowdy“).
            if let namen = Indizes.namen(fuer: gesucht),
               namen.contains(where: { enthaeltFolge(woerter(text), woerter($0)) }) {
                return true
            }
            guard basis.count >= 3 else { return false }
            let grosseWoerter = text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == ".") })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            return grosseWoerter.contains(gesucht) || grosseWoerter.contains(basis)
        case .isin:
            let gesucht = begriff.text.uppercased()
            return gesucht.count == 12 && text.uppercased().contains(gesucht)
        case .name:
            let gesucht = woerter(begriff.text)
            return !gesucht.isEmpty && enthaeltFolge(woerter(text), gesucht)
        case .stichwort:
            let gesucht = woerter(begriff.text)
            let vorhanden = Set(woerter(text))
            return !gesucht.isEmpty && gesucht.allSatisfy(vorhanden.contains)
        }
    }

    /// Je Begriff die passenden Meldungen, Reihenfolge der Meldungen bleibt.
    public static func gruppiert(_ meldungen: [Meldung], nach begriffe: [Merkbegriff]) -> [Merkbegriff: [Meldung]] {
        var ergebnis: [Merkbegriff: [Meldung]] = [:]
        for begriff in begriffe {
            ergebnis[begriff] = meldungen.filter { trifft($0, begriff) }
        }
        return ergebnis
    }

    /// `SAP.DE` → `SAP`; `BTC/USD` und `AAPL` bleiben.
    static func basisSymbol(_ symbol: String) -> String {
        symbol.split(separator: ".").first.map(String.init) ?? symbol
    }

    /// Wörter aus Buchstaben und Ziffern, klein geschrieben.
    static func woerter(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    static func enthaeltFolge(_ woerter: [String], _ folge: [String]) -> Bool {
        guard folge.count <= woerter.count else { return false }
        for start in 0...(woerter.count - folge.count) where Array(woerter[start..<(start + folge.count)]) == folge {
            return true
        }
        return false
    }
}
