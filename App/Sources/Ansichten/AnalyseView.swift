import SwiftUI
import TradingAssistant
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
        let mitKurs = Set(modell.kurse.verlaeufe.verlaeufe.keys)
        let werte = AnalyseWerte.sortiert(symbole, mitKurs: mitKurs)
        let aktuell = symbol.flatMap { werte.contains($0) ? $0 : nil } ?? werte.first
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Analyse", untertitel: aktuell.map { untertitel($0, mitKurs: mitKurs) })
                if let aktuell {
                    wertKarte(aktuell, werte: werte, mitKurs: mitKurs)
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
        // Wie im Kurschart: Tageskerzen für Werte mit freier Quelle holen, damit die Kennzeichnung stimmt.
        .task(id: symbole) { await modell.kurse.ladeVerlaeufe(fuer: symbole) }
    }

    /// Werte ohne Kursverlauf sagen es schon im Kopf (Tim 05.10.2026, de40.c ohne Kurse).
    private func untertitel(_ wert: String, mitKurs: Set<String>) -> String {
        mitKurs.contains(wert) ? wert : "\(wert) · \(String(localized: "Ohne Kurse: nur Nachrichten und eigene Trades"))"
    }

    private func wertKarte(_ aktuell: String, werte: [String], mitKurs: Set<String>) -> some View {
        Karte("Wert") {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Auswahlknopf("Wert", anzeige: aktuell, auswahl: Binding(get: { aktuell }, set: { symbol = $0 })) {
                    ForEach(werte, id: \.self) { wert in
                        if mitKurs.contains(wert) {
                            Text(verbatim: wert).tag(wert)
                        } else {
                            Text("\(wert) (ohne Kurse)").tag(wert)
                        }
                    }
                }
                Text("Bereitet eine Frage zu diesem Wert für Claude vor. Gesendet wird erst in Claude.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !mitKurs.contains(aktuell) {
                    // Vor dem Absprung sagen, was die Analyse ohne Kurse leisten kann (Tim 05.10.2026)
                    Text(verbatim: FragBrad.ohneKursverlaufHinweis.uebersetzt)
                        .font(.callout)
                }
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

    /// Werte mit Kursverlauf zuerst, innerhalb beider Gruppen alphabetisch.
    static func sortiert(_ werte: [String], mitKurs: Set<String>) -> [String] {
        werte.filter { mitKurs.contains($0) } + werte.filter { !mitKurs.contains($0) }
    }
}
