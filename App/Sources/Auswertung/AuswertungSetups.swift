import SwiftUI
import TradingCore

/// Reiter „Setups“: Vergleich nach Setup und Wert, Anteile als Donut, Stärken und Schwächen, Playbook.
struct SetupsReiter: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            SetupVergleichKarte(waehle: waehle)
            SetupDonuts(waehle: waehle)
            StaerkenKarte(waehle: waehle)
            if !modell.playbook.isEmpty {
                PlaybookAuswertungKarte()
            }
        }
    }
}

/// Netto oder Ø R je Setup und je Wert (Symbol) als Balken.
struct SetupVergleichKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var mass = Balkenmass.netto

    var body: some View {
        let trades = modell.angeglicheneTrades
        let setups = Auswertungsquelle.setups(modell)
        let nachSetup = Auswertungsquelle.gruppen(trades, schluessel: { setups[$0.id] ?? Gruppenname.ohneSetup },
                                                  name: { Gruppenname.text($0, .setup) })
        let nachWert = Auswertungsquelle.gruppen(trades, schluessel: { $0.basiswert ?? $0.symbol }, name: { $0 })
        Karte("Setups und Basiswerte") {
            HStack {
                Spacer()
                MassWahl(mass: $mass)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                    teil(String(localized: "Setup"), nachSetup).frame(maxWidth: .infinity)
                    teil(String(localized: "Basiswert"), nachWert).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    teil(String(localized: "Setup"), nachSetup)
                    teil(String(localized: "Basiswert"), nachWert)
                }
            }
            Erklaerung(String(localized: "Setup aus dem Journal. Basiswert bei Hebelprodukten der Wert dahinter, sonst das Symbol. Unter \(Kennzahlen.mindestanzahl) Trades je Gruppe beschreibt die Zahl nur. Klick auf einen Balken zeigt die Trades."))
        }
    }

    private func teil(_ titel: String, _ werte: [Balkenwert]) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            ErgebnisBalken(werte: Array(werte.prefix(12)), mass: mass, waehle: waehle)
            if werte.count > 12 {
                Erklaerung(String(localized: "Die zwölf Gruppen mit dem höchsten Netto; \(werte.count - 12) weitere ohne Balken."))
            }
        }
    }
}

/// Anteile der Setups und Werte an der Zahl der Trades, je Top 5 plus Rest.
struct SetupDonuts: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell

    var body: some View {
        let trades = modell.angeglicheneTrades
        let setups = Tiefenanalyse.anteileSetups(trades, setups: Auswertungsquelle.setups(modell))
        let werte = Tiefenanalyse.anteileSymbole(trades)
        Karte("Wie oft") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand * 2) {
                    donut(String(localized: "Setups"), setups).frame(maxWidth: .infinity)
                    donut(String(localized: "Werte"), werte).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    donut(String(localized: "Setups"), setups)
                    donut(String(localized: "Werte"), werte)
                }
            }
        }
    }

    private func donut(_ titel: String, _ anteile: [Tiefenanalyse.Anteil]) -> some View {
        AnteilDonut(titel: titel, anteile: anteile, wertText: { "\(Format.zahl($0.wert, stellen: 0))" }, waehle: waehle)
    }
}

/// Die stärksten und schwächsten Gruppen über Wochentag, Stunde, Haltedauer, Wert, Setup und Monat (Kern #270).
struct StaerkenKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let ergebnis = Tiefenanalyse.staerkenUndSchwaechen(modell.angeglicheneTrades, zeitzone: modell.zeitzone,
                                                           setups: Auswertungsquelle.setups(modell))
        Karte("Stärken und Schwächen") {
            if ergebnis.staerkste.isEmpty && ergebnis.schwaechste.isEmpty {
                Erklaerung(String(localized: "Noch keine Gruppe mit mindestens \(ergebnis.mindestanzahl) Trades."))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                        liste(String(localized: "Läuft gut"), ergebnis.staerkste).frame(maxWidth: .infinity, alignment: .leading)
                        liste(String(localized: "Läuft schlecht"), ergebnis.schwaechste).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                        liste(String(localized: "Läuft gut"), ergebnis.staerkste)
                        liste(String(localized: "Läuft schlecht"), ergebnis.schwaechste)
                    }
                }
            }
            Erklaerung(String(localized: "Gruppen ab \(ergebnis.mindestanzahl) Trades, nach Netto. Ein Trade steht in mehreren Gruppen, etwa in seinem Wochentag und in seinem Setup."))
        }
    }

    private func liste(_ titel: String, _ befunde: [Tiefenanalyse.Gruppenbefund]) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            Text(verbatim: titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            if befunde.isEmpty {
                Erklaerung(String(localized: "keine"))
            }
            ForEach(Array(befunde.enumerated()), id: \.offset) { eintrag in
                let befund = eintrag.element
                Button {
                    waehle(Drilldown(titel: Auswertungsquelle.gruppenName(befund), tradeIDs: befund.tradeIDs))
                } label: {
                    HStack(spacing: Abstand.raster * 2) {
                        Text(verbatim: Auswertungsquelle.gruppenName(befund))
                            .foregroundStyle(thema.text)
                        Spacer()
                        Text(verbatim: "\(befund.anzahl)")
                            .font(Schrift.tabelle)
                            .foregroundStyle(thema.textSchwach)
                        Text(verbatim: Format.r(befund.durchschnittR))
                            .font(Schrift.tabelle)
                            .foregroundStyle(befund.durchschnittR.map(thema.vorzeichen) ?? thema.textSchwach)
                        Text(verbatim: Format.geld(befund.netto, modell.summenwaehrung))
                            .font(Schrift.tabelle)
                            .foregroundStyle(thema.vorzeichen(befund.netto))
                    }
                    .font(Schrift.beschriftung)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
