import Foundation

extension JournalExport {
    /// EZB-Referenzkurse eines Kalendertags im Export: Einheiten je 1 Euro, als Text wie die Beträge der Trades.
    public struct Tageskurse: Sendable, Equatable, Codable {
        public var tag: Journaltag
        public var kurse: [String: Decimal]

        public init(tag: Journaltag, kurse: [String: Decimal]) {
            self.tag = tag
            self.kurse = kurse
        }

        private enum CodingKeys: String, CodingKey {
            case tag, kurse
        }

        /// Ein unlesbarer Kurs fehlt nur selbst; `Waehrungsangleich` lässt den Trade dann in `ohneKurs`.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tag = try c.decode(Journaltag.self, forKey: .tag)
            let texte = try c.decode([String: String].self, forKey: .kurse)
            kurse = texte.compactMapValues { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(tag, forKey: .tag)
            try c.encode(kurse.mapValues(\.description), forKey: .kurse)
        }
    }

    /// Auszug aus `kurse` für `Waehrungsangleich` und die Steuer über die Trades in `konten`: nur Währungen, die
    /// umgerechnet werden (bei Konten außerhalb des Euro auch die Kontowährung), und nur die Tage, die die Suche
    /// ab dem Schlusstag braucht (`Referenzkurse.hoechstensTageZurueck`),
    /// in UTC mit einem Tag Puffer je Seite, damit jede Zeitzone des Nutzers abgedeckt ist.
    public static func referenzkursauszug(_ kurse: Referenzkurse, fuer konten: [Kontodaten]) -> [Tageskurse] {
        let utc = TimeZone(secondsFromGMT: 0)!
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = utc
        var codes: Set<String> = []
        var tage: Set<Journaltag> = []
        for konto in konten {
            let kontowaehrung = konto.waehrung.uppercased()
            for t in konto.trades {
                let waehrung = t.waehrung(kontowaehrung: kontowaehrung)
                // Konten außerhalb des Euro brauchen den Euro-Kurs jedes Trades für die Steuer im Connector
                // (Dritter Gegencheck G4); Euro-Konten nur die Tage mit Fremdwährung.
                guard waehrung != kontowaehrung || kurscode(kontowaehrung) != "EUR" else { continue }
                codes.insert(kurscode(waehrung))
                codes.insert(kurscode(kontowaehrung))
                for zurueck in -1...(Referenzkurse.hoechstensTageZurueck + 1) {
                    guard let zeit = kalender.date(byAdding: .day, value: -zurueck, to: t.closeTime) else { continue }
                    tage.insert(Journaltag(zeit, zeitzone: utc))
                }
            }
        }
        codes.remove("EUR")
        return tage.sorted().compactMap { tag in
            let teil = (kurse.kurse[tag] ?? [:]).filter { codes.contains($0.key) }
            return teil.isEmpty ? nil : Tageskurse(tag: tag, kurse: teil)
        }
    }

    /// Kurse dieser Datei für `Waehrungsangleich`; `nil`, wenn die App keine mitgeschrieben hat.
    public var angleichskurse: Referenzkurse? {
        guard let referenzkurse else { return nil }
        var kurse: [Journaltag: [String: Decimal]] = [:]
        for tageskurse in referenzkurse { kurse[tageskurse.tag, default: [:]].merge(tageskurse.kurse) { a, _ in a } }
        return Referenzkurse(kurse: kurse)
    }

    /// Währungscode, unter dem `Referenzkurse` sucht (USDT wie USD).
    private static func kurscode(_ waehrung: String) -> String {
        Referenzkurse.gleichgesetzt[waehrung] ?? waehrung
    }
}
