import SwiftUI
import TradingCore

/// Zeichnet die Berichtsseiten mit `ImageRenderer` in ein PDF. Text bleibt Text (durchsuchbar,
/// scharf beim Drucken), Diagramme bleiben Vektorgrafik.
@MainActor
enum BerichtPDF {
    /// Papier ist hell: Farbwelt aus den Einstellungen, Erscheinungsbild immer Hell, Flächen ungetönt
    /// (weißes Blatt). Kontraste wie im Hell-Modus der App (Doc 10).
    static func druckthema(_ farbwelt: Farbwelt) -> Thema {
        farbwelt.thema(.light, getoent: false)
    }

    static func daten(_ bericht: Zeitraumbericht, kontext: BerichtKontext, thema: Thema) -> Data? {
        let daten = NSMutableData()
        guard let verbraucher = CGDataConsumer(data: daten as CFMutableData) else { return nil }
        var rahmen = CGRect(origin: .zero, size: BerichtMass.seite)
        let info = [kCGPDFContextTitle as String: kontext.titel,
                    kCGPDFContextCreator as String: "Henry"]
        guard let pdf = CGContext(consumer: verbraucher, mediaBox: &rahmen, info as CFDictionary) else { return nil }
        for seite in BerichtSeite.allCases {
            let ansicht = BerichtSeitenansicht(seite: seite, bericht: bericht, kontext: kontext)
                .environment(\.thema, thema)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: ansicht)
            renderer.proposedSize = ProposedViewSize(BerichtMass.seite)
            pdf.beginPDFPage(nil)
            renderer.render { _, zeichne in
                zeichne(pdf)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return daten as Data
    }

    /// Schreibt das PDF in den temporären Ordner, für Teilen-Blatt und Vorschau.
    static func temporaereDatei(_ bericht: Zeitraumbericht, kontext: BerichtKontext, thema: Thema) throws -> URL {
        guard let daten = daten(bericht, kontext: kontext, thema: thema) else { throw BerichtFehler.pdf }
        let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("Bericht", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let datei = ordner.appendingPathComponent(kontext.dateiname)
        try daten.write(to: datei, options: .atomic)
        return datei
    }
}

enum BerichtFehler: LocalizedError {
    case pdf

    var errorDescription: String? {
        switch self {
        case .pdf: String(localized: "Das PDF ließ sich nicht erzeugen.")
        }
    }
}
