import Foundation

extension JournalExport {
    /// Prüfstände des Kill-Kriteriums (E7) über alle Konten dieser Datei, getrennt nach Kontoart (E1), mit dem
    /// Setup aus dem Journal. Trades in fremder Währung zählen nach dem Angleich mit den Kursen der Datei wie in der
    /// App; ohne Kurs zählen sie mit, aber nur mit R aus dem Stop: Das geplante Risiko steht in Kontowährung und gäbe
    /// gegen ein Ergebnis in anderer Währung ein falsches R. Das Beispielkonto zählt nicht, seine Trades sind erfunden.
    public func setuppruefungen(_ playbook: [Setup]) -> [Setuppruefung] {
        let kurse = angleichskurse
        let konten = self.konten.filter { !$0.istBeispiel }.map { konto -> (kontoart: Kontoart, trades: [Trade],
                                                                       setups: [String: String]) in
            let angleich = Waehrungsangleich(konto.trades, kontowaehrung: konto.waehrung, kurse: kurse)
            return (kontoart: konto.art, trades: angleich.trades + angleich.ohneKurs.map { $0.mitGeplantemRisiko(nil) },
                    setups: konto.journal.compactMapValues(\.setup))
        }
        return Setuppruefung.berechne(playbook: playbook, konten: konten)
    }

    /// Kurzname mit Kontoart, für Ausgaben an Claude: Demo-Konten tragen immer „(Demo)“, Echtgeld-Konten
    /// „(Echtgeld)“, sobald die Datei auch ein Demo-Konto enthält. So vermischt keine Antwort die beiden (E1).
    /// Das Beispielkonto heißt „(Beispielkonto)“: Es ist weder das eine noch das andere.
    public func bezeichnung(_ konto: Kontodaten) -> String {
        if konto.istBeispiel { return kurzname(konto) + " (Beispielkonto)" }
        switch konto.art {
        case .demo: kurzname(konto) + " (Demo)"
        case .echt: konten.contains { $0.art == .demo } ? kurzname(konto) + " (Echtgeld)" : kurzname(konto)
        }
    }
}

/// Statusdatei der Erweiterung (E9, Tim 17.10.2026): Die Erweiterung schreibt sie beim Start und bei jedem
/// Werkzeugaufruf in den Export-Ordner, neben `JournalExport.dateiname`; die App liest sie und warnt, wenn die
/// Erweiterung mit einem anderen Rechenkern rechnet. Fehlt die Datei, ist die Erweiterung älter als 0.20.0 oder
/// wurde noch nie aufgerufen.
public struct Erweiterungsstand: Sendable, Equatable, Codable {
    public static let dateiname = "trading-buddy-erweiterung.json"

    /// Version der Erweiterung (`Connector/manifest.json`).
    public var erweiterung: String
    /// `TradingCore.version` der Erweiterung.
    public var rechenkern: String
    /// Höchstes Exportformat, das die Erweiterung liest (`JournalExport.aktuellesFormat`).
    public var format: Int
    public var geschrieben: Date

    public init(erweiterung: String, rechenkern: String = TradingCore.version,
                format: Int = JournalExport.aktuellesFormat, geschrieben: Date = .now) {
        self.erweiterung = erweiterung
        self.rechenkern = rechenkern
        self.format = format
        self.geschrieben = geschrieben
    }

    /// Rechnet die Erweiterung mit demselben Rechenkern wie dieses Programm?
    public var passtZurApp: Bool { rechenkern == TradingCore.version }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func lese(_ daten: Data) throws -> Erweiterungsstand {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Erweiterungsstand.self, from: daten)
    }
}
