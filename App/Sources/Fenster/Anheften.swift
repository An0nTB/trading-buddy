#if os(macOS)
import AppKit
import SwiftUI

/// Knopf „Immer im Vordergrund“ in der Werkzeugleiste eines abgetrennten Fensters; gemerkt je Bereich.
/// SwiftUI kennt die Fensterebene nur fest je Szene (`windowLevel`, macOS 15); für einen Schalter je Fenster
/// setzt `FensterEbene` die Ebene direkt am AppKit-Fenster (Stand-Doc 27, Abschnitt 3).
struct Stecknadel: View {
    @Binding var angeheftet: Bool

    var body: some View {
        Toggle(isOn: $angeheftet) {
            if angeheftet {
                Label("Nicht mehr im Vordergrund", systemImage: "pin.fill")
            } else {
                Label("Immer im Vordergrund", systemImage: "pin")
            }
        }
        .toggleStyle(.button)
        .help(angeheftet ? Text("Fenster wieder normal einordnen") : Text("Fenster bleibt über allen Programmen sichtbar"))
    }
}

/// Setzt Ebene und Verhalten des AppKit-Fensters, in dem die Ansicht liegt.
/// Angeheftet: über normalen Fenstern aller Programme, auf allen Schreibtischen und neben Programmen im Vollbild.
struct FensterEbene: NSViewRepresentable {
    let angeheftet: Bool

    func makeNSView(context: Context) -> Fuehler { Fuehler() }

    func updateNSView(_ fuehler: Fuehler, context: Context) {
        fuehler.angeheftet = angeheftet
    }

    final class Fuehler: NSView {
        var angeheftet = false {
            didSet { anwenden() }
        }
        /// Verhalten des Fensters vor dem ersten Anheften, zum Zurücksetzen.
        private var ursprung: NSWindow.CollectionBehavior?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            anwenden()
        }

        private func anwenden() {
            guard let window else { return }
            let vorher = ursprung ?? window.collectionBehavior
            ursprung = vorher
            if angeheftet {
                var verhalten = vorher
                // Gegenseitig ausschließende Werte zuerst entfernen (Vollbild-Gruppe, Schreibtisch-Gruppe).
                verhalten.subtract([.fullScreenPrimary, .fullScreenNone, .moveToActiveSpace])
                verhalten.formUnion([.fullScreenAuxiliary, .canJoinAllSpaces])
                window.collectionBehavior = verhalten
                window.level = .floating
            } else {
                window.collectionBehavior = vorher
                window.level = .normal
            }
        }
    }
}
#endif
