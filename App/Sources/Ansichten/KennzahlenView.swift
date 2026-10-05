import SwiftUI
import TradingCore

/// Seite „Auswertung“, vorher „Kennzahlen“ (Doc 10, Reihe 4; Tim 05.10.2026, Doc 02 Nr. 65): Reiter Überblick, Zeit,
/// Setups, Verhalten und Risiko (Karten in App/Sources/Auswertung/). Klick auf Zelle, Balken oder Kuchenstück zeigt
/// die Trades dahinter (Drill-down). Der Name des Typs bleibt, damit Hauptfenster und Fenster unverändert bauen.
struct KennzahlenView: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var reiter = Auswertungsreiter.ueberblick
    @State private var auswahl: Drilldown?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                Kopfzeile("Auswertung") {
                    MonatsberichtMenue() // F11 Monatsbericht als PDF
                        .labelStyle(.iconOnly)
                        .fixedSize()
                    Filterleiste()
                    FragBradKnopf(.monat) // Frag Brad (Doc 31)
                }
                if modell.alleTrades.isEmpty {
                    KeineTrades()
                } else if modell.trades.isEmpty {
                    KeineTreffer { modell.zeitraum = .alle; modell.instrument = nil } // Doc 55 J9
                } else {
                    Picker("Reiter", selection: $reiter) {
                        ForEach(Auswertungsreiter.allCases) { Text(verbatim: $0.titel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    HStack(spacing: Abstand.raster * 2) {
                        Kapsel(text: String(localized: "\(modell.kennzahlen.anzahl) Trades"), betont: true)
                        StichprobenHinweis(anzahl: modell.kennzahlen.anzahl)
                        MischwaehrungHinweis() // Umrechnung und fehlende Kurse (Doc 40 W3)
                    }
                    reiterInhalt
                }
                Pflichthinweis()
            }
            .padding(Abstand.seitenrand)
        }
        .sheet(item: $auswahl) { DrilldownBlatt(auswahl: $0) }
    }

    @ViewBuilder
    private var reiterInhalt: some View {
        let waehle: (Drilldown) -> Void = { auswahl = $0 }
        switch reiter {
        case .ueberblick:
            UeberblickReiter(waehle: waehle)
        case .zeit:
            ZeitReiter(waehle: waehle)
        case .setups:
            SetupsReiter(waehle: waehle)
        case .verhalten:
            VerhaltenReiter(waehle: waehle)
        case .risiko:
            RisikoReiter(waehle: waehle)
        }
    }
}

/// Reiter „Überblick“: die bisherigen acht Kacheln, Kacheln in R, Score als Netzdiagramm, Anteile als Donut und
/// die Aufschlüsselung mit Umschalter.
struct UeberblickReiter: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            kacheln
            RKacheln()
            ScoreNetzKarte()
            UeberblickDonuts(waehle: waehle)
            AufschluesselungKarte()
        }
    }

    private var kacheln: some View {
        let kennzahlen = modell.kennzahlen
        let verlauf = modell.kapitalverlauf
        let waehrung = modell.summenwaehrung
        // Regelverstöße wie in Disziplin und Monatsbericht, nicht Fehlermuster (Codex-Review B1). Gezählt über alle
        // gefilterten Trades, auch ohne EZB-Kurs; die Beträge nur, wo es einen Kurs gibt.
        let verletzt = modell.verletzteTrades
        let anzahlRegelbruch = modell.trades.filter { verletzt.contains($0.id) }.count
        let mitRegelbruch = modell.angeglicheneTrades.filter { verletzt.contains($0.id) }
        let ohneRegelbruch = modell.angeglicheneTrades.filter { !verletzt.contains($0.id) }
        return LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Netto",
                   wert: Format.geld(kennzahlen.netto, waehrung),
                   zusatz: String(localized: "Brutto \(Format.geld(kennzahlen.brutto, waehrung)) · Kosten \(Format.betrag(kennzahlen.kosten, waehrung)) (\(Format.prozent(kennzahlen.kostenquote)))"),
                   farbe: thema.vorzeichen(kennzahlen.netto))
            Kachel(titel: "Trefferquote",
                   wert: Format.prozent(kennzahlen.trefferquote),
                   zusatz: String(localized: "\(kennzahlen.gewinner) Gewinner, \(kennzahlen.verlierer) Verlierer, \(kennzahlen.breakeven) null"))
            Kachel(titel: "Profitfaktor",
                   wert: Format.zahl(kennzahlen.profitfaktor),
                   zusatz: String(localized: "Ø Gewinn zu Ø Verlust \(Format.zahl(kennzahlen.payoff)) · \(Format.geld(kennzahlen.durchschnittGewinn ?? 0, waehrung)) / \(Format.geld(kennzahlen.durchschnittVerlust ?? 0, waehrung))"),
                   hilfe: Kennzahlhilfe.profitfaktorUndVerhaeltnis)
            Kachel(titel: "Erwartung je Trade",
                   wert: Format.geld(kennzahlen.erwartungswert ?? 0, waehrung),
                   zusatz: String(localized: "\(Format.r(kennzahlen.erwartungswertR)) · bei \(kennzahlen.anzahlMitR) Trades mit Stop"),
                   farbe: thema.vorzeichen(kennzahlen.erwartungswert ?? 0),
                   hilfe: Kennzahlhilfe.erwartung)
            Kachel(titel: "Max. Drawdown",
                   wert: Format.geld(-verlauf.maxDrawdown, waehrung),
                   zusatz: drawdownZusatz(verlauf),
                   farbe: verlauf.maxDrawdown > 0 ? thema.verlust : nil,
                   hilfe: Kennzahlhilfe.drawdown)
            Kachel(titel: "Längste Verlustserie",
                   wert: "\(verlauf.laengsteVerlustserie)",
                   zusatz: String(localized: "Gewinnserie \(verlauf.laengsteGewinnserie)"))
            Kachel(titel: "Ohne Regelbrüche",
                   wert: Format.geld(netto(ohneRegelbruch), waehrung),
                   zusatz: String(localized: "\(anzahlRegelbruch) Trades mit Regelbruch: \(Format.geld(netto(mitRegelbruch), waehrung))"),
                   farbe: thema.vorzeichen(netto(ohneRegelbruch)))
            Kachel(titel: "Stop fehlt",
                   wert: "\(modell.ohneStop)",
                   zusatz: String(localized: "ohne Stop kein R"))
        }
    }

    private func netto(_ trades: [Trade]) -> Decimal {
        trades.reduce(Decimal(0)) { $0 + $1.netProfit }
    }

    private func drawdownZusatz(_ verlauf: Kapitalverlauf) -> String {
        if let prozent = verlauf.maxDrawdownProzent {
            return Format.prozent(prozent)
        }
        return String(localized: "vom Hoch der Kurve; ohne Startkapital kein Prozentwert")
    }
}
