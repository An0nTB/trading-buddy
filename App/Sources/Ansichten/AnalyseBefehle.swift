import SwiftUI
import TradingAssistant
import TradingCore

/// Menü „Analyse“ (Doc 38, Paket A5): Wertpapier- und Kursanalyse über Frag Henry mit der Vorlage „Wert analysieren“
/// (A4, Frag-Henry-Thread) im Inkognito-Chat, damit nichts in Claudes Erinnerungen landet (Tim 02.10.2026 12:02 UTC).
/// AP11 hängt nur Menü, Rechtsklick und den täglichen Kursverlauf-Abruf (`AppModell.ladeKursverlaeufe`) ein; das Blatt
/// wählt ohne Angabe das Instrument aus dem Filter, zeigt den Inkognito-Hinweis und nennt fehlende Kursverläufe selbst.
#if os(macOS)
struct AnalyseBefehle: Commands {
    @FocusedValue(\.fragBrad) private var zustand

    var body: some Commands {
        CommandMenu("Analyse") {
            Button("Wert analysieren …") { zustand?.frage(.analyse) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(zustand == nil)
        }
    }
}
#endif

/// Eintrag fürs Kontextmenü einer Trade-Zeile: Analyse des Symbols dieses Trades.
/// Fehlt das Blatt im Fenster (Einhängezeile noch nicht gesetzt), ist der Eintrag abgeschaltet statt wirkungslos.
struct AnalyseMenuePunkt: View {
    let trade: Trade
    @Environment(FragBradZustand.self) private var zustand: FragBradZustand?

    var body: some View {
        Button("Wert analysieren …", systemImage: "chart.xyaxis.line") {
            zustand?.frage(.analyse, trade: trade)
        }
        .disabled(zustand == nil)
    }
}
