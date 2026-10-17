import Foundation
import SwiftUI
import TradingCore
#if os(macOS)
import AppKit
#endif

/// Stand der Erweiterung „Henry“ in Claude Desktop (E9, Tim 17.10.2026): Die Erweiterung schreibt ab 0.20.0 beim Start
/// und bei jedem Werkzeugaufruf `Erweiterungsstand` in den Export-Ordner (AP12), die App vergleicht deren Rechenkern
/// mit dem eigenen. Weichen beide ab, rechnet Claude mit anderen Regeln als die App (Befund H1: Erweiterung 0.18.1,
/// App 0.26.1).
enum Erweiterungsstatus {
    #if os(macOS)
    /// Statusdatei aus dem gemerkten Export-Ordner, mit dessen Zugriffsrecht aus der Sandbox; `nil`, wenn sie fehlt
    /// (Erweiterung älter als 0.20.0 oder nie aufgerufen) oder unlesbar ist.
    static func ausExportOrdner() -> Erweiterungsstand? {
        guard let ordner = ExportOrdner.gemerkterOrdner() else { return nil }
        let zugriff = ordner.startAccessingSecurityScopedResource()
        defer { if zugriff { ordner.stopAccessingSecurityScopedResource() } }
        guard let daten = try? Data(contentsOf: ordner.appendingPathComponent(Erweiterungsstand.dateiname)) else {
            return nil
        }
        return try? Erweiterungsstand.lese(daten)
    }

    /// Die Erweiterung, die der App beiliegt (`Contents/Resources/Henry-Connector.mcpb`, gelegt von
    /// `scripts/app_verpacken.sh`); in Xcode-Bauten fehlt sie.
    static var beiliegendeErweiterung: URL? {
        Bundle.main.url(forResource: "Henry-Connector", withExtension: "mcpb")
    }
    #endif
}

extension Erweiterungsstand {
    /// Schlüssel für „schon gemeldet“: Ein Paar aus Erweiterung und App meldet die App nur einmal.
    var meldeschluessel: String { "\(erweiterung)|\(rechenkern)|\(TradingCore.version)" }

    var hinweistext: String {
        String(localized: "Die Erweiterung „Henry“ in Claude Desktop (\(erweiterung)) rechnet mit Rechenkern \(rechenkern), die App mit \(TradingCore.version). Zahlen in Claude können von der App abweichen. Ersetze die Erweiterung in Claude Desktop unter Einstellungen › Erweiterungen durch die Datei „Henry-Connector“, die zu dieser App gehört.")
    }
}

extension View {
    /// Hinweis beim Start, wenn die Erweiterung einen anderen Rechenkern meldet (E9); je Paar einmal.
    func erweiterungsHinweis() -> some View {
        modifier(ErweiterungsHinweis())
    }
}

struct ErweiterungsHinweis: ViewModifier {
    #if os(macOS)
    static let gemeldetSchluessel = "erweiterungsHinweisGemeldet"
    @State private var status: Erweiterungsstand?

    func body(content: Content) -> some View {
        content
            .task {
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                      let gelesen = Erweiterungsstatus.ausExportOrdner(), !gelesen.passtZurApp,
                      UserDefaults.standard.string(forKey: Self.gemeldetSchluessel) != gelesen.meldeschluessel
                else { return }
                status = gelesen
            }
            .alert("Erweiterung passt nicht zur App", isPresented: sichtbar, presenting: status) { s in
                if let datei = Erweiterungsstatus.beiliegendeErweiterung {
                    Button("Erweiterung öffnen") {
                        NSWorkspace.shared.open(datei)
                        gemeldet(s)
                    }
                }
                Button("Später", role: .cancel) { gemeldet(s) }
            } message: { s in
                Text(verbatim: s.hinweistext)
            }
    }

    private var sichtbar: Binding<Bool> {
        Binding(get: { status != nil }, set: { if !$0, let status { gemeldet(status) } })
    }

    private func gemeldet(_ s: Erweiterungsstand) {
        UserDefaults.standard.set(s.meldeschluessel, forKey: Self.gemeldetSchluessel)
        status = nil
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

#if os(macOS)
/// Zeile im Reiter Claude der Einstellungen: Stand der Erweiterung laut Statusdatei, mit Knopf zur beiliegenden Datei.
struct ErweiterungsstatusZeile: View {
    @Environment(\.thema) private var thema
    @State private var status: Erweiterungsstand?
    @State private var gelesen = false

    var body: some View {
        LabeledContent("Erweiterung") {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: zeile)
                    .foregroundStyle(status.map { $0.passtZurApp ? thema.textSchwach : thema.warnung } ?? thema.textSchwach)
                if let datei = Erweiterungsstatus.beiliegendeErweiterung {
                    Button("Erweiterung öffnen") { NSWorkspace.shared.open(datei) }
                }
            }
        }
        .task {
            status = Erweiterungsstatus.ausExportOrdner()
            gelesen = true
        }
    }

    private var zeile: String {
        guard gelesen else { return "" }
        guard let status else {
            return String(localized: "Die Erweiterung hat sich noch nicht gemeldet: älter als 0.20.0 oder noch nicht benutzt.")
        }
        if status.passtZurApp {
            return String(localized: "Version \(status.erweiterung), Rechenkern \(status.rechenkern) wie die App.")
        }
        return status.hinweistext
    }
}
#endif
