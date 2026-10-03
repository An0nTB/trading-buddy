import SwiftUI
import TradingCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Gemeinsamer Weg vom fertigen Bericht zur Datei: Mac mit Sichern-Dialog, iPhone und iPad über eine
/// temporäre Datei für Vorschau und Teilen-Blatt. Genutzt vom Menü und vom Blatt „Bericht für Zeitraum“.
@MainActor
enum BerichtAusgabe {
    #if os(macOS)
    /// Zeigt den Sichern-Dialog und schreibt das PDF. `false`, wenn der Nutzer abbricht.
    static func sichern(_ ergebnis: BerichtErgebnis, thema: Thema) throws -> Bool {
        guard let daten = BerichtPDF.daten(ergebnis.bericht, kontext: ergebnis.kontext, thema: thema) else {
            throw BerichtFehler.pdf
        }
        return try sichern(daten, dateiname: ergebnis.kontext.dateiname)
    }

    static func sichern(_ daten: Data, dateiname: String) throws -> Bool {
        let panel = NSSavePanel()
        panel.title = String(localized: "Bericht sichern")
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = dateiname
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let ziel = panel.url else { return false }
        try daten.write(to: ziel, options: .atomic)
        return true
    }
    #else
    /// Schreibt das PDF in den temporären Ordner für die Vorschau.
    static func datei(_ ergebnis: BerichtErgebnis, thema: Thema) throws -> BerichtDatei {
        guard let daten = BerichtPDF.daten(ergebnis.bericht, kontext: ergebnis.kontext, thema: thema) else {
            throw BerichtFehler.pdf
        }
        return try datei(daten, dateiname: ergebnis.kontext.dateiname)
    }

    static func datei(_ daten: Data, dateiname: String) throws -> BerichtDatei {
        BerichtDatei(url: try BerichtPDF.temporaereDatei(daten, dateiname: dateiname))
    }
    #endif
}
