import SwiftUI

@main
struct TradingBuddyApp: App {
    @State private var modell = AppModell()

    var body: some Scene {
        WindowGroup {
            MitThema { Hauptfenster() }
                .environment(modell)
        }
        #if os(macOS)
        Settings {
            MitThema { EinstellungenView() }
                .environment(modell)
        }
        #endif
    }
}

/// Setzt Erscheinungsbild und Farbwelt aus den Einstellungen für alles darunter.
struct MitThema<Inhalt: View>: View {
    @AppStorage("farbwelt") private var farbwelt = Farbwelt.nordlicht
    @AppStorage("erscheinungsbild") private var erscheinungsbild = Erscheinungsbild.system
    @Environment(\.colorScheme) private var modus
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        let thema = farbwelt.thema(modus)
        inhalt()
            .environment(\.thema, thema)
            .tint(thema.akzent)
            .preferredColorScheme(erscheinungsbild.farbschema)
    }
}
