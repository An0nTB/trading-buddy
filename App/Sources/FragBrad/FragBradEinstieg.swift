import SwiftUI
import TradingAssistant
import TradingCore

/// Offene „Frag Henry“-Anfrage: mit welcher Vorlage das Blatt startet und welcher Trade gemeint ist.
struct FragBradAnfrage: Identifiable {
    let id = UUID()
    var vorlage: FragBradVorlage
    var trade: Trade?
    /// Handelstag von der Tagesseite.
    var tag: Date?
}

/// Gemeinsamer Zustand aller Einstiege (Menü, Rechtsklick auf einen Trade). Eigenes Objekt statt eines Felds im
/// AppModell, damit „Frag Henry“ ohne Eingriff in fremde Dateien auskommt; das Hauptfenster zeigt das Blatt.
@Observable @MainActor
final class FragBradZustand {
    static let shared = FragBradZustand()
    var anfrage: FragBradAnfrage?

    func frage(_ vorlage: FragBradVorlage = .monat, trade: Trade? = nil, tag: Date? = nil) {
        anfrage = FragBradAnfrage(vorlage: trade == nil ? vorlage : .trade, trade: trade, tag: tag)
    }
}

extension View {
    /// Einhängezeile im Hauptfenster (AP11): zeigt das Blatt „Frag Henry“, sobald ein Einstieg fragt.
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
        Button("Frag Henry zu diesem Trade …", systemImage: "bubble.left.and.text.bubble.right") {
            FragBradZustand.shared.frage(trade: trade)
        }
    }
}

/// Knopf „Frag Henry“ für Seitenköpfe (Kennzahlen, Fehlermuster, Tagesseite); startet mit passender Vorlage.
struct FragBradKnopf: View {
    let vorlage: FragBradVorlage
    var tag: Date?

    init(_ vorlage: FragBradVorlage, tag: Date? = nil) {
        self.vorlage = vorlage
        self.tag = tag
    }

    var body: some View {
        Button("Frag Henry", systemImage: "bubble.left.and.text.bubble.right") {
            FragBradZustand.shared.frage(vorlage, tag: tag)
        }
        .help("Frage zu dieser Seite in Claude Desktop vorbereiten")
    }
}

#if os(macOS)
/// App-Menü: „Frag Henry …“ mit Befehl-Umschalt-B, direkt unter „Über Henry“.
struct FragBradBefehle: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Frag Henry …") { FragBradZustand.shared.frage() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}
#endif
