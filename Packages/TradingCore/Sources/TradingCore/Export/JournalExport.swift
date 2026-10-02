import Foundation

/// Datei für den Claude-Connector (AP12): Die App schreibt sie in den Export-Ordner,
/// der Connector liest sie und rechnet mit demselben Rechenkern.
/// Enthält je Konto die abgeschlossenen Trades, die Zeitpunkte gelöschter Orders und die
/// eigenen Journalangaben je Trade, die Ziele früherer Reviews und die eigenen Handelsregeln, dazu Tagesnotizen
/// und verpasste Trades, auf Wunsch Überschriften der Nachrichten und Tageskerzen geladener Kurse, dazu die
/// EZB-Referenzkurse für die Umrechnung in die Kontowährung und die Ausstiegsanalysen je Trade; keine Rohzeilen,
/// keine Kontonamen, keine Bilder und keine Minutenkerzen.
public struct JournalExport: Sendable, Equatable, Codable {
    public static let dateiname = "trading-buddy-export.json"
    /// Erhöhen, wenn ein älterer Connector den neuen Aufbau falsch lesen würde.
    /// Neue, freiwillige Felder (etwa `journal`, `ziele`) erhöhen es nicht: Ältere Connectoren übergehen sie.
    /// 2 seit `Trade.waehrung` (Rechenkern 0.17.0): Ein Connector vor 0.8.0 zählte USD-Beträge still als Kontowährung
    /// (Zweiter Gegencheck W4); er meldet jetzt „neueres Format“ statt falsch zu rechnen.
    public static let aktuellesFormat = 2

    public var format: Int
    public var erstellt: Date
    public var rechenkern: String
    /// Zeitzone des Nutzers (z. B. „Europe/Berlin“) für Monatsgrenzen, Wochentag und Stunde.
    public var zeitzone: String
    public var konten: [Kontodaten]
    /// Tonfall der App („henry“, früher „bro“, oder „sachlich“), damit Claude denselben Ton nimmt.
    /// Fehlt in älteren Dateien; dann gilt sachlich.
    public var ton: String?
    /// Persona-Ton der App „Henry“ (Entscheidung 49, 02.10.2026).
    public static let tonHenry = "henry"
    /// Früherer Persona-Ton „Brad“; ältere Exporte tragen ihn noch, er gilt wie `tonHenry`.
    public static let tonBro = "bro"
    /// Darf der erste Satz der Antwort in der Art der Persona klingen? Fehlt das Feld, gilt sachlich.
    public var personaTon: Bool { ton == Self.tonHenry || ton == Self.tonBro }
    /// Tagesnotizen (Plan und Rückblick) aller Tage, nach Tag sortiert; gelten für alle Konten.
    /// Fehlt in Dateien älterer Apps und wenn es keine gibt.
    public var tagesnotizen: [Notiz]?
    /// Verpasste Trades mit Grund, nach Zeit sortiert; gelten für alle Konten. Fehlt wie `tagesnotizen`.
    public var verpassteTrades: [Verpasst]?
    /// Nachrichten der letzten Tage, neueste zuerst; nur wenn die Nachrichten in der App eingeschaltet sind.
    public var nachrichten: [Meldung]?
    /// Tageskerzen geladener Werte, nach Symbol; fehlt ohne Kursverlauf in der App (Doc 38).
    public var kursverlauf: [Kursreihe]?
    /// EZB-Referenzkurse der Tage, an denen Trades in fremder Währung schlossen, nach Tag; nur Währungen dieser Trades.
    /// Fehlt ohne Fremdwährung oder ohne geladene Kurse; dann rechnet der Connector je Währung getrennt.
    public var referenzkurse: [Tageskurse]?

    public struct Kontodaten: Sendable, Equatable, Codable {
        public var broker: String
        public var kontonummer: String
        public var waehrung: String
        public var trades: [Trade]
        /// Zeitpunkte, zu denen Pending Orders gelöscht wurden (Stornoquote, Ständiges Umplanen).
        public var geloeschteOrders: [Date]
        /// Eigene Angaben je Trade, Schlüssel ist die Trade-ID. Fehlt in Dateien älterer Apps.
        public var journal: [String: Journalangaben]
        /// Ziele aus früheren Reviews, nach Beginn sortiert. Fehlt in Dateien älterer Apps.
        public var ziele: [Reviewziel]
        /// Eigene Handelsregeln des Kontos; `nil`, wenn keine gesetzt ist oder die Datei älter ist.
        public var regeln: Handelsregeln?
        /// Ausstiegsanalysen der Trades mit Kerzen in der App, nach Trade-ID sortiert (Doc 39, B4).
        /// Fehlt ohne gespeicherte Kerzen und in Dateien älterer Apps.
        public var ausstieg: [Ausstieg]?

        public init(broker: String, kontonummer: String, waehrung: String, trades: [Trade],
                    geloeschteOrders: [Date] = [], journal: [String: Journalangaben] = [:],
                    ziele: [Reviewziel] = [], regeln: Handelsregeln? = nil, ausstieg: [Ausstieg] = []) {
            self.broker = broker
            self.kontonummer = kontonummer
            self.waehrung = waehrung
            self.trades = trades
            self.geloeschteOrders = geloeschteOrders
            self.journal = journal.filter { !$0.value.istLeer }
            self.ziele = ziele
            self.regeln = regeln.flatMap { $0.leer ? nil : $0 }
            let ids = Set(trades.map(\.id))
            let analysen = ausstieg.filter { ids.contains($0.tradeID) }.sorted { $0.tradeID < $1.tradeID }
            self.ausstieg = analysen.isEmpty ? nil : analysen
        }

        /// Ausstiegsanalysen nach Trade-ID.
        public var ausstiegJeTrade: [String: Ausstieg] {
            Dictionary((ausstieg ?? []).map { ($0.tradeID, $0) }, uniquingKeysWith: { erste, _ in erste })
        }

        private enum CodingKeys: String, CodingKey {
            case broker, kontonummer, waehrung, trades, geloeschteOrders, journal, ziele, regeln, ausstieg
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(broker: try c.decode(String.self, forKey: .broker),
                      kontonummer: try c.decode(String.self, forKey: .kontonummer),
                      waehrung: try c.decode(String.self, forKey: .waehrung),
                      trades: try c.decode([Trade].self, forKey: .trades),
                      geloeschteOrders: try c.decode([Date].self, forKey: .geloeschteOrders),
                      journal: try c.decodeIfPresent([String: Journalangaben].self, forKey: .journal) ?? [:],
                      ziele: try c.decodeIfPresent([Reviewziel].self, forKey: .ziele) ?? [],
                      // Ändert sich der Aufbau der Regeln später, fehlen nur sie, nicht das ganze Konto.
                      regeln: try? c.decodeIfPresent(Handelsregeln.self, forKey: .regeln),
                      // Ebenso die Ausstiegsanalysen.
                      ausstieg: (try? c.decodeIfPresent([Ausstieg].self, forKey: .ausstieg)) ?? [])
        }

        public init(broker: String, kontonummer: String, waehrung: String,
                    positionen: [ClosedPosition], geloescht: [CancelledOrder]) {
            self.init(broker: broker, kontonummer: kontonummer, waehrung: waehrung,
                      trades: positionen.map { Trade($0) }, geloeschteOrders: geloescht.map(\.cancelledAt))
        }

        /// Broker und die letzten vier Stellen der Kontonummer, ohne Blick auf andere Konten.
        /// Für Ausgaben an Claude `JournalExport.kurzname(_:)` nehmen.
        public var kurzname: String { "\(broker) …\(kontonummer.suffix(4))" }
    }

    /// Wie viele Endziffern nötig sind, damit sich `nummer` von den anderen Nummern unterscheidet; mindestens vier.
    public static func endziffern(_ nummer: String, neben andere: [String]) -> Int {
        var stellen = 4
        while stellen < nummer.count,
              andere.contains(where: { $0 != nummer && $0.suffix(stellen) == nummer.suffix(stellen) }) {
            stellen += 1
        }
        return stellen
    }

    /// Broker und Endziffern eines Kontos dieser Datei, für Ausgaben an Claude. Gleiche letzte vier
    /// Stellen beim selben Broker bekommen weitere Stellen, damit Claude die Konten unterscheiden kann.
    public func kurzname(_ konto: Kontodaten) -> String {
        let andere = konten.filter { $0.broker == konto.broker }.map(\.kontonummer)
        return "\(konto.broker) …\(konto.kontonummer.suffix(Self.endziffern(konto.kontonummer, neben: andere)))"
    }

    public init(konten: [Kontodaten], zeitzone: TimeZone, erstellt: Date = .now, ton: String? = nil,
                tagesnotizen: [Notiz] = [], verpassteTrades: [Verpasst] = [], nachrichten: [Meldung] = [],
                kursverlauf: [Kursreihe] = [], referenzkurse: [Tageskurse] = []) {
        format = Self.aktuellesFormat
        self.erstellt = erstellt
        rechenkern = TradingCore.version
        self.zeitzone = zeitzone.identifier
        self.konten = konten
        self.ton = ton
        let notizen = tagesnotizen.filter { !$0.istLeer }.sorted { $0.tag < $1.tag }
        self.tagesnotizen = notizen.isEmpty ? nil : notizen
        self.verpassteTrades = verpassteTrades.isEmpty ? nil : verpassteTrades.sorted { ($0.zeit, $0.id) < ($1.zeit, $1.id) }
        let meldungen = nachrichten.sorted { ($0.zeit, $1.link) > ($1.zeit, $0.link) }.prefix(Self.nachrichtenHoechstens)
        self.nachrichten = meldungen.isEmpty ? nil : Array(meldungen)
        let reihen = kursverlauf.filter { !$0.kerzen.isEmpty }.sorted { $0.symbol < $1.symbol }
            .prefix(Self.kursreihenHoechstens)
        self.kursverlauf = reihen.isEmpty ? nil : Array(reihen)
        self.referenzkurse = referenzkurse.isEmpty ? nil : referenzkurse.sorted { $0.tag < $1.tag }
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

    /// Prüft das Format vor dem Rest: Eine neuere Datei kann Felder in neuer Form tragen, an denen das volle
    /// Lesen scheitern würde; dann soll die Meldung „neueres Format“ lauten, nicht ein Lesefehler (Befund G7).
    public static func lese(_ daten: Data) throws -> JournalExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let kopf = try? decoder.decode(Formatkopf.self, from: daten), kopf.format > aktuellesFormat {
            throw ExportFehler.neueresFormat(kopf.format)
        }
        let export = try decoder.decode(JournalExport.self, from: daten)
        guard export.format <= aktuellesFormat else { throw ExportFehler.neueresFormat(export.format) }
        return export
    }

    private struct Formatkopf: Decodable {
        var format: Int
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
