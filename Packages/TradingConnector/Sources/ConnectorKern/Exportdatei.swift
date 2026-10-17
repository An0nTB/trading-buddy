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
            return .geladen(try JournalExport.lese(daten).mitTageslage())
        } catch ExportFehler.neueresFormat(let format) {
            return .unlesbar(pfad: datei.path, fehler: "Format \(format) ist neuer als dieser Connector "
                + "(\(JournalExport.aktuellesFormat)). Bitte die Erweiterung aktualisieren.")
        } catch {
            return .unlesbar(pfad: datei.path, fehler: error.localizedDescription)
        }
    }

    /// Schreibt `Erweiterungsstand` (Version und Rechenkern dieser Erweiterung) in den Export-Ordner, damit die App
    /// eine veraltete Erweiterung erkennt (E9). Nur wenn der Ordner existiert; Fehler bleiben still, die Werkzeuge
    /// lesen weiter. Sonst schreibt die Erweiterung nichts.
    @discardableResult
    public static func meldeStand(ordner: String?, jetzt: Date = .now) -> Bool {
        guard let ordner, !ordner.isEmpty else { return false }
        let verzeichnis = URL(filePath: ordner, directoryHint: .isDirectory)
        var istOrdner: ObjCBool = false
        guard FileManager.default.fileExists(atPath: verzeichnis.path, isDirectory: &istOrdner), istOrdner.boolValue,
              let daten = try? Erweiterungsstand(erweiterung: Verbindungsstatus.connectorVersion, geschrieben: jetzt).json()
        else { return false }
        return (try? daten.write(to: verzeichnis.appending(path: Erweiterungsstand.dateiname), options: .atomic)) != nil
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
