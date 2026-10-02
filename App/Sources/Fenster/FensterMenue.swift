import SwiftUI

extension View {
    /// Rechtsklick (iPad: langes Drücken) auf eine Zeile der Seitenleiste: Bereich als eigenes Fenster öffnen.
    func inNeuemFenster(_ bereich: Bereich) -> some View {
        modifier(InNeuemFensterMenue(bereich: bereich))
    }

    /// Symbol in der Werkzeugleiste des Hauptfensters: die gerade gezeigte Seite als eigenes Fenster öffnen.
    func fensterSymbol(_ bereich: Bereich) -> some View {
        modifier(FensterSymbolLeiste(bereich: bereich))
    }
}

/// Kontextmenü „In neuem Fenster öffnen“; am iPhone (keine weiteren Fenster) bleibt es leer.
/// Menü und Werkzeugleiste hängen immer an, nur ihr Inhalt ist bedingt: eine bedingt angehängte Werkzeugleiste
/// baut die Fensterleiste bei jedem Durchlauf neu und kann eine Layout-Schleife auslösen (Startabsturz 02.10.2026).
struct InNeuemFensterMenue: ViewModifier {
    let bereich: Bereich
    @Environment(\.supportsMultipleWindows) private var mehrereFenster
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.contextMenu {
            if mehrereFenster, Bereich.abtrennbar.contains(bereich) {
                Button("In neuem Fenster öffnen", systemImage: "macwindow.badge.plus") {
                    openWindow(id: FensterID.bereich, value: bereich)
                }
                #if os(macOS)
                Button("In neuem Fenster, immer im Vordergrund", systemImage: "pin") {
                    UserDefaults.standard.set(true, forKey: bereich.anheftSchluessel)
                    openWindow(id: FensterID.bereich, value: bereich)
                }
                #endif
            }
        }
    }
}

/// Werkzeugleisten-Knopf für die gerade gezeigte Seite; Bereiche ohne eigenes Fenster zeigen ihn abgeschaltet.
struct FensterSymbolLeiste: ViewModifier {
    let bereich: Bereich
    @Environment(\.supportsMultipleWindows) private var mehrereFenster
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("In eigenem Fenster öffnen", systemImage: "macwindow.badge.plus") {
                    openWindow(id: FensterID.bereich, value: bereich)
                }
                .help("Diese Seite als eigenes Fenster öffnen, frei verschiebbar")
                .disabled(!mehrereFenster || !Bereich.abtrennbar.contains(bereich))
            }
        }
    }
}

#if os(macOS)
/// Menü „Fenster“: jeder Bereich als eigenes Fenster, die ersten neun mit Wahl-Befehl-Ziffer.
struct FensterBefehle: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Menu("Bereich in eigenem Fenster") {
                ForEach(Array(Bereich.abtrennbar.enumerated()), id: \.element) { eintrag in
                    knopf(eintrag.element, nummer: eintrag.offset + 1)
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private func knopf(_ bereich: Bereich, nummer: Int) -> some View {
        let button = Button(bereich.titel) { openWindow(id: FensterID.bereich, value: bereich) }
        if nummer <= 9, let ziffer = String(nummer).first {
            button.keyboardShortcut(KeyEquivalent(ziffer), modifiers: [.command, .option])
        } else {
            button
        }
    }
}
#endif
