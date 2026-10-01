import Foundation

/// Experiment AP6: Kann der von Claude Desktop gestartete Server
/// eine Datei lesen, die die App in den Export-Ordner geschrieben hat?
/// (Die App Group scheiterte am Container-Schutz von macOS, Messung 01.10.2026.)
public enum Datenweg {
    public static let dateiname = "connector-test.json"

    public enum Ergebnis: Equatable, Sendable {
        case gelesen(pfad: String, inhalt: String)
        case fehlt(pfad: String)
        case keinZugriff(pfad: String, fehler: String)
        case keinOrdner
    }

    public static func pruefe(ordner: String?) -> Ergebnis {
        guard let ordner, !ordner.isEmpty else { return .keinOrdner }
        let datei = URL(filePath: ordner, directoryHint: .isDirectory).appending(path: dateiname)
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
            "FEHLT: Keine Datei unter \(pfad). Ist in der App derselbe Export-Ordner gewählt?"
        case let .keinZugriff(pfad, fehler):
            "KEIN ZUGRIFF: \(pfad) existiert, ist aber nicht lesbar. Fehler: \(fehler)"
        case .keinOrdner:
            "KEIN ORDNER: In den Einstellungen der Erweiterung ist kein Export-Ordner eingetragen."
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
