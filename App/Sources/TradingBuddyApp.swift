import SwiftUI

@main
struct TradingBuddyApp: App {
    @State private var modell = AppModell()

    var body: some Scene {
        WindowGroup(id: FensterID.haupt) {
            MitThema { Hauptfenster() }
                .environment(modell)
        }
        #if os(macOS)
        .commands { FensterBefehle() } // P12 Eigene Fenster
        #endif
        BereichFensterSzene(modell: modell) // P12 Eigene Fenster
        #if os(macOS)
        Settings {
            MitThema { EinstellungenView() }
                .environment(modell)
        }
        #endif
    }
}

/// Setzt Erscheinungsbild und Farbwelt aus den Einstellungen für alles darunter (Doc 10, E1).
struct MitThema<Inhalt: View>: View {
    @AppStorage("farbwelt") private var farbwelt = Farbwelt.nordlicht
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system
    @AppStorage("flaechenGetoent") private var flaechenGetoent = true
    @Environment(\.colorScheme) private var systemModus
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        // Ein erzwungenes Erscheinungsbild gilt auch für die Token, nicht nur für die Systemfarben.
        let thema = farbwelt.thema(erscheinungsbild.farbschema ?? systemModus, getoent: flaechenGetoent)
        inhalt()
            .environment(\.thema, thema)
            .tint(thema.akzent)
            .preferredColorScheme(erscheinungsbild.farbschema)
    }
}
