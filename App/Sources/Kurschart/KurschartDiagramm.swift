import Charts
import SwiftUI
import TradingQuotes

/// Texte zum Kurschart.
enum KurschartFormat {
    static func titel(_ zeitraum: Chartzeitraum) -> String {
        switch zeitraum {
        case .monat: String(localized: "1 Monat")
        case .quartal: String(localized: "3 Monate")
        case .halbjahr: String(localized: "6 Monate")
        case .jahr: String(localized: "1 Jahr")
        }
    }
}

/// Kerzen als Docht (Tief bis Hoch) und Körper (Eröffnung bis Schluss), dazu Marken für eigene Ein- und Ausstiege
/// und Rauten am unteren Rand für Tage mit Meldungen. Ein Klick wählt den Tag für die Meldungsliste.
struct KurschartDiagramm: View {
    let chart: Kurschart
    let waehrung: String
    @Binding var gewaehlterTag: Date?
    @Environment(\.thema) private var thema

    var body: some View {
        Chart {
            ForEach(chart.kerzen, id: \.zeit) { kerze in
                RuleMark(x: .value("Tag", kerze.zeit, unit: .day),
                         yStart: .value("Tief", zahl(kerze.tief)), yEnd: .value("Hoch", zahl(kerze.hoch)))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(farbe(kerze))
                    .accessibilityHidden(true)
                RectangleMark(x: .value("Tag", kerze.zeit, unit: .day),
                              yStart: .value("Eröffnung", zahl(kerze.eroeffnung)),
                              yEnd: .value("Schluss", zahl(kerze.schluss)), width: .ratio(0.6))
                    .foregroundStyle(farbe(kerze))
                    .accessibilityLabel(Text(kerze.zeit, format: .dateTime.day().month()))
                    .accessibilityValue(Text(richtung(kerze)))
            }
            ForEach(chart.marken) { marke in
                PointMark(x: .value("Tag", marke.zeit, unit: .day), y: .value("Preis", zahl(marke.preis)))
                    .symbol(symbol(marke))
                    .symbolSize(70)
                    .foregroundStyle(markenfarbe(marke))
            }
            ForEach(chart.nachrichtentage) { tag in
                PointMark(x: .value("Tag", tag.tag, unit: .day), y: .value("Preis", zahl(chart.tief)))
                    .symbol(.diamond)
                    .symbolSize(istGewaehlt(tag.tag) ? 90 : 45)
                    .foregroundStyle(istGewaehlt(tag.tag) ? thema.akzent : thema.textSchwach)
            }
        }
        .chartYScale(domain: zahl(chart.tief)...zahl(chart.hoch))
        .chartXSelection(value: $gewaehlterTag)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(thema.textSchwach)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(thema.linie)
                AxisValueLabel().foregroundStyle(thema.textSchwach)
            }
        }
        .accessibilityLabel(Text("Kurschart mit \(chart.kerzen.count) Tageskerzen und \(chart.marken.count) Marken"))
    }

    private func zahl(_ wert: Decimal) -> Double { Format.double(wert) }

    private func farbe(_ kerze: Tageskerze) -> Color {
        let farbe = kerze.schluss >= kerze.eroeffnung ? thema.gewinn : thema.verlust
        return kerze.abgeschlossen ? farbe : farbe.opacity(0.8)
    }

    /// Richtung der Kerze für VoiceOver; im Bild trägt sie nur die Farbe.
    private func richtung(_ kerze: Tageskerze) -> LocalizedStringKey {
        kerze.schluss >= kerze.eroeffnung ? "steigend" : "fallend"
    }

    /// Form statt nur Farbe: Dreieck Einstieg, Kreis Ausstieg, Kreuz Ausstieg mit Verlust.
    private func symbol(_ marke: Chartmarke) -> BasicChartSymbolShape {
        if marke.art == .einstieg { return .triangle }
        if let ergebnis = marke.ergebnis, ergebnis < 0 { return .cross }
        return .circle
    }

    private func markenfarbe(_ marke: Chartmarke) -> Color {
        guard let ergebnis = marke.ergebnis else { return thema.akzent }
        return ergebnis >= 0 ? thema.gewinn : thema.verlust
    }

    private func istGewaehlt(_ tag: Date) -> Bool {
        guard let gewaehlterTag else { return false }
        return Calendar.current.isDate(tag, inSameDayAs: gewaehlterTag)
    }
}

/// Meldungen je Tag, neueste zuerst; mit gewähltem Tag nur dieser. Öffnet den Link im Browser (R6).
struct KurschartMeldungen: View {
    let tage: [Nachrichtentag]
    @Binding var gewaehlterTag: Date?
    @Environment(\.thema) private var thema
    @Environment(\.openURL) private var openURL

    var body: some View {
        let gezeigt = tage.reversed().filter { tag in
            guard let gewaehlterTag else { return true }
            return Calendar.current.isDate(tag.tag, inSameDayAs: gewaehlterTag)
        }
        VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
            if gewaehlterTag != nil {
                Button("Alle Tage zeigen") { gewaehlterTag = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(thema.akzent)
            }
            if gezeigt.isEmpty {
                Text("An diesem Tag keine Meldungen.")
                    .foregroundStyle(thema.textSchwach)
            }
            ForEach(gezeigt) { tag in
                ForEach(tag.meldungen) { meldung in
                    Button { openURL(meldung.link) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: meldung.titel)
                                .foregroundStyle(thema.text)
                            Text(verbatim: meldung.quelle + " · " + Format.zeit(meldung.zeit))
                                .font(Schrift.beschriftung)
                                .foregroundStyle(thema.textSchwach)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Im Browser öffnen"))
                }
            }
        }
    }
}
