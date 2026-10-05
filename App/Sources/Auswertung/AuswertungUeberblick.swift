import SwiftUI
import TradingCore

/// Kacheln in R wie in der Ur-Vorlage (Tim 05.10.2026 20:31 UTC): Ø Gewinn, Ø Verlust, größter Verlust und
/// Verluste über 1 R. Nur Trades mit bekanntem Risiko (Stop oder geplantes Risiko).
struct RKacheln: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let r = RKennzahlen(trades: modell.angeglicheneTrades)
        LazyVGrid(columns: Raster.kacheln, spacing: Abstand.kachelAbstand) {
            Kachel(titel: "Ø Gewinn in R",
                   wert: Format.r(r.durchschnittGewinnR),
                   zusatz: String(localized: "\(r.anzahlGewinnerMitR) Gewinner mit Risiko"),
                   farbe: r.durchschnittGewinnR.map(thema.vorzeichen),
                   hilfe: Kennzahlhilfe.erwartung)
            Kachel(titel: "Ø Verlust in R",
                   wert: Format.r(r.durchschnittVerlustR),
                   zusatz: String(localized: "\(r.anzahlVerliererMitR) Verlierer mit Risiko"),
                   farbe: r.durchschnittVerlustR.map(thema.vorzeichen))
            Kachel(titel: "Größter Verlust in R",
                   wert: Format.r(r.groessterVerlustR),
                   zusatz: String(localized: "Plan war −1 R"),
                   farbe: r.groessterVerlustR.map(thema.vorzeichen))
            Kachel(titel: "Verluste über 1 R",
                   wert: "\(r.verlusteUeber1R)",
                   zusatz: String(localized: "\(Format.prozent(r.anteilVerlusteUeber1R)) der Verlierer mit Risiko"),
                   farbe: r.verlusteUeber1R > 0 ? thema.verlust : nil)
        }
    }
}

/// Leistungsscore als Netzdiagramm mit der Gesamtzahl in der Mitte (Tim 05.10.2026 „alle vier“). Regeltreue aus
/// der Regelprüfung; ohne Regeln fehlt die Achse und der Kern verteilt die Gewichte neu.
struct ScoreNetzKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        let score = Leistungsscore(trades: modell.angeglicheneTrades, zeitzone: modell.zeitzone,
                                   regeltreue: Auswertungsquelle.regeltreue(modell))
        Karte("Score") {
            if let score {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Abstand.kachelAbstand * 2) {
                        ScoreNetz(score: score).frame(maxWidth: .infinity)
                        komponenten(score).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                        ScoreNetz(score: score)
                        komponenten(score)
                    }
                }
            } else {
                Text("Der Score braucht mindestens \(Leistungsscore.mindestanzahl) Trades im gewählten Zeitraum.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
            Erklaerung(String(localized: "0 bis 100 aus Trefferquote, Gewinn-Verlust-Verhältnis, Profitfaktor, Beständigkeit (Anteil Tage im Plus), Drawdown im Verhältnis zu den Gewinnen und Regeltreue. Die Ankerwerte sind Vorschläge und beschreiben die Vergangenheit."))
        }
    }

    private func komponenten(_ score: Leistungsscore) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Abstand.kachelAbstand, verticalSpacing: Abstand.raster) {
            ForEach(score.komponenten, id: \.schluessel) { teil in
                GridRow {
                    Text(verbatim: ScoreNetz.name(teil.komponente))
                        .foregroundStyle(thema.text)
                    Text(verbatim: ScoreNetz.rohwert(teil))
                        .font(Schrift.tabelle)
                        .foregroundStyle(thema.textSchwach)
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: Format.zahl(teil.wert, stellen: 0))
                        .font(Schrift.tabelle.weight(.semibold))
                        .foregroundStyle(thema.text)
                        .gridColumnAlignment(.trailing)
                }
                .font(Schrift.beschriftung)
            }
            if score.wert(.regeltreue) == nil {
                GridRow {
                    Text("Regeltreue")
                        .foregroundStyle(thema.textSchwach)
                    Text("keine Regeln")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                        .gridCellColumns(2)
                }
                .font(Schrift.beschriftung)
            }
        }
    }
}

/// Netzdiagramm (Radar): eine Achse je Komponente, Ringe bei 25, 50, 75 und 100, Fläche im Akzent.
struct ScoreNetz: View {
    let score: Leistungsscore
    @Environment(\.thema) private var thema

    var body: some View {
        let werte = score.komponenten.map { Format.double($0.wert) / 100 }
        let namen = score.komponenten.map { Self.name($0.komponente) }
        GeometryReader { geo in
            let mitte = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = max(20, min(geo.size.width, geo.size.height) / 2 - 34)
            ZStack {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { stufe in
                    Vieleck(anteile: Array(repeating: stufe, count: werte.count), mitte: mitte, radius: radius)
                        .stroke(thema.linie, lineWidth: 1)
                }
                Vieleck(anteile: werte, mitte: mitte, radius: radius)
                    .fill(thema.akzent.opacity(0.22))
                Vieleck(anteile: werte, mitte: mitte, radius: radius)
                    .stroke(thema.akzent, lineWidth: Diagramm.linie)
                ForEach(namen.indices, id: \.self) { index in
                    Text(verbatim: namen[index])
                        .font(.caption2)
                        .foregroundStyle(thema.textSchwach)
                        .fixedSize()
                        .position(Vieleck.punkt(index, anzahl: namen.count, mitte: mitte, radius: radius + 18))
                }
                VStack(spacing: 0) {
                    Text(verbatim: Format.zahl(score.gesamt, stellen: 0))
                        .font(Schrift.zahlGross)
                        .foregroundStyle(thema.text)
                    Text("von 100")
                        .font(.caption2)
                        .foregroundStyle(thema.textSchwach)
                }
                .position(mitte)
            }
        }
        .frame(minHeight: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(localized: "Score \(Format.zahl(score.gesamt, stellen: 0)) von 100")))
    }

    static func name(_ komponente: Leistungsscore.Komponente) -> String {
        switch komponente {
        case .trefferquote: String(localized: "Trefferquote")
        case .payoff: String(localized: "Gewinn zu Verlust")
        case .profitfaktor: String(localized: "Profitfaktor")
        case .bestaendigkeit: String(localized: "Beständigkeit")
        case .drawdown: String(localized: "Drawdown")
        case .regeltreue: String(localized: "Regeltreue")
        }
    }

    /// Rohwert vor der Skalierung: Anteile in Prozent, Verhältnisse als Zahl.
    static func rohwert(_ teil: Leistungsscore.Komponentenwert) -> String {
        guard let roh = teil.rohwert else { return "–" }
        switch teil.komponente {
        case .trefferquote, .bestaendigkeit, .regeltreue, .drawdown: return Format.prozent(roh)
        case .payoff, .profitfaktor: return Format.zahl(roh)
        }
    }
}

/// Vieleck um eine Mitte: Ecke `i` bei Winkel −90° + i × 360° ÷ Anzahl, Abstand `anteil × radius`.
struct Vieleck: Shape {
    let anteile: [Double]
    let mitte: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var pfad = Path()
        guard anteile.count >= 3 else { return pfad }
        for (index, anteil) in anteile.enumerated() {
            let punkt = Self.punkt(index, anzahl: anteile.count, mitte: mitte, radius: radius * CGFloat(max(0, anteil)))
            if index == 0 { pfad.move(to: punkt) } else { pfad.addLine(to: punkt) }
        }
        pfad.closeSubpath()
        return pfad
    }

    static func punkt(_ index: Int, anzahl: Int, mitte: CGPoint, radius: CGFloat) -> CGPoint {
        let winkel = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(anzahl, 1))
        return CGPoint(x: mitte.x + radius * CGFloat(cos(winkel)), y: mitte.y + radius * CGFloat(sin(winkel)))
    }
}

/// Donuts im Überblick: Gewinner, Verlierer und Null mit der Trefferquote in der Mitte; Long und Short.
struct UeberblickDonuts: View {
    let waehle: (Drilldown) -> Void
    @Environment(AppModell.self) private var modell

    var body: some View {
        let trades = modell.angeglicheneTrades
        let kennzahlen = modell.kennzahlen
        Karte("Anteile") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand * 2) {
                    ergebnis(trades, kennzahlen).frame(maxWidth: .infinity)
                    richtung(trades).frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: Abstand.kachelAbstand) {
                    ergebnis(trades, kennzahlen)
                    richtung(trades)
                }
            }
        }
    }

    private func ergebnis(_ trades: [Trade], _ kennzahlen: Kennzahlen) -> some View {
        AnteilDonut(titel: String(localized: "Gewinner und Verlierer"),
                    anteile: Tiefenanalyse.anteileErgebnis(trades),
                    mitte: Format.prozent(kennzahlen.trefferquote),
                    wertText: { "\(Format.zahl($0.wert, stellen: 0))" },
                    waehle: waehle)
    }

    private func richtung(_ trades: [Trade]) -> some View {
        AnteilDonut(titel: String(localized: "Long und Short"),
                    anteile: Tiefenanalyse.anteileRichtung(trades),
                    wertText: { "\(Format.zahl($0.wert, stellen: 0))" },
                    waehle: waehle)
    }
}
