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
    /// Wert für „Wert analysieren“ (Menü „Analyse“, AP11). Ohne Angabe nimmt das Blatt das Symbol des Trades
    /// oder das Instrument im Filter.
    var symbol: String?
}

/// Zustand der Einstiege eines Fensters (Menü, Rechtsklick, Knöpfe). Je Fenster ein eigenes Objekt, damit das Blatt
/// nur im Fenster aufgeht, in dem gefragt wurde (Gesamt-Gegencheck F1); kein Feld im AppModell, damit „Frag Henry“
/// ohne Eingriff in fremde Dateien auskommt.
@Observable @MainActor
final class FragBradZustand {
    var anfrage: FragBradAnfrage?

    /// Mit Trade startet das Blatt bei „Diesen Trade einordnen“, außer bei `.analyse` (Analyse des Trade-Symbols).
    func frage(_ vorlage: FragBradVorlage = .monat, trade: Trade? = nil, tag: Date? = nil, symbol: String? = nil) {
        let start = trade == nil || vorlage == .analyse ? vorlage : .trade
        anfrage = FragBradAnfrage(vorlage: start, trade: trade, tag: tag, symbol: symbol)
    }
}

extension View {
    /// Einhängezeile an der Wurzel jedes Fensters (Hauptfenster: AP11, eigene Fenster: Fenster-Thread): gibt den
    /// Einstiegen darunter ihren Zustand, dem Menü über den Fokus, und zeigt dort das Blatt „Frag Henry“.
    func fragBradBlatt() -> some View {
        modifier(FragBradBlattZeigen())
    }
}

struct FragBradBlattZeigen: ViewModifier {
    @State private var zustand = FragBradZustand()

    func body(content: Content) -> some View {
        content
            .environment(zustand)
            .focusedSceneValue(\.fragBrad, zustand)
            .sheet(item: $zustand.anfrage) { anfrage in
                FragBradBlatt(anfrage: anfrage)
            }
    }
}

extension FocusedValues {
    /// Zustand des vordersten Fensters, für den Menübefehl.
    @Entry var fragBrad: FragBradZustand?
}

/// Eintrag fürs Kontextmenü einer Trade-Zeile (AP11 hängt ihn in TradesView ein).
/// Fehlt das Blatt im Fenster (Einhängezeile noch nicht gesetzt), ist der Eintrag abgeschaltet statt wirkungslos.
struct FragBradMenuePunkt: View {
    let trade: Trade
    @Environment(FragBradZustand.self) private var zustand: FragBradZustand?

    var body: some View {
        Button("Frag Henry zu diesem Trade …", systemImage: "bubble.left.and.text.bubble.right") {
            zustand?.frage(trade: trade)
        }
        .disabled(zustand == nil)
    }
}

/// Knopf „Frag Henry“ für Seitenköpfe (Kennzahlen, Fehlermuster, Tagesseite); startet mit passender Vorlage.
struct FragBradKnopf: View {
    let vorlage: FragBradVorlage
    var tag: Date?
    @Environment(FragBradZustand.self) private var zustand: FragBradZustand?

    init(_ vorlage: FragBradVorlage, tag: Date? = nil) {
        self.vorlage = vorlage
        self.tag = tag
    }

    var body: some View {
        Button("Frag Henry", systemImage: "bubble.left.and.text.bubble.right") {
            zustand?.frage(vorlage, tag: tag)
        }
        .help("Frage zu dieser Seite in Claude Desktop vorbereiten")
        .disabled(zustand == nil)
    }
}

#if os(macOS)
/// App-Menü: „Frag Henry …“ mit Befehl-Umschalt-B, direkt unter „Über Henry“.
/// Wirkt im vordersten Fenster; ohne Fenster mit Blatt abgeschaltet.
struct FragBradBefehle: Commands {
    @FocusedValue(\.fragBrad) private var zustand

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Frag Henry …") { zustand?.frage() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(zustand == nil)
        }
    }
}
#endif
