import Foundation
import SwiftUI
import TradingCore
#if os(macOS)
import AppKit
#endif

/// Stand der Erweiterung „Henry“ in Claude Desktop (E9, Tim 17.10.2026): Die Erweiterung schreibt bei jedem Start eine
/// kleine Statusdatei in den Export-Ordner (AP12), die App vergleicht deren Rechenkern mit dem eigenen. Weichen beide
/// ab, rechnet Claude mit anderen Regeln als die App (Befund H1: Erweiterung 0.18.1, App 0.26.1).
struct Erweiterungsstatus: Decodable, Equatable {
    /// Version der Erweiterung laut ihrem Manifest.
    var connector: String
    /// `TradingCore.version` der Erweiterung.
    var rechenkern: String
    /// Wann die Erweiterung die Datei zuletzt geschrieben hat.
    var stand: Date?

    static let dateiname = "connector_status.json"

    /// Rechnen App und Erweiterung mit demselben Kern?
    var passt: Bool { rechenkern == TradingCore.version }

    /// Liest die Statusdatei; `nil`, wenn sie fehlt (Erweiterung noch nie gestartet) oder unlesbar ist.
    static func lies(_ daten: Data) -> Erweiterungsstatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Erweiterungsstatus.self, from: daten)
    }

    #if os(macOS)
    /// Statusdatei aus dem gemerkten Export-Ordner, mit dessen Zugriffsrecht aus der Sandbox.
    static func ausExportOrdner() -> Erweiterungsstatus? {
        guard let ordner = ExportOrdner.gemerkterOrdner() else { return nil }
        let zugriff = ordner.startAccessingSecurityScopedResource()
        defer { if zugriff { ordner.stopAccessingSecurityScopedResource() } }
        guard let daten = try? Data(contentsOf: ordner.appendingPathComponent(dateiname)) else { return nil }
        return lies(daten)
    }

    /// Die Erweiterung, die der App beiliegt (`Contents/Resources`), falls das Paket sie enthält.
    static var beiliegendeErweiterung: URL? {
        Bundle.main.url(forResource: "Henry-Connector", withExtension: "mcpb")
    }
    #endif

    /// Schlüssel für „schon gemeldet“: Ein Paar aus Erweiterung und App meldet die App nur einmal.
    var meldeschluessel: String { "\(connector)|\(rechenkern)|\(TradingCore.version)" }

    var hinweistext: String {
        String(localized: "Die Erweiterung „Henry“ in Claude Desktop (\(connector)) rechnet mit Rechenkern \(rechenkern), die App mit \(TradingCore.version). Zahlen in Claude können von der App abweichen. Ersetze die Erweiterung in Claude Desktop unter Einstellungen › Erweiterungen durch die Datei „Henry-Connector“, die zu dieser App gehört.")
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
    @State private var status: Erweiterungsstatus?

    func body(content: Content) -> some View {
        content
            .task {
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                      let gelesen = Erweiterungsstatus.ausExportOrdner(), !gelesen.passt,
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

    private func gemeldet(_ s: Erweiterungsstatus) {
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
    @State private var status: Erweiterungsstatus?
    @State private var gelesen = false

    var body: some View {
        LabeledContent("Erweiterung") {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: zeile)
                    .foregroundStyle(status.map { $0.passt ? thema.textSchwach : thema.warnung } ?? thema.textSchwach)
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
            return String(localized: "Noch keine Meldung der Erweiterung. Sie schreibt ihren Stand in den Export-Ordner, sobald Claude Desktop sie startet.")
        }
        if status.passt {
            return String(localized: "Version \(status.connector), Rechenkern \(status.rechenkern) wie die App.")
        }
        return status.hinweistext
    }
}
#endif
