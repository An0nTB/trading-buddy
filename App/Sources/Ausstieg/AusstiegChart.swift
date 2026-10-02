import Charts
import SwiftUI
import TradingCore

/// Ein Balken des Trade-Charts: mehrere Minutenkerzen zusammengefasst, damit auch lange Trades flüssig zeichnen.
struct Chartbalken: Identifiable, Equatable {
    let id: Int
    let mitte: Date
    let hoch: Double
    let tief: Double
    let schluss: Double

    /// Fasst aufsteigende Kerzen zu höchstens `hoechstens` Balken zusammen (Hoch, Tief, letzter Schluss).
    static func buendle(_ kerzen: [Zeitkerze], hoechstens: Int = 240) -> [Chartbalken] {
        guard !kerzen.isEmpty, hoechstens > 0 else { return [] }
        let groesse = max(1, (kerzen.count + hoechstens - 1) / hoechstens)
        var ergebnis: [Chartbalken] = []
        var start = 0
        while start < kerzen.count {
            let teil = kerzen[start..<min(start + groesse, kerzen.count)]
            if let erste = teil.first, let letzte = teil.last,
               let hoch = teil.map(\.high).max(), let tief = teil.map(\.low).min() {
                let mitte = erste.beginn.addingTimeInterval(letzte.ende.timeIntervalSince(erste.beginn) / 2)
                ergebnis.append(Chartbalken(id: ergebnis.count, mitte: mitte, hoch: Format.double(hoch),
                                            tief: Format.double(tief), schluss: Format.double(letzte.close)))
            }
            start += groesse
        }
        return ergebnis
    }
}

/// Kursverlauf eines Trades aus den gespeicherten Minutenkerzen (F8, Paket A3): Spanne je Balken, Schlusskurs als
/// Linie, Einstieg als Dreieck, Ausstieg als Kreis, Stop und Ziel gestrichelt. Nur Rückblick, keine Aussage über
/// künftige Kurse.
struct AusstiegChart: View {
    let trade: Trade
    let balken: [Chartbalken]
    @Environment(\.thema) private var thema

    init(trade: Trade, kerzen: [Zeitkerze]) {
        self.trade = trade
        self.balken = Chartbalken.buendle(kerzen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            diagramm
                .frame(height: 180)
            Text("Dreieck Einstieg, Kreis Ausstieg, gestrichelt Stop (rot) und Ziel (grün).")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
        }
    }

    private var diagramm: some View {
        Chart {
            RuleMark(x: .value("Zeit", trade.openTime))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(thema.linie)
            RuleMark(x: .value("Zeit", trade.closeTime))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(thema.linie)
            ForEach(balken) { b in
                RuleMark(x: .value("Zeit", b.mitte), yStart: .value("Tief", b.tief), yEnd: .value("Hoch", b.hoch))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(thema.textSchwach.opacity(0.5))
            }
            ForEach(balken) { b in
                LineMark(x: .value("Zeit", b.mitte), y: .value("Schluss", b.schluss))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(thema.text)
            }
            if let stop = trade.stopLoss {
                RuleMark(y: .value("Stop", Format.double(stop)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(thema.verlust)
            }
            if let ziel = trade.takeProfit {
                RuleMark(y: .value("Ziel", Format.double(ziel)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(thema.gewinn)
            }
            PointMark(x: .value("Zeit", trade.openTime), y: .value("Preis", Format.double(trade.openPrice)))
                .symbol(.triangle)
                .symbolSize(70)
                .foregroundStyle(thema.akzent)
            PointMark(x: .value("Zeit", trade.closeTime), y: .value("Preis", Format.double(trade.closePrice)))
                .symbol(.circle)
                .symbolSize(70)
                .foregroundStyle(ausstiegsfarbe)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel(format: achsenformat).foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .accessibilityLabel(Text("Kursverlauf des Trades mit \(balken.count) Balken, Einstieg und Ausstieg markiert"))
    }

    private var ausstiegsfarbe: Color {
        trade.netProfit >= 0 ? thema.gewinn : thema.verlust
    }

    /// Uhrzeit bei kurzen Spannen, sonst Tag und Monat.
    private var achsenformat: Date.FormatStyle {
        guard let erste = balken.first, let letzte = balken.last,
              letzte.mitte.timeIntervalSince(erste.mitte) > 2 * 86_400 else {
            return .dateTime.hour().minute()
        }
        return .dateTime.day().month(.abbreviated)
    }
}
