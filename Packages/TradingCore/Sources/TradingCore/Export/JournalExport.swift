import Foundation

/// Datei für den Claude-Connector (AP12): Die App schreibt sie in den Export-Ordner,
/// der Connector liest sie und rechnet mit demselben Rechenkern.
/// Enthält je Konto die abgeschlossenen Trades und die Zeitpunkte gelöschter Orders,
/// keine Rohzeilen und keine Kontonamen.
public struct JournalExport: Sendable, Equatable, Codable {
    public static let dateiname = "trading-buddy-export.json"
    /// Erhöhen, wenn ein älterer Connector den neuen Aufbau falsch lesen würde.
    public static let aktuellesFormat = 1

    public var format: Int
    public var erstellt: Date
    public var rechenkern: String
    /// Zeitzone des Nutzers (z. B. „Europe/Berlin“) für Monatsgrenzen, Wochentag und Stunde.
    public var zeitzone: String
    public var konten: [Kontodaten]

    public struct Kontodaten: Sendable, Equatable, Codable {
        public var broker: String
        public var kontonummer: String
        public var waehrung: String
        public var trades: [Trade]
        /// Zeitpunkte, zu denen Pending Orders gelöscht wurden (Stornoquote, Ständiges Umplanen).
        public var geloeschteOrders: [Date]

        public init(broker: String, kontonummer: String, waehrung: String, trades: [Trade],
                    geloeschteOrders: [Date] = []) {
            self.broker = broker
            self.kontonummer = kontonummer
            self.waehrung = waehrung
            self.trades = trades
            self.geloeschteOrders = geloeschteOrders
        }

        public init(broker: String, kontonummer: String, waehrung: String,
                    positionen: [ClosedPosition], geloescht: [CancelledOrder]) {
            self.init(broker: broker, kontonummer: kontonummer, waehrung: waehrung,
                      trades: positionen.map { Trade($0) }, geloeschteOrders: geloescht.map(\.cancelledAt))
        }

        /// Broker und die letzten vier Stellen der Kontonummer, für Ausgaben an Claude.
        public var kurzname: String { "\(broker) …\(kontonummer.suffix(4))" }
    }

    public init(konten: [Kontodaten], zeitzone: TimeZone, erstellt: Date = .now) {
        format = Self.aktuellesFormat
        self.erstellt = erstellt
        rechenkern = TradingCore.version
        self.zeitzone = zeitzone.identifier
        self.konten = konten
    }

    /// Zeitzone des Nutzers; UTC, falls der Name unbekannt ist.
    public var nutzerZeitzone: TimeZone {
        TimeZone(identifier: zeitzone) ?? TimeZone(secondsFromGMT: 0)!
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func lese(_ daten: Data) throws -> JournalExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(JournalExport.self, from: daten)
        guard export.format <= aktuellesFormat else { throw ExportFehler.neueresFormat(export.format) }
        return export
    }
}

public enum ExportFehler: Error, Equatable, Sendable {
    /// Die Datei stammt von einer neueren App; der Connector muss aktualisiert werden.
    case neueresFormat(Int)
}
