import Charts
import SwiftUI
import TradingCore

/// Reiter „Verhalten“: Tagesverlauf mit Revanche- und Überhandeln-Phasen, Trades je Tag gegen Ergebnis,
/// Kosten der Fehlermuster, Tags, Zustand und Marktumfeld, Reihenfolge-Effekte.
struct VerhaltenReiter: View {
    let waehle: (Drilldown) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            TagesverlaufKarte(waehle: waehle)
            TradesJeTagKarte(waehle: waehle)
            MusterkostenKarte(waehle: waehle)
            MerkmalKarte(waehle: waehle)
            ReihenfolgeKarte()
        }
    }
}

/// Ablauf eines Handelstags als Zeitstrahl: laufende Tagessumme, Punkt je Schluss, Revanche- und
/// Überhandeln-Phasen farbig hinterlegt. Standard ist der jüngste Tag.
struct TagesverlaufKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var gewaehlt: Journaltag?

    var body: some View {
        let trades = modell.angeglicheneTrades
        let tage = Tiefenanalyse.tradesJeTag(trades, zeitzone: modell.zeitzone).punkte.reversed().map(\.tag)
        let tag = gewaehlt.flatMap { tage.contains($0) ? $0 : nil } ?? tage.first
        Karte("Tagesverlauf") {
            if let tag {
                let verlauf = Tiefenanalyse.tagesverlauf(trades, tag: tag, befunde: modell.befunde,
                                                         zeitzone: modell.zeitzone)
                HStack {
                    Picker("Tag", selection: Binding(get: { tag }, set: { gewaehlt = $0 })) {
                        ForEach(tage, id: \.self) { t in
                            Text(verbatim: Format.datum(t.beginn(in: modell.zeitzone))).tag(t)
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Text(verbatim: String(localized: "Tagesergebnis \(Format.geld(verlauf.netto, modell.summenwaehrung))"))
                        .font(Schrift.tabelle)
                        .foregroundStyle(thema.vorzeichen(verlauf.netto))
                }
                if verlauf.eintraege.isEmpty {
                    Erklaerung(String(localized: "An diesem Tag nur Trades ohne Uhrzeit; kein Zeitstrahl."))
                } else {
                    zeitstrahl(verlauf)
                    phasen(verlauf)
                }
                if !verlauf.ohneUhrzeit.isEmpty {
                    Erklaerung(String(localized: "\(verlauf.ohneUhrzeit.count) Trades ohne Uhrzeit zählen im Tagesergebnis, fehlen im Zeitstrahl."))
                }
            } else {
                Erklaerung(String(localized: "Keine Trades im gewählten Zeitraum."))
            }
            Erklaerung(String(localized: "Linie: laufende Summe des Tages nach jedem Schluss. Orange hinterlegt: Revanche-Trade nach einem Verlust. Rot hinterlegt: Überhandeln, mehr Trades als an üblichen Tagen."))
        }
    }

    private func zeitstrahl(_ verlauf: Tiefenanalyse.Tagesverlauf) -> some View {
        let start = verlauf.eintraege.map(\.einstieg).min() ?? Date()
        // Die Linie beginnt beim ersten Einstieg mit 0, danach ein Punkt je Schluss.
        var punkte: [(zeit: Date, summe: Decimal)] = [(zeit: start, summe: 0)]
        for punkt in verlauf.punkte {
            punkte.append((zeit: punkt.zeit, summe: punkt.summe))
        }
        return Chart {
            ForEach(Array(verlauf.phasen.enumerated()), id: \.offset) { eintrag in
                RectangleMark(xStart: .value("Von", eintrag.element.von), xEnd: .value("Bis", eintrag.element.bis))
                    .foregroundStyle(phasenfarbe(eintrag.element.muster))
            }
            RuleMark(y: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
            ForEach(Array(punkte.enumerated()), id: \.offset) { eintrag in
                LineMark(x: .value("Zeit", eintrag.element.zeit), y: .value("Summe", Format.double(eintrag.element.summe)))
                    .foregroundStyle(thema.akzent)
                    .interpolationMethod(.stepEnd)
            }
            ForEach(verlauf.eintraege, id: \.tradeID) { e in
                PointMark(x: .value("Zeit", e.ausstieg), y: .value("Summe", Format.double(e.summeNachSchluss)))
                    .foregroundStyle(thema.vorzeichen(e.netto))
                    .symbolSize(60)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(thema.textSchwach)
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

    @ViewBuilder
    private func phasen(_ verlauf: Tiefenanalyse.Tagesverlauf) -> some View {
        if !verlauf.phasen.isEmpty {
            VStack(alignment: .leading, spacing: Abstand.raster) {
                ForEach(Array(verlauf.phasen.enumerated()), id: \.offset) { eintrag in
                    let phase = eintrag.element
                    let text = "\(phase.muster.titel) \(Format.uhrzeit(phase.von))–\(Format.uhrzeit(phase.bis))"
                    Button {
                        waehle(Drilldown(titel: text, tradeIDs: phase.tradeIDs))
                    } label: {
                        HStack(spacing: Abstand.raster * 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(phasenfarbe(phase.muster))
                                .frame(width: Diagramm.marker * 2, height: Diagramm.marker)
                            Text(verbatim: text)
                                .foregroundStyle(thema.text)
                            Text(verbatim: String(localized: "\(phase.tradeIDs.count) Trades"))
                                .foregroundStyle(thema.textSchwach)
                        }
                        .font(Schrift.beschriftung)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func phasenfarbe(_ muster: Fehlermuster) -> Color {
        muster == .revancheTrade ? thema.warnung.opacity(0.25) : thema.verlust.opacity(0.18)
    }
}

/// Trades je Tag gegen Tagesergebnis mit Trendlinie: Wird es schlechter, wenn ich mehr handle?
struct TradesJeTagKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let ergebnis = Tiefenanalyse.tradesJeTag(modell.angeglicheneTrades, zeitzone: modell.zeitzone)
        Karte("Trades je Tag") {
            if ergebnis.punkte.count < 2 {
                Erklaerung(String(localized: "Dafür braucht es Trades an mehreren Tagen."))
            } else {
                diagramm(ergebnis)
                Erklaerung(satz(ergebnis))
            }
            Erklaerung(String(localized: "Ein Punkt je Handelstag. Teilverkäufe einer Position zählen als ein Trade. Klick auf eine Spalte zeigt die Trades dieser Tage."))
        }
    }

    private func diagramm(_ ergebnis: Tiefenanalyse.TradesJeTag) -> some View {
        let xs = ergebnis.punkte.map { Double($0.trades) }
        let links = xs.min() ?? 0
        let rechts = xs.max() ?? 0
        var linie: [(x: Double, y: Double)] = []
        if let r = ergebnis.regression {
            linie = [(x: links, y: r.wert(bei: links)), (x: rechts, y: r.wert(bei: rechts))]
        }
        return Chart {
            RuleMark(y: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
            ForEach(Array(ergebnis.punkte.enumerated()), id: \.offset) { eintrag in
                PointMark(x: .value("Trades", eintrag.element.trades), y: .value("Netto", Format.double(eintrag.element.netto)))
                    .foregroundStyle(thema.vorzeichen(eintrag.element.netto))
                    .symbolSize(50)
            }
            ForEach(Array(linie.enumerated()), id: \.offset) { eintrag in
                LineMark(x: .value("Trades", eintrag.element.x), y: .value("Trend", eintrag.element.y), series: .value("Linie", "Trend"))
                    .foregroundStyle(thema.akzent)
                    .lineStyle(StrokeStyle(lineWidth: Diagramm.linie, dash: [5, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
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
                              let x = proxy.value(atX: ort.x - geo[rahmen].origin.x, as: Double.self) else { return }
                        let anzahl = Int(x.rounded())
                        let tage = ergebnis.punkte.filter { $0.trades == anzahl }
                        guard !tage.isEmpty else { return }
                        waehle(Drilldown(titel: String(localized: "Tage mit \(anzahl) Trades"),
                                         tradeIDs: tage.flatMap(\.tradeIDs)))
                    }
            }
        }
        .frame(height: 200)
    }

    private func satz(_ ergebnis: Tiefenanalyse.TradesJeTag) -> String {
        guard let r = ergebnis.regression else {
            return String(localized: "Für eine Trendlinie braucht es mindestens drei Tage mit unterschiedlich vielen Trades.")
        }
        let betrag = Format.geld(Decimal(abs(r.steigung)), modell.summenwaehrung)
        if r.steigung < 0 {
            return String(localized: "Trendlinie: Jeder weitere Trade am Tag ging im Schnitt mit \(betrag) weniger Tagesergebnis einher.")
        }
        return String(localized: "Trendlinie: Jeder weitere Trade am Tag ging im Schnitt mit \(betrag) mehr Tagesergebnis einher.")
    }
}

/// Was die Fehlermuster gekostet haben, in Geld und R, und welcher Teil der Verluste auf welches Muster fällt.
struct MusterkostenKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let kosten = Auswertungsquelle.musterkosten(modell)
        let werte = kosten.map {
            Balkenwert(id: $0.id, name: $0.muster.titel, netto: $0.netto, anzahl: $0.anzahl,
                       durchschnittR: nil, tradeIDs: $0.tradeIDs)
        }
        let anteile = Tiefenanalyse.anteileVerlusteJeMuster(modell.angeglicheneTrades, befunde: modell.befunde)
        Karte("Fehlermuster in Geld und R") {
            if kosten.isEmpty {
                Erklaerung(String(localized: "Im gewählten Zeitraum hat kein Fehlermuster angeschlagen."))
            } else {
                ErgebnisBalken(werte: werte, waehle: waehle)
                tabelle(kosten)
            }
            AnteilDonut(titel: String(localized: "Verluste je Fehlermuster"), anteile: anteile,
                        wertText: { Format.betrag($0.wert, modell.summenwaehrung) }, waehle: waehle)
            Erklaerung(String(localized: "Netto und Summe R der Trades mit diesem Muster; ein Trade kann mehrere Muster tragen. Im Kreis zählt jeder Verlierer nur einmal, beim ersten seiner Muster."))
        }
    }

    private func tabelle(_ kosten: [Musterkosten]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Muster")
                Text("Trades").gridColumnAlignment(.trailing)
                Text("Netto").gridColumnAlignment(.trailing)
                Text("Summe R").gridColumnAlignment(.trailing)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(kosten) { k in
                GridRow {
                    Text(verbatim: k.muster.titel).foregroundStyle(thema.text).lineLimit(1)
                    Text(verbatim: "\(k.anzahl)").font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: Format.geld(k.netto, modell.summenwaehrung))
                        .font(Schrift.tabelle)
                        .foregroundStyle(thema.vorzeichen(k.netto))
                    Text(verbatim: Format.r(k.summeR))
                        .font(Schrift.tabelle)
                        .foregroundStyle(k.summeR.map(thema.vorzeichen) ?? thema.textSchwach)
                }
            }
        }
    }
}

/// Auswertung nach Tags, Zustand, Marktumfeld oder Setup (Kern `Merkmalauswertung`).
struct MerkmalKarte: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema
    @State private var art = Merkmalart.tags

    var body: some View {
        let auswertung = Merkmalauswertung(trades: modell.angeglicheneTrades,
                                           merkmale: Auswertungsquelle.merkmale(modell, art: art))
        let werte = auswertung.merkmale.map {
            Balkenwert(id: $0.merkmal, name: $0.merkmal, netto: $0.netto, anzahl: $0.anzahl,
                       durchschnittR: $0.durchschnittR, tradeIDs: $0.tradeIDs)
        }
        Karte("Tags, Zustand und Marktumfeld") {
            Picker("Merkmal", selection: $art) {
                ForEach(Merkmalart.allCases) { Text(verbatim: $0.titel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if werte.isEmpty {
                Erklaerung(leer)
            } else {
                ErgebnisBalken(werte: Array(werte.prefix(12)), waehle: waehle)
                tabelle(auswertung)
            }
            if auswertung.ohneMerkmal > 0 && !werte.isEmpty {
                Erklaerung(String(localized: "\(auswertung.ohneMerkmal) Trades ohne Eintrag."))
            }
        }
    }

    private var leer: String {
        switch art {
        case .tags: String(localized: "Noch keine Tags an Trades im gewählten Zeitraum.")
        case .zustand: String(localized: "Noch kein Zustand eingetragen. Den Zustand von 1 bis 5 trägst du im Inspektor eines Trades ein.")
        case .marktumfeld: String(localized: "Noch kein Marktumfeld eingetragen.")
        case .setup: String(localized: "Noch kein Setup eingetragen.")
        }
    }

    private func tabelle(_ auswertung: Merkmalauswertung) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            GridRow {
                Text("Merkmal")
                Text("Trades").gridColumnAlignment(.trailing)
                Text("Treffer").gridColumnAlignment(.trailing)
                Text("Ø R").gridColumnAlignment(.trailing)
                Text("Anteil an Verlierern").gridColumnAlignment(.trailing)
            }
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            ForEach(auswertung.merkmale.prefix(12), id: \.merkmal) { je in
                GridRow {
                    Text(verbatim: je.merkmal).foregroundStyle(thema.text).lineLimit(1)
                    Text(verbatim: "\(je.anzahl)").font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: Format.prozent(je.trefferquote)).font(Schrift.tabelle).foregroundStyle(thema.text)
                    Text(verbatim: Format.r(je.durchschnittR))
                        .font(Schrift.tabelle)
                        .foregroundStyle(je.durchschnittR.map(thema.vorzeichen) ?? thema.textSchwach)
                    Text(verbatim: Format.prozent(je.anteilAnVerlierern)).font(Schrift.tabelle).foregroundStyle(thema.text)
                }
            }
        }
    }
}
