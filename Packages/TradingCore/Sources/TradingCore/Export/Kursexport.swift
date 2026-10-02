import Foundation

extension JournalExport {
    /// Tageskerzen eines Werts für die Kursanalyse über den Connector (Doc 38, Paket A3).
    /// Die App lädt sie (TradingQuotes, A1); der Connector rechnet daraus `Kursanalyse` und hat selbst kein Netz.
    public struct Kursreihe: Sendable, Equatable, Codable {
        /// Symbol wie im Journal (`Trade.symbol`), damit eigene Trades dazu passen.
        public var symbol: String
        /// Kursquelle, etwa „kraken“ oder „alpaca“.
        public var quelle: String
        /// Währung der Kurse, etwa USD.
        public var waehrung: String
        /// Zeitpunkt des letzten Abrufs.
        public var stand: Date
        /// Nach Tag sortiert, höchstens `kerzenHoechstens`; eine laufende Kerze steht zuletzt.
        public var kerzen: [Kerze]

        public init(symbol: String, quelle: String, waehrung: String, stand: Date, kerzen: [Kerze]) {
            self.symbol = symbol
            self.quelle = quelle
            self.waehrung = waehrung.uppercased()
            self.stand = stand
            var jeTag: [Journaltag: Kerze] = [:]
            for k in kerzen { jeTag[k.tag] = k }
            self.kerzen = Array(jeTag.values.sorted { $0.tag < $1.tag }.suffix(JournalExport.kerzenHoechstens))
        }

        private enum CodingKeys: String, CodingKey {
            case symbol, quelle, waehrung, stand, kerzen
        }

        /// Eine unlesbare Kerze kostet nur die Kerzen dieser Reihe, nicht die ganze Datei.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try c.decode(String.self, forKey: .symbol)
            quelle = try c.decode(String.self, forKey: .quelle)
            waehrung = try c.decode(String.self, forKey: .waehrung)
            stand = try c.decode(Date.self, forKey: .stand)
            kerzen = (try? c.decodeIfPresent([Kerze].self, forKey: .kerzen)) ?? []
        }
    }

    /// So viele Tageskerzen trägt eine Reihe höchstens (ein Jahr mit Wochenenden und Puffer).
    public static let kerzenHoechstens = 370
    /// So viele Reihen trägt die Datei höchstens.
    public static let kursreihenHoechstens = 60
}
