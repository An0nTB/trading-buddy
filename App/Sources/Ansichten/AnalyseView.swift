import SwiftUI
import TradingCore
import TradingStore

/// Seite „Analyse“ unter Markt (Tim 05.10.2026): Wert wählen und „Wert analysieren“ in Frag Henry öffnen.
/// Dieselbe Frage wie Menü „Analyse“ und Kontextmenü (Doc 38); neue Werte kommen über den Kurschart.
struct AnalyseView: View {
    @Environment(AppModell.self) private var modell
    @Environment(FragBradZustand.self) private var zustand: FragBradZustand?
    @State private var symbol: String?

    var body: some View {
        let symbole = AnalyseWerte.liste(
            trades: modell.alleTrades.map(\.symbol),
            positionen: modell.offenePositionen.map(\.symbol),
            merkliste: modell.nachrichten.aktiveEintraege.filter { $0.art == .symbol }.map(\.begriff),
            chartwerte: modell.kurse.chartwerte)
        let aktuell = symbol.flatMap { symbole.contains($0) ? $0 : nil } ?? symbole.first
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Analyse", untertitel: aktuell)
                if let aktuell {
                    wertKarte(aktuell, symbole: symbole)
                } else {
                    Platzhalter(titel: "Noch kein Wert", symbol: Bereich.analyse.symbol,
                                text: "Werte kommen aus eigenen Trades, offenen Positionen, der Merkliste und dem Kurschart.")
                }
                HStack(spacing: Abstand.kachelAbstand) {
                    Text("Neue Werte unter Kurschart › Wert hinzufügen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Zum Kurschart") { modell.bereich = .kurschart }
                        .buttonStyle(.borderless)
                }
            }
            .padding(Abstand.seitenrand)
        }
    }

    private func wertKarte(_ aktuell: String, symbole: [String]) -> some View {
        Karte("Wert") {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Auswahlknopf("Wert", anzeige: aktuell, auswahl: Binding(get: { aktuell }, set: { symbol = $0 })) {
                    ForEach(symbole, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                Text("Bereitet eine Frage zu diesem Wert für Claude vor. Gesendet wird erst in Claude.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if istBeispiel {
                    // Gleiche Regel wie im Blatt Frag Henry (Doc 57, Doc 59 B2)
                    Text("Beispielkonto: keine Kursanalyse, weil die Beispiel-Trades erfundene Preise haben und nicht neben echte Kurse gehören.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Analysieren", systemImage: "bubble.left.and.text.bubble.right") {
                    zustand?.frage(.analyse, symbol: aktuell)
                }
                .disabled(zustand == nil || istBeispiel)
            }
        }
    }

    private var istBeispiel: Bool { modell.konto.map(Beispieldaten.istBeispiel) ?? false }
}

/// Wählbare Werte der Seite „Analyse“: eigene Trades, offene Positionen, Merkliste und Kurschart-Werte,
/// ohne Leerzeichen am Rand, ohne Doppel, alphabetisch.
enum AnalyseWerte {
    static func liste(trades: [String], positionen: [String], merkliste: [String], chartwerte: [String]) -> [String] {
        let alle = trades + positionen + merkliste + chartwerte
        let bereinigt = alle.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(bereinigt).sorted()
    }
}
