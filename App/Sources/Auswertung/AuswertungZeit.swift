import Charts
import SwiftUI
import TradingCore

/// Reiter „Zeit“: Heatmap Wochentag × Stunde, Wochentage und Stunden als Balken, Monate.
/// Tims Frage vom 05.10.2026: „welche tage zum beispiel oder welche uhrzeit gut und schlecht läuft“.
struct ZeitReiter: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @State private var mass = Balkenmass.netto

    var body: some View {
        let heatmap = Tiefenanalyse.heatmap(modell.angeglicheneTrades, zeitzone: modell.zeitzone)
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            HeatmapKarte(heatmap: heatmap, mass: $mass, waehle: waehle)
            ZeitBalkenKarte(heatmap: heatmap, mass: mass, waehle: waehle)
            MonateKarte(mass: mass, waehle: waehle)
        }
    }
}

/// Heatmap Wochentag × Stunde der Eröffnung. Zellen unter der Mindestanzahl grau mit „zu wenig Daten“;
/// darüber ein Satz zu den besten und schwächsten Zeitfenstern. Klick auf eine Zelle zeigt ihre Trades.
struct HeatmapKarte: View {
    let heatmap: Tiefenanalyse.Heatmap
    @Binding var mass: Balkenmass
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Wochentag und Uhrzeit") {
            HStack {
                Text(verbatim: satz())
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                MassWahl(mass: $mass)
            }
            if heatmap.zellen.isEmpty {
                Erklaerung(String(localized: "Keine Trades mit Uhrzeit im gewählten Zeitraum."))
            } else {
                raster
            }
            Erklaerung(String(localized: "Stunde der Eröffnung in deiner Zeitzone. Grün im Plus, rot im Minus, je kräftiger, desto größer. Grau: unter \(heatmap.mindestanzahl) Trades, zu wenig Daten. Die Zahl in der Zelle ist die Anzahl der Trades."))
            if heatmap.ohneUhrzeit > 0 {
                Erklaerung(String(localized: "\(heatmap.ohneUhrzeit) Trades ohne Uhrzeit fehlen hier."))
            }
        }
    }

    private var raster: some View {
        let stunden = stundenbereich()
        let tage = tagesbereich()
        let groesster = groessterBetrag()
        return ScrollView(.horizontal) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text(verbatim: "")
                    ForEach(stunden, id: \.self) { stunde in
                        Text(verbatim: "\(stunde)")
                            .font(.caption2)
                            .foregroundStyle(thema.textSchwach)
                    }
                }
                ForEach(tage, id: \.self) { tag in
                    GridRow {
                        Text(verbatim: Auswertungsquelle.wochentagKurz(tag))
                            .font(.caption2)
                            .foregroundStyle(thema.textSchwach)
                            .gridColumnAlignment(.leading)
                        ForEach(stunden, id: \.self) { stunde in
                            zelle(heatmap.zelle(wochentag: tag, stunde: stunde), groesster: groesster)
                        }
                    }
                }
            }
            .padding(.bottom, Abstand.raster)
        }
    }

    @ViewBuilder
    private func zelle(_ zelle: Tiefenanalyse.HeatmapZelle?, groesster: Double) -> some View {
        let form = RoundedRectangle(cornerRadius: 3)
        if let zelle {
            Button {
                let titel = "\(Gruppenname.wochentag("\(zelle.wochentag)")), \(Auswertungsquelle.stundeName(zelle.stunde))"
                waehle(Drilldown(titel: titel, tradeIDs: zelle.tradeIDs))
            } label: {
                Text(verbatim: "\(zelle.anzahl)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(thema.text)
                    .frame(minWidth: 26, maxWidth: .infinity, minHeight: 26)
                    .background(farbe(zelle, groesster: groesster), in: form)
                    .contentShape(form)
            }
            .buttonStyle(.plain)
            .help(hilfe(zelle))
            .accessibilityLabel(Text(verbatim: hilfe(zelle)))
        } else {
            form
                .strokeBorder(thema.linie, lineWidth: 1)
                .frame(minWidth: 26, maxWidth: .infinity, minHeight: 26)
                .accessibilityHidden(true)
        }
    }

    private func wert(_ zelle: Tiefenanalyse.HeatmapZelle) -> Double {
        switch mass {
        case .netto: Format.double(zelle.netto)
        case .r: Format.double(zelle.durchschnittR ?? 0)
        }
    }

    /// Belastbare Zellen in Gewinn- oder Verlustfarbe, Deckkraft nach Betrag; die übrigen grau.
    private func farbe(_ zelle: Tiefenanalyse.HeatmapZelle, groesster: Double) -> Color {
        guard zelle.belastbar else { return thema.flaeche2 }
        let w = wert(zelle)
        guard w != 0, groesster > 0 else { return thema.flaeche2 }
        let staerke = 0.2 + 0.6 * min(1, abs(w) / groesster)
        return (w > 0 ? thema.gewinn : thema.verlust).opacity(staerke)
    }

    private func groessterBetrag() -> Double {
        heatmap.zellen.filter(\.belastbar).map { abs(wert($0)) }.max() ?? 0
    }

    private func hilfe(_ zelle: Tiefenanalyse.HeatmapZelle) -> String {
        let ort = "\(Gruppenname.wochentag("\(zelle.wochentag)")) \(Auswertungsquelle.stundeName(zelle.stunde))"
        let zahlen = String(localized: "\(zelle.anzahl) Trades, Netto \(Format.geld(zelle.netto, modell.summenwaehrung)), Treffer \(Format.prozent(zelle.trefferquote)), Ø \(Format.r(zelle.durchschnittR))")
        let hinweis = zelle.belastbar ? "" : String(localized: " (zu wenig Daten)")
        return "\(ort): \(zahlen)\(hinweis)"
    }

    /// Stunden von der frühesten bis zur spätesten Stunde mit Trades.
    private func stundenbereich() -> [Int] {
        guard let von = heatmap.zellen.map(\.stunde).min(), let bis = heatmap.zellen.map(\.stunde).max() else { return [] }
        return Array(von...bis)
    }

    /// Montag bis Freitag immer, Samstag und Sonntag nur mit Trades.
    private func tagesbereich() -> [Int] {
        let mitTrades = Set(heatmap.zellen.map(\.wochentag))
        return (1...7).filter { $0 <= 5 || mitTrades.contains($0) }
    }

    /// Bestes und schwächstes belastbares Zeitfenster als ein Satz.
    private func satz() -> String {
        let belastbar = heatmap.zellen.filter(\.belastbar)
        guard let beste = belastbar.max(by: { wert($0) < wert($1) }),
              let schwaechste = belastbar.min(by: { wert($0) < wert($1) }) else {
            return String(localized: "Noch kein Zeitfenster mit mindestens \(heatmap.mindestanzahl) Trades. Die Farben zeigen erst ab dann Gewinn und Verlust.")
        }
        var teile: [String] = []
        if wert(beste) > 0 { teile.append(String(localized: "Am stärksten: \(fenster(beste)).")) }
        if wert(schwaechste) < 0 { teile.append(String(localized: "Am schwächsten: \(fenster(schwaechste)).")) }
        if teile.isEmpty { return String(localized: "Kein Zeitfenster sticht heraus.") }
        return teile.joined(separator: " ")
    }

    private func fenster(_ zelle: Tiefenanalyse.HeatmapZelle) -> String {
        let ort = "\(Gruppenname.wochentag("\(zelle.wochentag)")) \(Auswertungsquelle.stundeName(zelle.stunde))"
        let betrag = mass == .netto ? Format.geld(zelle.netto, modell.summenwaehrung) : Format.r(zelle.durchschnittR)
        return String(localized: "\(ort) mit \(betrag) bei \(zelle.anzahl) Trades")
    }
}

/// Wochentage und Stunden einzeln als Balken; dieselben Trades wie die Heatmap.
struct ZeitBalkenKarte: View {
    let heatmap: Tiefenanalyse.Heatmap
    let mass: Balkenmass
    let waehle: (Drilldown) -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        let tage = Auswertungsquelle.zusammengefasst(heatmap, nachWochentag: true)
        let stunden = Auswertungsquelle.zusammengefasst(heatmap, nachWochentag: false)
        Karte("Wochentage und Stunden") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                    teil(String(localized: "Wochentag"), tage).frame(maxWidth: .infinity)
                    teil(String(localized: "Stunde"), stunden).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    teil(String(localized: "Wochentag"), tage)
                    teil(String(localized: "Stunde"), stunden)
                }
            }
            Erklaerung(String(localized: "Klick auf einen Balken zeigt die Trades. Die kleine Zahl ist die Anzahl der Trades."))
        }
    }

    private func teil(_ titel: String, _ werte: [Balkenwert]) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            if werte.isEmpty {
                Erklaerung(String(localized: "Keine Trades mit Uhrzeit."))
            } else {
                ErgebnisBalken(werte: werte, mass: mass, waehle: waehle)
            }
        }
    }
}

/// Ergebnis je Schlussmonat als Balken, ältester oben.
struct MonateKarte: View {
    let mass: Balkenmass
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell

    var body: some View {
        let monate = Tiefenanalyse.monate(modell.angeglicheneTrades, zeitzone: modell.zeitzone)
        let werte = monate.map { gruppe in
            Balkenwert(id: "\(gruppe.jahr)-\(gruppe.monat)",
                       name: Auswertungsquelle.monatName(jahr: gruppe.jahr, monat: gruppe.monat),
                       netto: gruppe.netto, anzahl: gruppe.anzahl, durchschnittR: gruppe.durchschnittR,
                       tradeIDs: gruppe.tradeIDs)
        }
        Karte("Monate") {
            if werte.count <= 1 {
                Erklaerung(String(localized: "Nur ein Monat im gewählten Zeitraum. Unter „Zeitraum“ alle Monate wählen, um Monate zu vergleichen."))
            }
            if !werte.isEmpty {
                ErgebnisBalken(werte: werte, mass: mass, waehle: waehle)
            }
            Erklaerung(String(localized: "Monat, in dem der Trade geschlossen wurde."))
        }
    }
}
