import SwiftUI
import TradingCore
#if os(macOS)
import AppKit
#endif

/// Die letzten Importfehler dieser Sitzung, nur im Speicher, für „Problem melden“. Ohne Dateinamen, weil Broker
/// die Kontonummer oft in den Namen schreiben.
@MainActor
enum Fehlerprotokoll {
    private(set) static var eintraege: [(zeit: Date, text: String)] = []
    static let hoechstens = 10

    static func merke(_ text: String, zeit: Date = Date()) {
        eintraege.append((zeit, text))
        if eintraege.count > hoechstens { eintraege.removeFirst(eintraege.count - hoechstens) }
    }
}

/// Diagnosetext für Tester (Nachtpaket AP11): Versionen, System, Zahl der Konten und die letzten Importfehler.
/// Keine Trades, keine Beträge, keine Pfade mit Benutzernamen, keine langen Nummern.
enum Diagnose {
    struct Angaben {
        var app: String
        var kern: String
        var connector: String
        var system: String
        var konten: Int
        var importordnerAktiv: Bool
        var fehler: [(zeit: Date, text: String)]
    }

    static func text(_ a: Angaben) -> String {
        var zeilen = [
            "Henry – Diagnose",
            "App: \(a.app)",
            "Rechenkern: \(a.kern)",
            "Connector (gleicher Stand): \(a.connector)",
            "System: \(a.system)",
            "Konten: \(a.konten)",
            "Import-Ordner: \(a.importordnerAktiv ? "an" : "aus")",
        ]
        if a.fehler.isEmpty {
            zeilen.append("Importfehler in dieser Sitzung: keine")
        } else {
            zeilen.append("Importfehler in dieser Sitzung:")
            let format = ISO8601DateFormatter()
            for f in a.fehler {
                zeilen.append("- \(format.string(from: f.zeit)): \(f.text)")
            }
        }
        return bereinigt(zeilen.joined(separator: "\n"))
    }

    /// Entfernt Benutzernamen aus Pfaden und kürzt Ziffernfolgen ab fünf Stellen (Konto-, Order-, Ticketnummern).
    static func bereinigt(_ text: String, heimordner: String = NSHomeDirectory()) -> String {
        var t = text
        if heimordner.count > 1 { t = t.replacingOccurrences(of: heimordner, with: "~") }
        t = t.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "/Users/…", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\d{5,}"#, with: "•••", options: .regularExpression)
        return t
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Version aus `Connector/manifest.json`, das der Build als Ressource mitnimmt.
    static var connectorVersion: String {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let daten = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let version = json["version"] as? String
        else { return String(localized: "unbekannt") }
        return version
    }
}

#if os(macOS)
/// Hilfe › „Problem melden …“: zeigt den Diagnosetext, kopiert ihn und sagt, was der Tester damit macht.
struct ProblemMeldenBlatt: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(\.dismiss) private var dismiss
    @State private var kopiert = false

    var body: some View {
        let text = diagnose
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text("Problem melden")
                .font(Schrift.titel)
                .foregroundStyle(thema.text)
            Text("Kopiere diesen Text und schick ihn mit einer kurzen Beschreibung an Tim: was du getan hast, was passiert ist und was du erwartet hast. Den Weg dafür nennt dir Tim.")
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.textSchwach)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(thema.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Abstand.kachelInnen)
            }
            .frame(minHeight: 140, maxHeight: 240)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
            Text("Enthalten: Versionen, System, Zahl der Konten und Importfehler dieser Sitzung. Nicht enthalten: Trades, Beträge, Namen, volle Konto- oder Ticketnummern. Hängt es an einer Datei, hilft zusätzlich die anonymisierte Probe aus dem Import-Blatt.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if kopiert {
                    Label("In der Zwischenablage", systemImage: "checkmark")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.gewinn)
                }
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Text kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    kopiert = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Abstand.seitenrand)
        .frame(minWidth: 520, idealWidth: 580)
    }

    private var diagnose: String {
        let fehler = Fehlerprotokoll.eintraege
            + Importordner.geteilt.rueckfragen.map { (zeit: Date(), text: "Import-Ordner: \($0.grund)") }
        return Diagnose.text(Diagnose.Angaben(
            app: Diagnose.appVersion,
            kern: TradingCore.version,
            connector: Diagnose.connectorVersion,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            konten: modell.konten.count,
            importordnerAktiv: Importordner.geteilt.aktiv,
            fehler: fehler))
    }
}
#endif
