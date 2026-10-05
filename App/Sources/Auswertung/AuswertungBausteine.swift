import Charts
import SwiftUI
import TradingCore

/// Blatt des Drill-downs: die Trades hinter einer Zelle, einem Balken oder einem Kuchenstück, neueste zuerst.
/// Ein Klick auf eine Zeile springt in die Trade-Liste und wählt den Trade.
struct DrilldownBlatt: View {
    let auswahl: Drilldown
    @Environment(AppModell.self) private var modell
    @Environment(\.dismiss) private var dismiss
    @Environment(\.thema) private var thema

    var body: some View {
        let trades = zeilen()
        let waehrung = modell.summenwaehrung
        let netto: Decimal = trades.map(\.netProfit).reduce(0, +)
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: auswahl.titel)
                    .font(Schrift.titel)
                    .foregroundStyle(thema.text)
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(verbatim: String(localized: "\(trades.count) Trades · Netto \(Format.geld(netto, waehrung))"))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            List(trades, id: \.id) { trade in
                Button {
                    dismiss()
                    modell.zeigeTrade(trade.id)
                } label: {
                    DrilldownZeile(trade: trade, waehrung: waehrung)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .frame(minHeight: 240)
            Text("Klick auf einen Trade öffnet ihn in der Trade-Liste.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
        .padding(Abstand.seitenrand)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .background(thema.grund)
    }

    /// Die Trades der Auswahl in der Anzeigewährung, neueste zuerst.
    private func zeilen() -> [Trade] {
        let ids = Set(auswahl.tradeIDs)
        return modell.angeglicheneTrades
            .filter { ids.contains($0.id) }
            .sorted { ($0.closeTime, $0.id) > ($1.closeTime, $1.id) }
    }
}

/// Eine Zeile im Drill-down: Schlusszeit, Symbol, Richtung, Netto und R.
struct DrilldownZeile: View {
    let trade: Trade
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        HStack(spacing: Abstand.kachelAbstand) {
            Text(verbatim: trade.nurDatum ? Format.datum(trade.closeTime) : Format.zeit(trade.closeTime))
                .font(Schrift.tabelle)
                .foregroundStyle(thema.textSchwach)
            Text(verbatim: trade.symbol)
                .foregroundStyle(thema.text)
                .lineLimit(1)
            Text(verbatim: Format.richtung(trade.side))
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            Spacer()
            Text(verbatim: Format.r(trade.rMultiple))
                .font(Schrift.tabelle)
                .foregroundStyle(trade.rMultiple.map(thema.vorzeichen) ?? thema.textSchwach)
            Text(verbatim: Format.geld(trade.netProfit, waehrung))
                .font(Schrift.tabelle)
                .foregroundStyle(thema.vorzeichen(trade.netProfit))
        }
        .contentShape(Rectangle())
    }
}

/// Kennzahl der Balken: Netto in Geld oder Ø R.
enum Balkenmass: String, CaseIterable, Identifiable {
    case netto, r

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .netto: String(localized: "Netto")
        case .r: String(localized: "Ø R")
        }
    }
}

/// Waagerechte Balken links und rechts der Nulllinie, je Gruppe Netto oder Ø R. Klick auf einen Balken öffnet
/// den Drill-down. Negative Werte passen in keinen Kuchen; deshalb Balken für Ergebnisse (Tim 05.10.2026).
struct ErgebnisBalken: View {
    let werte: [Balkenwert]
    var mass = Balkenmass.netto
    let waehle: (Drilldown) -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        Chart(werte) { wert in
            BarMark(x: .value("Wert", zahl(wert)), y: .value("Gruppe", wert.name))
                .foregroundStyle(zahl(wert) < 0 ? thema.verlust : thema.gewinn)
                .cornerRadius(Diagramm.balkenEndeRadius)
                .annotation(position: zahl(wert) < 0 ? .leading : .trailing) {
                    Text(verbatim: "\(wert.anzahl)")
                        .font(.caption2)
                        .foregroundStyle(thema.textSchwach)
                }
            RuleMark(x: .value("Null", 0.0))
                .foregroundStyle(thema.linie)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(thema.text)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { ort in
                        guard let rahmen = proxy.plotFrame else { return }
                        let y = ort.y - geo[rahmen].origin.y
                        guard let name = proxy.value(atY: y, as: String.self),
                              let wert = werte.first(where: { $0.name == name }) else { return }
                        waehle(Drilldown(titel: wert.name, tradeIDs: wert.tradeIDs))
                    }
            }
        }
        .frame(height: max(120, CGFloat(werte.count) * (Diagramm.balkenMax + Abstand.raster)))
        .accessibilityLabel(Text(verbatim: werte.map { "\($0.name): \(text($0))" }.joined(separator: ", ")))
    }

    private func zahl(_ wert: Balkenwert) -> Double {
        switch mass {
        case .netto: Format.double(wert.netto)
        case .r: Format.double(wert.durchschnittR ?? 0)
        }
    }

    private func text(_ wert: Balkenwert) -> String {
        switch mass {
        case .netto: Format.double(wert.netto).formatted(.number.precision(.fractionLength(2)))
        case .r: Format.r(wert.durchschnittR)
        }
    }
}

/// Donut für Anteile eines Ganzen (SectorMark): Gewinner/Verlierer/Null, Long/Short, Setups und Werte als Top 5
/// plus Rest, Verluste je Fehlermuster. Klick auf ein Stück oder eine Zeile der Legende öffnet den Drill-down.
struct AnteilDonut: View {
    let titel: String
    let anteile: [Tiefenanalyse.Anteil]
    /// Text in der Mitte, etwa die Trefferquote.
    var mitte: String?
    /// Wert eines Stücks als Text für die Legende, etwa Anzahl oder Betrag.
    let wertText: (Tiefenanalyse.Anteil) -> String
    let waehle: (Drilldown) -> Void
    @Environment(\.thema) private var thema

    var body: some View {
        let namen = anteile.map(Auswertungsquelle.anteilName)
        VStack(alignment: .leading, spacing: Abstand.raster * 2) {
            Text(verbatim: titel)
                .font(.headline)
                .foregroundStyle(thema.text)
            if anteile.isEmpty {
                Text("Keine Daten im gewählten Zeitraum.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                kreis(namen)
                legende(namen)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kreis(_ namen: [String]) -> some View {
        Chart(Array(anteile.enumerated()), id: \.offset) { eintrag in
            SectorMark(angle: .value("Anteil", Format.double(eintrag.element.wert)),
                       innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(farbe(eintrag.offset, eintrag.element))
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let mitte, let rahmen = proxy.plotFrame {
                    let feld = geo[rahmen]
                    Text(verbatim: mitte)
                        .font(Schrift.titel)
                        .foregroundStyle(thema.text)
                        .position(x: feld.midX, y: feld.midY)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { ort in
                        guard let rahmen = proxy.plotFrame else { return }
                        let feld = geo[rahmen]
                        if let index = stueck(bei: ort, mitte: CGPoint(x: feld.midX, y: feld.midY)) {
                            waehle(Drilldown(titel: "\(titel): \(namen[index])", tradeIDs: anteile[index].tradeIDs))
                        }
                    }
            }
        }
        .frame(height: 170)
        .accessibilityHidden(true)
    }

    private func legende(_ namen: [String]) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            ForEach(Array(anteile.enumerated()), id: \.offset) { eintrag in
                Button {
                    waehle(Drilldown(titel: "\(titel): \(namen[eintrag.offset])", tradeIDs: eintrag.element.tradeIDs))
                } label: {
                    HStack(spacing: Abstand.raster * 2) {
                        Circle()
                            .fill(farbe(eintrag.offset, eintrag.element))
                            .frame(width: Diagramm.marker, height: Diagramm.marker)
                        Text(verbatim: namen[eintrag.offset])
                            .foregroundStyle(thema.text)
                            .lineLimit(1)
                        Spacer()
                        Text(verbatim: wertText(eintrag.element))
                            .font(Schrift.tabelle)
                            .foregroundStyle(thema.text)
                        Text(verbatim: Format.prozent(eintrag.element.anteil))
                            .font(Schrift.tabelle)
                            .foregroundStyle(thema.textSchwach)
                    }
                    .font(Schrift.beschriftung)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Index des Stücks unter dem Klick: Swift Charts beginnt oben und zeichnet im Uhrzeigersinn.
    private func stueck(bei ort: CGPoint, mitte: CGPoint) -> Int? {
        let summe = anteile.map { Format.double($0.wert) }.reduce(0, +)
        guard summe > 0 else { return nil }
        var winkel = atan2(Double(ort.x - mitte.x), Double(mitte.y - ort.y))
        if winkel < 0 { winkel += 2 * .pi }
        let ziel = winkel / (2 * .pi) * summe
        var laufend = 0.0
        for (index, anteil) in anteile.enumerated() {
            laufend += Format.double(anteil.wert)
            if ziel <= laufend { return index }
        }
        return anteile.indices.last
    }

    /// Farben aus den Token: Ergebnis in Gewinn, Verlust und schwachem Text; sonst Akzent in Stufen, Rest und
    /// „ohne“ in schwachem Text.
    private func farbe(_ index: Int, _ anteil: Tiefenanalyse.Anteil) -> Color {
        switch anteil.schluessel {
        case "gewinner": return thema.gewinn
        case "verlierer": return thema.verlust
        case "breakeven": return thema.textSchwach
        default: break
        }
        if anteil.art != .eintrag { return thema.textSchwach.opacity(0.6) }
        let stufen: [Double] = [1, 0.75, 0.55, 0.4, 0.28, 0.2]
        return thema.akzent.opacity(stufen[min(index, stufen.count - 1)])
    }
}

/// Satz unter einer Grafik in schwacher Schrift.
struct Erklaerung: View {
    let text: String
    @Environment(\.thema) private var thema

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(Schrift.beschriftung)
            .foregroundStyle(thema.textSchwach)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Umschalter Netto oder Ø R für Balken und Heatmap.
struct MassWahl: View {
    @Binding var mass: Balkenmass

    var body: some View {
        Picker("Kennzahl", selection: $mass) {
            ForEach(Balkenmass.allCases) { Text(verbatim: $0.titel).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
