import Charts
import Observation
import SwiftUI
import TradingCore

/// Reiter „Risiko“: Verteilung in R und in Geld, Drawdown unter der Kapitalkurve, Serien, Best-Exit.
struct RisikoReiter: View {
    let waehle: (Drilldown) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            VerteilungKarte(waehle: waehle)
            DrawdownKarte(waehle: waehle)
            BestExitKarte()
        }
    }
}

/// Histogramme: Ergebnisse in R (halbe R) und in Geld. Klick auf einen Balken zeigt die Trades der Klasse.
struct VerteilungKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var inR = true

    var body: some View {
        let trades = modell.angeglicheneTrades
        let r = Tiefenanalyse.rVerteilung(trades)
        let betrag = Tiefenanalyse.betragsverteilung(trades)
        let klassen = inR ? r.klassen : betrag.klassen
        Karte("Verteilung der Ergebnisse") {
            Picker("Einheit", selection: $inR) {
                Text("in R").tag(true)
                Text(verbatim: modell.summenwaehrung).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if klassen.isEmpty {
                Erklaerung(inR ? String(localized: "Kein Trade mit bekanntem Risiko. Ohne Stop oder geplantes Risiko gibt es kein R.")
                               : String(localized: "Keine Trades im gewählten Zeitraum."))
            } else {
                histogramm(klassen)
            }
            if inR && r.ohneRisiko > 0 {
                Erklaerung(String(localized: "\(r.ohneRisiko) Trades ohne bekanntes Risiko fehlen hier."))
            }
            Erklaerung(inR ? String(localized: "Klassen zu einem halben R. Links von −1 R liegen Verluste, die größer waren als geplant.")
                           : String(localized: "Ergebnis netto je Trade in Klassen gleicher Breite."))
        }
    }

    private func histogramm(_ klassen: [Tiefenanalyse.Klasse]) -> some View {
        let namen = klassen.map(name)
        return Chart(Array(klassen.enumerated()), id: \.offset) { eintrag in
            BarMark(x: .value("Klasse", namen[eintrag.offset]), y: .value("Trades", eintrag.element.anzahl))
                .foregroundStyle(farbe(eintrag.element))
                .cornerRadius(Diagramm.balkenEndeRadius)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(orientation: .verticalReversed).foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { ort in
                        guard let rahmen = proxy.plotFrame,
                              let gewaehlt = proxy.value(atX: ort.x - geo[rahmen].origin.x, as: String.self),
                              let index = namen.firstIndex(of: gewaehlt), klassen[index].anzahl > 0 else { return }
                        waehle(Drilldown(titel: gewaehlt, tradeIDs: klassen[index].tradeIDs))
                    }
            }
        }
        .frame(height: 220)
    }

    /// Grenzen der Klasse, offen am Rand: „unter −5 R“, „−1 R bis −0,5 R“, „ab 5 R“.
    private func name(_ klasse: Tiefenanalyse.Klasse) -> String {
        switch (klasse.untergrenze, klasse.obergrenze) {
        case (nil, let oben?): return String(localized: "unter \(grenze(oben))")
        case (let unten?, nil): return String(localized: "ab \(grenze(unten))")
        case (let unten?, let oben?): return "\(grenze(unten)) – \(grenze(oben))"
        default: return "–"
        }
    }

    private func grenze(_ wert: Decimal) -> String {
        if inR { return Format.zahl(wert, stellen: 1) + " R" }
        return Format.geld(wert, modell.summenwaehrung)
    }

    private func farbe(_ klasse: Tiefenanalyse.Klasse) -> Color {
        let mitte = klasse.untergrenze ?? (klasse.obergrenze ?? 0) - 1
        return mitte < 0 ? thema.verlust : thema.gewinn
    }
}

/// Kapitalkurve mit dem Abstand zum bisherigen Hoch darunter, größter Rückgang mit Erholung, längste Serien.
struct DrawdownKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let analyse = Tiefenanalyse.drawdown(modell.angeglicheneTrades)
        let waehrung = modell.summenwaehrung
        Karte("Drawdown und Serien") {
            if analyse.punkte.count < 2 {
                Erklaerung(String(localized: "Dafür braucht es mindestens zwei Trades."))
            } else {
                kurve(analyse)
                abstand(analyse)
                Text(verbatim: zusammenfassung(analyse, waehrung))
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            serien(analyse, waehrung)
            Erklaerung(String(localized: "Oben die Summe netto nach jedem Trade, darunter der Abstand zum bisherigen Hoch. Null unterbricht eine Serie."))
        }
    }

    private func kurve(_ analyse: Tiefenanalyse.Drawdownanalyse) -> some View {
        Chart(analyse.punkte, id: \.tradeID) { punkt in
            LineMark(x: .value("Zeit", punkt.zeit), y: .value("Kapital", Format.double(punkt.kapital)))
                .foregroundStyle(thema.akzent)
                .interpolationMethod(.stepEnd)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .frame(height: 160)
    }

    private func abstand(_ analyse: Tiefenanalyse.Drawdownanalyse) -> some View {
        Chart(analyse.punkte, id: \.tradeID) { punkt in
            AreaMark(x: .value("Zeit", punkt.zeit), y: .value("Abstand", -Format.double(punkt.abstand)))
                .foregroundStyle(thema.verlust.opacity(0.35))
                .interpolationMethod(.stepEnd)
            LineMark(x: .value("Zeit", punkt.zeit), y: .value("Abstand", -Format.double(punkt.abstand)))
                .foregroundStyle(thema.verlust)
                .interpolationMethod(.stepEnd)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .frame(height: 110)
    }

    private func zusammenfassung(_ analyse: Tiefenanalyse.Drawdownanalyse, _ waehrung: String) -> String {
        guard analyse.maxDrawdown > 0, let tief = analyse.tiefpunkt else {
            return String(localized: "Kein Rückgang vom Hoch im gewählten Zeitraum.")
        }
        let groesse = Format.geld(-analyse.maxDrawdown, waehrung)
        if let erholt = analyse.erholt {
            return String(localized: "Größter Rückgang \(groesse), Tiefpunkt am \(Format.datum(tief)), wieder auf dem alten Hoch am \(Format.datum(erholt)) (\(Format.dauer(analyse.dauerBisErholung)) nach dem Tiefpunkt).")
        }
        return String(localized: "Größter Rückgang \(groesse), Tiefpunkt am \(Format.datum(tief)), das alte Hoch ist noch nicht wieder erreicht.")
    }

    private func serien(_ analyse: Tiefenanalyse.Drawdownanalyse, _ waehrung: String) -> some View {
        HStack(spacing: Abstand.kachelAbstand) {
            serie(String(localized: "Längste Verlustserie"), analyse.laengsteVerlustserie, waehrung)
            serie(String(localized: "Längste Gewinnserie"), analyse.laengsteGewinnserie, waehrung)
        }
    }

    private func serie(_ titel: String, _ serie: Tiefenanalyse.Serie, _ waehrung: String) -> some View {
        Button {
            waehle(Drilldown(titel: titel, tradeIDs: serie.tradeIDs))
        } label: {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                Text(verbatim: titel)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                Text(verbatim: String(localized: "\(serie.anzahl) Trades"))
                    .font(Schrift.titel)
                    .foregroundStyle(thema.text)
                Text(verbatim: Format.geld(serie.summe, waehrung))
                    .font(Schrift.tabelle)
                    .foregroundStyle(thema.vorzeichen(serie.summe))
                if let von = serie.von, let bis = serie.bis {
                    Text(verbatim: "\(Format.datum(von)) – \(Format.datum(bis))")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Abstand.kachelInnen)
            .background(thema.flaeche2, in: RoundedRectangle(cornerRadius: Abstand.radiusKachel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(serie.tradeIDs.isEmpty)
    }
}

/// Best-Exit (Kern #269): Wie wären feste Ziele bei 1 R, 1,5 R, 2 R und 3 R ausgegangen, verglichen mit dem
/// tatsächlichen Ausstieg, und wo lag die Obergrenze (Ausstieg am besten Kurs)? Kerzen liest der vorhandene
/// Ausstiegsdienst; abgerufen oder importiert werden sie auf der Seite „Ausstieg“.
struct BestExitKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var berechnung = Berechnung()

    struct Schluessel: Equatable {
        var trades: [Trade]
        var stand: Int
        var konto: Int64?
        var waehrung: String
    }

    @Observable @MainActor
    final class Berechnung {
        private var schluessel: Schluessel?
        private var auswertung: BestExitAuswertung?
        private var auftrag = 0
        private(set) var rechnet = false

        func ergebnis(fuer aktuell: Schluessel) -> BestExitAuswertung? {
            schluessel == aktuell ? auswertung : nil
        }

        func zuruecksetzen() {
            auftrag += 1
            schluessel = nil
            auswertung = nil
            rechnet = false
        }

        func aktualisiere(_ neu: Schluessel, rechne: @MainActor () async -> BestExitAuswertung) async {
            zuruecksetzen()
            schluessel = neu
            let lauf = auftrag
            rechnet = true
            let ergebnis = await rechne()
            guard lauf == auftrag else { return }
            rechnet = false
            guard !Task.isCancelled else { return }
            auswertung = ergebnis
        }
    }

    var body: some View {
        let dienst = Ausstiegsdienst.geteilt
        let trades = modell.trades
        let schluessel = Schluessel(trades: trades, stand: dienst.stand, konto: modell.kontoId, waehrung: modell.waehrung)
        Karte("Best-Exit") {
            if istBeispiel {
                Erklaerung(String(localized: "Die Beispiel-Trades haben erfundene Preise. Ein Vergleich mit echten Kursen ergibt hier keinen Sinn."))
            } else if let ergebnis = berechnung.ergebnis(fuer: schluessel), ergebnis.anzahl > 0 {
                inhalt(ergebnis)
            } else if berechnung.rechnet {
                ProgressView().controlSize(.small)
            } else {
                Erklaerung(String(localized: "Für Best-Exit braucht es Trades mit Stop oder geplantem Risiko und Minutenkurse. Kurse holt oder importiert die Seite „Ausstieg“."))
                Button("Zur Seite Ausstieg") { modell.bereich = .ausstieg }
            }
            Erklaerung(String(localized: "Rückblick auf vergangene Kurse, Kerze für Kerze ohne Schlupf. Berührt eine Kerze Stop und Ziel, zählt der Stop. Die Obergrenze ist der Ausstieg genau am besten Kurs; den kennt man im Voraus nicht."))
        }
        .task(id: schluessel) {
            guard !istBeispiel else { berechnung.zuruecksetzen(); return }
            await berechnung.aktualisiere(schluessel) {
                await rechne(trades, dienst: dienst, waehrung: schluessel.waehrung)
            }
        }
    }

    private var istBeispiel: Bool { modell.konto.map(Beispieldaten.istBeispiel) ?? false }

    /// Kerzen je Trade mit Risiko aus dem Speicher; die Auswahl auf die Haltedauer macht der Kern.
    private func rechne(_ trades: [Trade], dienst: Ausstiegsdienst, waehrung: String) async -> BestExitAuswertung {
        await dienst.ladeBestand()
        var kerzen: [String: [Zeitkerze]] = [:]
        for trade in trades where trade.risk != nil && !trade.nurDatum && dienst.hatKerzen(trade.symbol) {
            kerzen[trade.id] = await dienst.chartkerzen(trade)
            if Task.isCancelled { break }
        }
        let waehrungen = Set(trades.map { $0.waehrung(kontowaehrung: waehrung).uppercased() })
        return BestExitAuswertung(trades: trades, kerzenJeTrade: kerzen, gleicheWaehrung: waehrungen.count <= 1)
    }

    private func inhalt(_ ergebnis: BestExitAuswertung) -> some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            Text(verbatim: satz(ergebnis))
                .font(Schrift.fliesstext)
                .foregroundStyle(thema.text)
                .fixedSize(horizontal: false, vertical: true)
            diagramm(ergebnis)
            tabelle(ergebnis)
            Erklaerung(String(localized: "\(ergebnis.anzahl) Trades ausgewertet, \(ergebnis.ohneRisiko) ohne Risiko, \(ergebnis.ohneKerzen) ohne Kurse."))
        }
    }

    private func satz(_ ergebnis: BestExitAuswertung) -> String {
        let tatsaechlich = Format.r(ergebnis.summeTatsaechlichR)
        guard let beste = ergebnis.besteStufe,
              let stufe = ergebnis.stufen.first(where: { $0.ziel == beste }) else {
            return String(localized: "Tatsächlich: \(tatsaechlich).")
        }
        let ziel = Format.zahl(beste, stellen: 1)
        if stufe.differenzR > 0 {
            return String(localized: "Ein festes Ziel bei \(ziel) R hätte \(Format.r(stufe.summeR)) gebracht statt \(tatsaechlich), also \(Format.r(stufe.differenzR)) mehr.")
        }
        return String(localized: "Dein tatsächlicher Ausstieg mit \(tatsaechlich) war besser als jedes feste Ziel; das beste wäre \(ziel) R mit \(Format.r(stufe.summeR)).")
    }

    private func diagramm(_ ergebnis: BestExitAuswertung) -> some View {
        let tatsaechlich = Format.double(ergebnis.summeTatsaechlichR)
        return Chart {
            ForEach(ergebnis.stufen, id: \.ziel) { stufe in
                BarMark(x: .value("Ziel", "\(Format.zahl(stufe.ziel, stellen: 1)) R"), y: .value("Summe R", Format.double(stufe.summeR)))
                    .foregroundStyle(stufe.summeR < 0 ? thema.verlust : thema.gewinn)
                    .cornerRadius(Diagramm.balkenEndeRadius)
            }
            BarMark(x: .value("Ziel", String(localized: "Obergrenze")), y: .value("Summe R", Format.double(ergebnis.summeTheoretischesMaximumR)))
                .foregroundStyle(thema.textSchwach.opacity(0.5))
                .cornerRadius(Diagramm.balkenEndeRadius)
            RuleMark(y: .value("Tatsächlich", tatsaechlich))
                .foregroundStyle(thema.akzent)
                .lineStyle(StrokeStyle(lineWidth: Diagramm.linie, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text(verbatim: String(localized: "tatsächlich \(Format.r(ergebnis.summeTatsaechlichR))"))
                        .font(.caption2)
                        .foregroundStyle(thema.akzent)
                }
            RuleMark(y: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(thema.text)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .frame(height: 200)
    }

    private func tabelle(_ ergebnis: BestExitAuswertung) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Ziel")
                Text("Summe R").gridColumnAlignment(.trailing)
                Text("Ø R").gridColumnAlignment(.trailing)
                Text("Unterschied").gridColumnAlignment(.trailing)
                Text("Ziel zuerst").gridColumnAlignment(.trailing)
                Text("Stop zuerst").gridColumnAlignment(.trailing)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(ergebnis.stufen, id: \.ziel) { stufe in
                GridRow {
                    Text(verbatim: "\(Format.zahl(stufe.ziel, stellen: 1)) R").foregroundStyle(thema.text)
                    Text(verbatim: Format.r(stufe.summeR)).font(Schrift.tabelle).foregroundStyle(thema.vorzeichen(stufe.summeR))
                    Text(verbatim: Format.r(stufe.durchschnittR)).font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: Format.r(stufe.differenzR)).font(Schrift.tabelle).foregroundStyle(thema.vorzeichen(stufe.differenzR))
                    Text(verbatim: "\(stufe.zielErreicht)").font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: "\(stufe.stopZuerst)").font(Schrift.tabelle).foregroundStyle(thema.text)
                }
            }
        }
    }
}
