import SwiftUI
import TradingCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Anonymisierte Probe einer Datei, die das Import-Blatt nicht lesen kann (Kern `AnonymeProbe`, TradingCore 0.23.0):
/// höchstens 50 Zeilen, Namen, Konto- und Ordernummern ersetzt. Der Nutzer sieht die Probe vor dem Sichern, weil
/// Freitext (Verwendungszweck, Notizen) weitere Angaben enthalten kann. Gedacht zum Weitergeben mit „Problem melden“.
struct ProbeKarte: View {
    let daten: Data
    @Environment(\.thema) private var thema
    @State private var probe: AnonymeProbe.Ergebnis?
    @State private var fehler: String?

    /// Nur Textdateien ergeben eine Probe; Excel und andere Binärdateien nicht.
    static func moeglich(_ daten: Data) -> Bool { Importtext.lies(daten) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            if let probe {
                Text("Bitte vor dem Weitergeben ansehen, Freitext kann weitere Angaben enthalten.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                ScrollView {
                    Text(verbatim: probe.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(thema.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Abstand.kachelInnen)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
                Text(verbatim: Self.zusammenfassung(probe))
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                HStack {
                    #if os(macOS)
                    Button("Sichern …") { sichere(probe.text) }
                    #else
                    ShareLink(item: probe.text) { Text("Teilen …") }
                    #endif
                    if let fehler {
                        Text(verbatim: fehler).font(Schrift.beschriftung).foregroundStyle(thema.verlust)
                    }
                }
            } else {
                Button("Anonymisierte Probe speichern …") {
                    guard let text = Importtext.lies(daten) else { return }
                    probe = AnonymeProbe.erstelle(text, hoechstensZeilen: 50)
                }
            }
        }
    }

    /// „3 ersetzt (Konto: 1, Name: 2) · 120 Zeilen weggelassen“; Arten alphabetisch.
    static func zusammenfassung(_ probe: AnonymeProbe.Ergebnis) -> String {
        let summe = probe.ersetzt.values.reduce(0, +)
        var text = String(localized: "\(summe) Angaben ersetzt")
        if !probe.ersetzt.isEmpty {
            text += " (" + probe.ersetzt.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                .joined(separator: ", ") + ")"
        }
        if probe.weggelassen > 0 {
            text += " · " + String(localized: "\(probe.weggelassen) Zeilen weggelassen")
        }
        return text
    }

    #if os(macOS)
    private func sichere(_ text: String) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Anonymisierte Probe sichern")
        panel.allowedContentTypes = [.plainText]
        // Neutraler Name: Dateinamen der Broker enthalten oft die Kontonummer.
        panel.nameFieldStringValue = "Importprobe.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let ziel = panel.url else { return }
        do {
            try Data(text.utf8).write(to: ziel, options: .atomic)
            fehler = nil
        } catch {
            fehler = error.localizedDescription
        }
    }
    #endif
}
