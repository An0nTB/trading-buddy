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
    /// Befund aus dem Inhalt der Statusdatei (`nil`, wenn sie fehlt) und ob die Exportdatei im Ordner liegt: Fehlt die
    /// Statusdatei neben einem Export, gilt die Erweiterung als veraltet oder fehlend (Erweiterung 0.18.1 schreibt keine);
    /// ohne Export ist noch nichts eingerichtet, eine unlesbare Statusdatei meldet nichts.
    static func befund(statusdaten: Data?, exportVorhanden: Bool) -> Erweiterungsbefund? {
        guard let statusdaten else { return exportVorhanden ? .fehlt : nil }
        return (try? Erweiterungsstand.lese(statusdaten)).map(Erweiterungsbefund.gemeldet)
    }

    #if os(macOS)
    /// Befund aus dem gemerkten Export-Ordner, mit dessen Zugriffsrecht aus der Sandbox; `nil` ohne Ordner.
    static func ausExportOrdner() -> Erweiterungsbefund? {
        guard let ordner = ExportOrdner.gemerkterOrdner() else { return nil }
        let zugriff = ordner.startAccessingSecurityScopedResource()
        defer { if zugriff { ordner.stopAccessingSecurityScopedResource() } }
        let export = ordner.appendingPathComponent(JournalExport.dateiname)
        return befund(statusdaten: try? Data(contentsOf: ordner.appendingPathComponent(Erweiterungsstand.dateiname)),
                      exportVorhanden: FileManager.default.fileExists(atPath: export.path))
    }

    /// Die Erweiterung, die der App beiliegt (`Contents/Resources/Henry-Connector.mcpb`, gelegt von
    /// `scripts/app_verpacken.sh`); in Xcode-Bauten fehlt sie.
    static var beiliegendeErweiterung: URL? {
        Bundle.main.url(forResource: "Henry-Connector", withExtension: "mcpb")
    }
    #endif
}

/// Was die App über die Erweiterung weiß (E9).
enum Erweiterungsbefund: Equatable {
    /// Die Statusdatei liegt vor.
    case gemeldet(Erweiterungsstand)
    /// Export vorhanden, Statusdatei fehlt: Erweiterung älter als 0.20.0, nicht installiert oder nie aufgerufen.
    case fehlt

    /// Hinweis beim Start: anderer Rechenkern oder keine Meldung.
    var verdientHinweis: Bool {
        switch self {
        case .gemeldet(let stand): !stand.passtZurApp
        case .fehlt: true
        }
    }

    /// Je Paar aus Erweiterung und App einmal; fehlt die Meldung, einmal je Rechenkern der App.
    var meldeschluessel: String {
        switch self {
        case .gemeldet(let stand): stand.meldeschluessel
        case .fehlt: "fehlt|\(TradingCore.version)"
        }
    }

    var titel: String {
        switch self {
        case .gemeldet: String(localized: "Erweiterung passt nicht zur App")
        case .fehlt: String(localized: "Erweiterung hat sich nicht gemeldet")
        }
    }

    var hinweistext: String {
        switch self {
        case .gemeldet(let stand): stand.hinweistext
        case .fehlt:
            String(localized: "Die Erweiterung „Henry“ in Claude Desktop hat sich noch nicht gemeldet. Sie ist älter als 0.20.0, nicht installiert oder wurde noch nicht benutzt. Installiere in Claude Desktop unter Einstellungen › Erweiterungen die Datei „Henry-Connector“, die zu dieser App gehört.")
        }
    }
}

extension Erweiterungsstand {
    /// Schlüssel für „schon gemeldet“: Ein Paar aus Erweiterung und App meldet die App nur einmal.
    var meldeschluessel: String { "\(erweiterung)|\(rechenkern)|\(TradingCore.version)" }

    var hinweistext: String {
        String(localized: "Die Erweiterung „Henry“ in Claude Desktop (\(erweiterung)) rechnet mit Rechenkern \(rechenkern), die App mit \(TradingCore.version). Zahlen in Claude können von der App abweichen. Ersetze die Erweiterung in Claude Desktop unter Einstellungen › Erweiterungen durch die Datei „Henry-Connector“, die zu dieser App gehört.")
    }
}

extension View {
    /// Hinweis beim Start, wenn die Erweiterung einen anderen Rechenkern meldet oder sich neben einem Export nicht
    /// meldet (E9); je Paar beziehungsweise je Rechenkern der App einmal.
    func erweiterungsHinweis() -> some View {
        modifier(ErweiterungsHinweis())
    }
}

struct ErweiterungsHinweis: ViewModifier {
    #if os(macOS)
    static let gemeldetSchluessel = "erweiterungsHinweisGemeldet"
    @State private var befund: Erweiterungsbefund?

    func body(content: Content) -> some View {
        content
            .task {
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                      let gelesen = Erweiterungsstatus.ausExportOrdner(), gelesen.verdientHinweis,
                      UserDefaults.standard.string(forKey: Self.gemeldetSchluessel) != gelesen.meldeschluessel
                else { return }
                befund = gelesen
            }
            .alert(Text(verbatim: befund?.titel ?? ""), isPresented: sichtbar, presenting: befund) { b in
                if let datei = Erweiterungsstatus.beiliegendeErweiterung {
                    Button("Erweiterung öffnen") {
                        NSWorkspace.shared.open(datei)
                        gemeldet(b)
                    }
                }
                Button("Später", role: .cancel) { gemeldet(b) }
            } message: { b in
                Text(verbatim: b.hinweistext)
            }
    }

    private var sichtbar: Binding<Bool> {
        Binding(get: { befund != nil }, set: { if !$0, let befund { gemeldet(befund) } })
    }

    private func gemeldet(_ b: Erweiterungsbefund) {
        UserDefaults.standard.set(b.meldeschluessel, forKey: Self.gemeldetSchluessel)
        befund = nil
    }
    #else
    func body(content: Content) -> some View { content }
    #endif
}

#if os(macOS)
/// Zeile im Reiter Claude der Einstellungen: Stand der Erweiterung laut Statusdatei, mit Knopf zur beiliegenden Datei.
/// Abweichender Rechenkern oder fehlende Meldung neben einem Export stehen in der Warnfarbe.
struct ErweiterungsstatusZeile: View {
    @Environment(\.thema) private var thema
    @State private var befund: Erweiterungsbefund?
    @State private var gelesen = false

    var body: some View {
        LabeledContent("Erweiterung") {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: zeile)
                    .foregroundStyle(befund?.verdientHinweis == true ? thema.warnung : thema.textSchwach)
                if let datei = Erweiterungsstatus.beiliegendeErweiterung {
                    Button("Erweiterung öffnen") { NSWorkspace.shared.open(datei) }
                }
            }
        }
        .task {
            befund = Erweiterungsstatus.ausExportOrdner()
            gelesen = true
        }
    }

    private var zeile: String {
        guard gelesen else { return "" }
        switch befund {
        case nil:
            return String(localized: "Die Erweiterung hat sich noch nicht gemeldet: älter als 0.20.0 oder noch nicht benutzt.")
        case .gemeldet(let status) where status.passtZurApp:
            return String(localized: "Version \(status.erweiterung), Rechenkern \(status.rechenkern) wie die App.")
        case let befund?:
            return befund.hinweistext
        }
    }
}
#endif
