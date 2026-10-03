import SwiftUI

/// Blätter aus dem Hilfe-Menü (Nachtpaket AP11, Beta-Weg): „Erste Schritte“ und „Problem melden“.
enum HilfeBlatt: String, Identifiable {
    case erststart, problem
    var id: String { rawValue }
}

/// Zustand je Fenster, wie bei „Frag Henry“: das Menü erreicht das vorderste Fenster über den Fokus.
@Observable @MainActor
final class HilfeZustand {
    var blatt: HilfeBlatt?
}

extension FocusedValues {
    @Entry var hilfe: HilfeZustand?
}

extension View {
    /// Einhängezeile an der Wurzel des Hauptfensters: zeigt die Hilfe-Blätter und beim Start „Erste Schritte“,
    /// solange kein Konto existiert und der Haken „Nicht mehr zeigen“ fehlt.
    func hilfeBlaetter() -> some View {
        modifier(HilfeBlaetterZeigen())
    }
}

struct HilfeBlaetterZeigen: ViewModifier {
    /// Schlüssel für den Haken „Nicht mehr zeigen“ im Blatt „Erste Schritte“.
    static let ausgeblendetSchluessel = "erststart.ausgeblendet"

    @Environment(AppModell.self) private var modell
    @AppStorage(Self.ausgeblendetSchluessel) private var ausgeblendet = false
    @State private var zustand = HilfeZustand()

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusedSceneValue(\.hilfe, zustand)
            .sheet(item: $zustand.blatt) { blatt in
                switch blatt {
                case .erststart: ErststartBlatt()
                case .problem: ProblemMeldenBlatt()
                }
            }
            .task {
                if Self.zeigeBeimStart(ausgeblendet: ausgeblendet, kontoVorhanden: !modell.konten.isEmpty,
                                       imTest: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) {
                    zustand.blatt = .erststart
                }
            }
        #else
        content
        #endif
    }

    /// Beim ersten Start und solange kein Konto existiert; nie im App-Testlauf.
    static func zeigeBeimStart(ausgeblendet: Bool, kontoVorhanden: Bool, imTest: Bool) -> Bool {
        !ausgeblendet && !kontoVorhanden && !imTest
    }
}

#if os(macOS)
/// Menü „Hilfe“: ersetzt die leere Systemsuche durch „Erste Schritte …“ und „Problem melden …“.
struct HilfeBefehle: Commands {
    @FocusedValue(\.hilfe) private var zustand

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Erste Schritte …") { zustand?.blatt = .erststart }
                .disabled(zustand == nil)
            Button("Problem melden …") { zustand?.blatt = .problem }
                .disabled(zustand == nil)
        }
    }
}
#endif
