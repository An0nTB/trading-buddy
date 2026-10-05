import SwiftUI
import TradingCore
import TradingQuotes

/// Seite „Kurschart“ (Tim 02.10.2026 12:50 UTC, Vorschlag des Hauptthreads Punkt 1): Tageskerzen eines Werts mit
/// eigenen Ein- und Ausstiegen und den Meldungen der Nachrichtenseite auf der Zeitachse. Nur Krypto und US-Aktien,
/// weil es nur dafür freie Kurse gibt. Beschreibt den Verlauf, gibt keine Signale und keine Prognose (Doc 18).
struct KurschartView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @Environment(FragBradZustand.self) private var fragBrad: FragBradZustand?
    @State private var symbol: String?
    @State private var zeitraum = Chartzeitraum.quartal
    @State private var gewaehlterTag: Date?
    @State private var werteZeigen = false

    var body: some View {
        let kurse = modell.kurse
        let symbole = alleSymbole(kurse)
        let aktuell = symbol.flatMap { symbole.contains($0) ? $0 : nil } ?? symbole.first
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Kurschart", untertitel: aktuell) {
                    if !symbole.isEmpty {
                        Auswahlknopf("Wert", anzeige: aktuell ?? "", auswahl: Binding(
                            get: { aktuell ?? "" }, set: { symbol = $0; gewaehlterTag = nil })) {
                            ForEach(symbole, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                    }
                    // Analyse des gewählten Werts in Frag Henry, wie Menü Analyse › Wert analysieren (Tim 05.10.2026).
                    Button("Wert analysieren …", systemImage: "chart.xyaxis.line") {
                        fragBrad?.frage(.analyse, symbol: aktuell)
                    }
                    .disabled(fragBrad == nil || aktuell == nil)
                    Button("Wert hinzufügen", systemImage: "plus") { werteZeigen = true }
                }
                inhalt(aktuell, kurse: kurse, symbole: symbole)
            }
            .padding(Abstand.seitenrand)
        }
        .task(id: symbole) { await kurse.ladeVerlaeufe(fuer: symbole) }
        .sheet(isPresented: $werteZeigen) {
            ChartwerteBlatt { neu in
                symbol = neu
                gewaehlterTag = nil
            }
        }
    }

    /// Journal-Werte mit freiem Kurs, eigene Werte und Symbole der Merkliste mit freier Quelle.
    private func alleSymbole(_ kurse: Kursdienst) -> [String] {
        let journal = KurschartQuellen.symbole(modell.alleTrades, kurse: kurse)
        let merkbegriffe = modell.nachrichten.aktiveEintraege.filter { $0.art == .symbol }.map(\.begriff)
        let merkliste = merkbegriffe.isEmpty ? []
            : Chartwerteingabe.ausMerkliste(merkbegriffe, alpacaSchluessel: kurse.schluesselbund.vorhanden())
        return Chartwerteingabe.liste(journal: journal, eigene: kurse.chartwerte, merkliste: merkliste)
    }

    @ViewBuilder
    private func inhalt(_ aktuell: String?, kurse: Kursdienst, symbole: [String]) -> some View {
        if !kurse.aktiv {
            Platzhalter(titel: "Kurse sind aus", symbol: "chart.xyaxis.line",
                        text: "Der Kurschart lädt Tageskerzen nur, wenn die Kurse in den Einstellungen eingeschaltet sind.")
        } else if let aktuell, let verlauf = kurse.verlaeufe.verlaeufe[aktuell] {
            diagrammKarte(verlauf, kurse: kurse)
            nachrichtenKarte(verlauf, kurse: kurse)
        } else if let aktuell, let fehler = kurse.verlaeufe.fehler[aktuell] {
            Platzhalter(titel: "Kein Kursverlauf", symbol: "exclamationmark.triangle",
                        text: "Abruf für \(aktuell) fehlgeschlagen: \(fehler)")
        } else if aktuell != nil {
            ProgressView("Tageskerzen werden geladen")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(spacing: Abstand.kachelAbstand) {
                Platzhalter(titel: "Kein passender Wert", symbol: "chart.xyaxis.line",
                            text: "Im Journal steht kein Wert mit freiem Kurs. Füge Krypto wie BTC/EUR oder US-Aktien wie AAPL selbst hinzu; für CFDs und Devisen gibt es keine freien Kurse.")
                Button("Wert hinzufügen", systemImage: "plus") { werteZeigen = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var istBeispiel: Bool { modell.konto.map(Beispieldaten.istBeispiel) ?? false }

    private func chart(_ verlauf: Kursverlauf) -> Kurschart? {
        // Beispielkonto: erfundene Preise nicht als Ein- und Ausstiege auf echte Kerzen zeichnen (Doc 57, 04.10.2026).
        let marken = istBeispiel ? [] : KurschartQuellen.marken(modell.alleTrades, symbol: verlauf.journalSymbol)
        let zuordnung = Kurszuordnung(journalSymbol: verlauf.journalSymbol, quelle: verlauf.quelle,
                                      quellSymbol: verlauf.quellSymbol)
        let meldungen = modell.nachrichten.aktiv
            ? KurschartQuellen.meldungen(modell.nachrichten.meldungen, zuordnung: zuordnung) : []
        return Kurschart.baue(verlauf, zeitraum: zeitraum, marken: marken, meldungen: meldungen, jetzt: .now)
    }

    @ViewBuilder
    private func diagrammKarte(_ verlauf: Kursverlauf, kurse: Kursdienst) -> some View {
        Karte(verbatim: kurse.quellenname(verlauf.quelle) + " · " + (verlauf.waehrung ?? "")) {
            Picker("Zeitraum", selection: $zeitraum) {
                ForEach(Chartzeitraum.allCases) { Text(verbatim: KurschartFormat.titel($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let chart = chart(verlauf) {
                KurschartDiagramm(chart: chart, waehrung: modell.waehrung, gewaehlterTag: $gewaehlterTag)
                    .frame(minHeight: 280)
                hinweise(chart, verlauf: verlauf)
            } else {
                Text("Keine Kerzen in diesem Zeitraum.")
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    @ViewBuilder
    private func hinweise(_ chart: Kurschart, verlauf: Kursverlauf) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text("Dreieck: Einstieg, Kreis: Ausstieg, Kreuz: Ausstieg mit Verlust, Raute: Tag mit Meldungen. Tageskerzen, nur beschreibend.")
            if istBeispiel {
                Text("Beispieldaten: Die Beispiel-Trades haben erfundene Preise und erscheinen deshalb nicht im Chart.")
            }
            if let naeherung = verlauf.naeherung { Text(verbatim: naeherung.uebersetzt) }
            if chart.ausserhalb > 0 {
                Text("\(chart.ausserhalb) Ein- oder Ausstiege liegen weit außerhalb dieser Kurse (anderer Kurs des Brokers) und fehlen im Bild.")
            }
            if chart.laufend { Text("Die letzte Kerze ist der laufende Tag.") }
        }
        .font(Schrift.beschriftung)
        .foregroundStyle(thema.textSchwach)
    }

    @ViewBuilder
    private func nachrichtenKarte(_ verlauf: Kursverlauf, kurse: Kursdienst) -> some View {
        Karte("Meldungen") {
            if !modell.nachrichten.aktiv {
                Text("Die Nachrichten sind aus. Eingeschaltet erscheinen hier Meldungen der letzten 14 Tage zu diesem Wert.")
                    .foregroundStyle(thema.textSchwach)
            } else if let chart = chart(verlauf), !chart.nachrichtentage.isEmpty {
                KurschartMeldungen(tage: chart.nachrichtentage, gewaehlterTag: $gewaehlterTag)
            } else {
                Text("Keine Meldungen zu diesem Wert in den letzten 14 Tagen.")
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }
}
