import SwiftUI
import TradingAssistant
import TradingCore

/// Offene „Frag Brad“-Anfrage: mit welcher Vorlage das Blatt startet und welcher Trade gemeint ist.
struct FragBradAnfrage: Identifiable {
    let id = UUID()
    var vorlage: FragBradVorlage
    var trade: Trade?
}

/// Gemeinsamer Zustand aller Einstiege (Menü, Rechtsklick auf einen Trade). Eigenes Objekt statt eines Felds im
/// AppModell, damit „Frag Brad“ ohne Eingriff in fremde Dateien auskommt; das Hauptfenster zeigt das Blatt.
@Observable @MainActor
final class FragBradZustand {
    static let shared = FragBradZustand()
    var anfrage: FragBradAnfrage?

    func frage(_ vorlage: FragBradVorlage = .monat, trade: Trade? = nil) {
        anfrage = FragBradAnfrage(vorlage: trade == nil ? vorlage : .trade, trade: trade)
    }
}

extension View {
    /// Einhängezeile im Hauptfenster (AP11): zeigt das Blatt „Frag Brad“, sobald ein Einstieg fragt.
    func fragBradBlatt() -> some View {
        modifier(FragBradBlattZeigen())
    }
}

struct FragBradBlattZeigen: ViewModifier {
    @State private var zustand = FragBradZustand.shared

    func body(content: Content) -> some View {
        content.sheet(item: $zustand.anfrage) { anfrage in
            FragBradBlatt(anfrage: anfrage)
        }
    }
}

/// Eintrag fürs Kontextmenü einer Trade-Zeile (AP11 hängt ihn in TradesView ein).
struct FragBradMenuePunkt: View {
    let trade: Trade

    var body: some View {
        Button("Frag Brad zu diesem Trade …", systemImage: "bubble.left.and.text.bubble.right") {
            FragBradZustand.shared.frage(trade: trade)
        }
    }
}

#if os(macOS)
/// Menü „Brad“ (App-Menü): „Frag Brad …“ mit Befehl-Umschalt-B, direkt unter „Über Brad“.
struct FragBradBefehle: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Frag Brad …") { FragBradZustand.shared.frage() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}
#endif
