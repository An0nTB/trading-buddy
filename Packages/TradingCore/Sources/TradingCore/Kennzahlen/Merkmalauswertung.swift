import Foundation

/// Kennzahlen je frei vergebenem Merkmal eines Trades: Tags, Zustand („1“–„5“), Marktumfeld oder anderes
/// aus dem Journal (Tim 05.10.2026). Die Werte kommen von außen (Store), der Kern rechnet nur.
/// Ein Trade kann mehrere Merkmale tragen und zählt dann in jeder dieser Gruppen; dasselbe Merkmal zweimal am
/// selben Trade zählt einmal. Merkmale werden ohne Rücksicht auf Groß- und Kleinschreibung und ohne Leerzeichen
/// am Rand zusammengefasst. Beträge in Kontowährung (vorher `Waehrungsangleich`).
public struct Merkmalauswertung: Sendable, Equatable {
    public struct JeMerkmal: Sendable, Equatable {
        /// Häufigste Schreibweise über alle Nennungen; bei Gleichstand die alphabetisch erste.
        public var merkmal: String
        public var anzahl: Int
        public var netto: Decimal
        public var trefferquote: Decimal?
        /// Ø R der Trades mit bekanntem Risiko; `nil` ohne solche.
        public var durchschnittR: Decimal?
        public var verlierer: Int
        /// Verlierer mit diesem Merkmal ÷ alle Verlierer der übergebenen Trades; `nil` ohne Verlierer.
        public var anteilAnVerlierern: Decimal?
        /// Nach Schlusszeit, bei gleicher Zeit nach ID.
        public var tradeIDs: [Trade.ID]
    }

    /// Nach Netto absteigend, bei Gleichstand nach Merkmal.
    public var merkmale: [JeMerkmal]
    /// Trades ohne ein (nicht leeres) Merkmal.
    public var ohneMerkmal: Int

    /// - Parameter merkmale: Merkmale je Trade-ID; IDs ohne Trade in `trades` werden übergangen.
    public init(trades: [Trade], merkmale: [Trade.ID: [String]]) {
        let sortiert = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        let alleVerlierer = sortiert.filter { $0.outcome == .loss }.count
        var jeSchluessel: [String: [Trade]] = [:]
        var schreibweisen: [String: [String: Int]] = [:]
        var ohne = 0
        for t in sortiert {
            var gesehen: Set<String> = []
            for roh in merkmale[t.id] ?? [] {
                let text = roh.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let schluessel = text.lowercased()
                schreibweisen[schluessel, default: [:]][text, default: 0] += 1
                if gesehen.insert(schluessel).inserted { jeSchluessel[schluessel, default: []].append(t) }
            }
            if gesehen.isEmpty { ohne += 1 }
        }
        var ergebnis: [JeMerkmal] = []
        for (schluessel, teil) in jeSchluessel {
            let k = Kennzahlen(trades: teil)
            let anteil: Decimal? = alleVerlierer > 0 ? Decimal(k.verlierer) / Decimal(alleVerlierer) : nil
            ergebnis.append(JeMerkmal(
                merkmal: Self.haeufigste(schreibweisen[schluessel] ?? [:], ersatz: schluessel), anzahl: k.anzahl,
                netto: k.netto, trefferquote: k.trefferquote, durchschnittR: k.erwartungswertR, verlierer: k.verlierer,
                anteilAnVerlierern: anteil, tradeIDs: teil.map(\.id)))
        }
        self.merkmale = ergebnis.sorted { a, b in
            a.netto != b.netto ? a.netto > b.netto : a.merkmal < b.merkmal
        }
        ohneMerkmal = ohne
    }

    static func haeufigste(_ zaehlung: [String: Int], ersatz: String) -> String {
        let reihenfolge = zaehlung.keys.sorted { a, b in
            let na = zaehlung[a] ?? 0
            let nb = zaehlung[b] ?? 0
            return na != nb ? na > nb : a < b
        }
        return reihenfolge.first ?? ersatz
    }
}
