import Foundation

/// Experiment AP6: Kann der von Claude Desktop gestartete Server
/// eine Datei lesen, die die App in ihre App Group geschrieben hat?
public enum Datenweg {
    public static let dateiname = "connector-test.json"

    public enum Ergebnis: Equatable, Sendable {
        case gelesen(pfad: String, inhalt: String)
        case fehlt(pfad: String)
        case keinZugriff(pfad: String, fehler: String)
        case keineGruppe
    }

    /// Ordner der App Group, z. B. ~/Library/Group Containers/ABCDE12345.journal
    public static func ordner(gruppe: String, home: URL) -> URL {
        home.appending(path: "Library/Group Containers/\(gruppe)", directoryHint: .isDirectory)
    }

    public static func pruefe(gruppe: String?, home: URL) -> Ergebnis {
        guard let gruppe, !gruppe.isEmpty else { return .keineGruppe }
        let datei = ordner(gruppe: gruppe, home: home).appending(path: dateiname)
        guard FileManager.default.fileExists(atPath: datei.path) else {
            return .fehlt(pfad: datei.path)
        }
        do {
            let inhalt = try String(contentsOf: datei, encoding: .utf8)
            return .gelesen(pfad: datei.path, inhalt: inhalt)
        } catch {
            return .keinZugriff(pfad: datei.path, fehler: error.localizedDescription)
        }
    }

    public static func text(_ ergebnis: Ergebnis) -> String {
        switch ergebnis {
        case let .gelesen(pfad, inhalt):
            "ERFOLG: Datei der App gelesen.\nPfad: \(pfad)\nInhalt: \(inhalt)"
        case let .fehlt(pfad):
            "FEHLT: Keine Datei unter \(pfad). Wurde die App einmal gestartet?"
        case let .keinZugriff(pfad, fehler):
            "KEIN ZUGRIFF: \(pfad) existiert, ist aber nicht lesbar. Fehler: \(fehler)"
        case .keineGruppe:
            "KEINE GRUPPE: Umgebungsvariable TB_APP_GROUP fehlt im Manifest."
        }
    }
}

/// Feste Beispielwerte für den ersten Werkzeugaufruf (keine echten Trades).
public enum Beispielkennzahlen {
    public static let text = """
        Beispielwerte aus dem Trading Buddy (Experiment, keine echten Trades):
        Trades: 24
        Trefferquote: 41,7 %
        Profitfaktor: 1,32
        Erwartungswert: 0,18 R je Trade
        Größter Verlust: -1,9 R
        """
}
