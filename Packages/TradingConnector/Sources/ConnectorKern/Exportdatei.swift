import Foundation
import TradingCore

/// Liest die Exportdatei der App aus dem Export-Ordner (Datenweg seit AP6, Entscheidung 13).
/// Bei jedem Werkzeugaufruf neu, damit ein frischer Import sofort zählt.
public enum Exportdatei {
    public enum Ergebnis: Sendable, Equatable {
        case geladen(JournalExport)
        case keinOrdner
        case fehlt(pfad: String)
        case keinZugriff(pfad: String, fehler: String)
        case unlesbar(pfad: String, fehler: String)
    }

    public static func lade(ordner: String?) -> Ergebnis {
        guard let ordner, !ordner.isEmpty else { return .keinOrdner }
        let datei = URL(filePath: ordner, directoryHint: .isDirectory).appending(path: JournalExport.dateiname)
        guard FileManager.default.fileExists(atPath: datei.path) else { return .fehlt(pfad: datei.path) }
        let daten: Data
        do {
            daten = try Data(contentsOf: datei)
        } catch {
            return .keinZugriff(pfad: datei.path, fehler: error.localizedDescription)
        }
        do {
            return .geladen(try JournalExport.lese(daten))
        } catch ExportFehler.neueresFormat(let format) {
            return .unlesbar(pfad: datei.path, fehler: "Format \(format) ist neuer als dieser Connector "
                + "(\(JournalExport.aktuellesFormat)). Bitte die Erweiterung aktualisieren.")
        } catch {
            return .unlesbar(pfad: datei.path, fehler: error.localizedDescription)
        }
    }

    /// Meldung für Claude, wenn keine Daten geladen wurden; `nil` bei Erfolg.
    public static func meldung(_ ergebnis: Ergebnis) -> String? {
        switch ergebnis {
        case .geladen:
            nil
        case .keinOrdner:
            "KEIN ORDNER: In den Einstellungen der Erweiterung ist kein Export-Ordner eingetragen."
        case let .fehlt(pfad):
            "KEINE DATEN: \(pfad) fehlt. Ist in der App derselbe Export-Ordner gewählt, "
                + "und hat die App seit dem letzten Import exportiert?"
        case let .keinZugriff(pfad, fehler):
            "KEIN ZUGRIFF: \(pfad) ist nicht lesbar (\(fehler))."
        case let .unlesbar(pfad, fehler):
            "DATEI UNLESBAR: \(pfad) (\(fehler))."
        }
    }
}
