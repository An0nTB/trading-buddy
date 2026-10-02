import SwiftUI

@main
struct TradingBuddyApp: App {
    @State private var modell = AppModell()

    var body: some Scene {
        // Ohne Kennung, damit AppKit die gespeicherte Fenstergröße des Nutzers wiederfindet; mit Standardgröße,
        // damit ein neues Fenster nicht in Mindestgröße 900 x 600 startet (Startabsturz 02.10.2026, Layout-Schleife).
        WindowGroup {
            MitThema { Hauptfenster() }
                .environment(modell)
        }
        .defaultSize(width: 1200, height: 780)
        #if os(macOS)
        .commands {
            FensterBefehle() // P12 Eigene Fenster
            FragBradBefehle() // Frag Brad (Doc 31)
            AnalyseBefehle() // Menü „Analyse“ (Doc 38, Paket A5)
            // F11 Monatsbericht als PDF: Menü „Ablage“, unter „Sichern“
            CommandGroup(after: .saveItem) {
                MonatsberichtMenue()
                    .environment(modell)
            }
        }
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
