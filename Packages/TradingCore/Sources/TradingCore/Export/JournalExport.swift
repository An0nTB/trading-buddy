import Foundation

/// Datei für den Claude-Connector (AP12): Die App schreibt sie in den Export-Ordner,
/// der Connector liest sie und rechnet mit demselben Rechenkern.
/// Enthält je Konto die abgeschlossenen Trades, die Zeitpunkte gelöschter Orders und die
/// eigenen Journalangaben je Trade, keine Rohzeilen und keine Kontonamen.
public struct JournalExport: Sendable, Equatable, Codable {
    public static let dateiname = "trading-buddy-export.json"
    /// Erhöhen, wenn ein älterer Connector den neuen Aufbau falsch lesen würde.
    /// Neue, freiwillige Felder (etwa `journal`) erhöhen es nicht: Ältere Connectoren übergehen sie.
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
        /// Eigene Angaben je Trade, Schlüssel ist die Trade-ID. Fehlt in Dateien älterer Apps.
        public var journal: [String: Journalangaben]

        public init(broker: String, kontonummer: String, waehrung: String, trades: [Trade],
                    geloeschteOrders: [Date] = [], journal: [String: Journalangaben] = [:]) {
            self.broker = broker
            self.kontonummer = kontonummer
            self.waehrung = waehrung
            self.trades = trades
            self.geloeschteOrders = geloeschteOrders
            self.journal = journal.filter { !$0.value.istLeer }
        }

        private enum CodingKeys: String, CodingKey {
            case broker, kontonummer, waehrung, trades, geloeschteOrders, journal
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(broker: try c.decode(String.self, forKey: .broker),
                      kontonummer: try c.decode(String.self, forKey: .kontonummer),
                      waehrung: try c.decode(String.self, forKey: .waehrung),
                      trades: try c.decode([Trade].self, forKey: .trades),
                      geloeschteOrders: try c.decode([Date].self, forKey: .geloeschteOrders),
                      journal: try c.decodeIfPresent([String: Journalangaben].self, forKey: .journal) ?? [:])
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

/// Eigene Angaben zu einem Trade aus dem Journal der App, ohne den Stop
/// (der steckt schon im Trade, siehe `Trade.stopLoss`). Alle Felder freiwillig.
public struct Journalangaben: Sendable, Equatable, Codable {
    /// Name des Setups, z. B. „Ausbruch“.
    public var setup: String?
    /// Nach den eigenen Regeln gehandelt?
    public var regeltreue: Bool?
    /// Eigener Zustand von 1 (schlecht) bis 5 (sehr gut).
    public var zustand: Int?
    public var marktumfeld: String?
    /// Grund für den Einstieg, freier Text.
    public var grund: String?

    public init(setup: String? = nil, regeltreue: Bool? = nil, zustand: Int? = nil,
                marktumfeld: String? = nil, grund: String? = nil) {
        self.setup = setup
        self.regeltreue = regeltreue
        self.zustand = zustand
        self.marktumfeld = marktumfeld
        self.grund = grund
    }

    public var istLeer: Bool {
        setup == nil && regeltreue == nil && zustand == nil && marktumfeld == nil && grund == nil
    }
}

public enum ExportFehler: Error, Equatable, Sendable {
    /// Die Datei stammt von einer neueren App; der Connector muss aktualisiert werden.
    case neueresFormat(Int)
}
