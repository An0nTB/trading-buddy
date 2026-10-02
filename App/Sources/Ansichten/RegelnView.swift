import Charts
import SwiftUI
import TradingCore

/// Karten der Handelsregeln auf der Übersicht (P6; Doc 18 F1 und F10): Regel-Ampel des letzten Handelstags,
/// Disziplin-Kurve neben der Kapitalkurve, Stand der Prop-Firm-Challenge. Alle drei erscheinen nur, wenn
/// Regeln gesetzt sind (`Handelsregeln.leer`); geprüft wird nach dem Import, nicht live (E3).

/// Ampelstufe einer Regel am Tagesende: frei, Grenze nah oder erreicht, Verstoß oder überschritten.
enum Ampelstufe {
    case gruen, gelb, rot
}

/// Eine Zeile der Regel-Ampel.
struct Ampellampe: Identifiable {
    let id: String
    let titel: String
    let wert: String
    let status: String
    let stufe: Ampelstufe

    /// Baut die Zeilen für einen Tagesstand: nur gesetzte Regeln, dazu Journal-Markierungen „nicht regeltreu“.
    static func lampen(regeln: Handelsregeln, stand: Regelpruefung.Tagesstand, verstoesse: [Regelverstoss],
                       trades: [Trade], waehrung: String) -> [Ampellampe] {
        var lampen: [Ampellampe] = []
        func hat(_ art: Regelverstoss.Art) -> Bool { verstoesse.contains { $0.art == art } }
        let verstoss = String(localized: "Verstoß")
        let frei = String(localized: "frei")

        if let grenze = regeln.maxTagesverlust {
            let verlust = max(0, -stand.netto)
            let stufe: Ampelstufe = hat(.tagesverlust) || verlust >= grenze ? .rot : verlust >= grenze * 7 / 10 ? .gelb : .gruen
            let status = stufe == .rot ? (hat(.tagesverlust) ? verstoss : String(localized: "Grenze erreicht"))
                : stufe == .gelb ? String(localized: "nah an der Grenze") : frei
            lampen.append(Ampellampe(id: "tagesverlust", titel: String(localized: "Tagesverlust"),
                                     wert: String(localized: "\(Format.geld(stand.netto, waehrung)) von −\(Format.betrag(grenze, waehrung))"),
                                     status: status, stufe: stufe))
        }
        if let grenze = regeln.maxTradesJeTag {
            let stufe: Ampelstufe = hat(.tradesJeTag) || stand.trades > grenze ? .rot : stand.trades == grenze ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "Grenze erreicht") : frei
            lampen.append(Ampellampe(id: "tradesJeTag", titel: String(localized: "Trades am Tag"),
                                     wert: String(localized: "\(stand.trades) von \(grenze)"), status: status, stufe: stufe))
        }
        if let grenze = regeln.stoppNachVerlusten {
            let stufe: Ampelstufe = hat(.stoppNachVerlusten) ? .rot : stand.verlusteInFolge >= grenze ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "Stopp erreicht") : frei
            lampen.append(Ampellampe(id: "verlusteInFolge", titel: String(localized: "Verluste in Folge"),
                                     wert: String(localized: "\(stand.verlusteInFolge) von \(grenze)"), status: status, stufe: stufe))
        }
        if let grenze = regeln.maxRisikoJeTrade {
            let risiken = trades.compactMap(\.risk)
            let groesstes = risiken.max() ?? 0
            let stufe: Ampelstufe = hat(.risikoJeTrade) ? .rot : groesstes >= grenze * 8 / 10 ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "nah an der Grenze") : frei
            let wert = risiken.isEmpty
                ? String(localized: "kein Stop, Risiko unbekannt")
                : String(localized: "größtes \(Format.betrag(groesstes, waehrung)) von \(Format.betrag(grenze, waehrung))")
            lampen.append(Ampellampe(id: "risiko", titel: String(localized: "Risiko je Trade"), wert: wert,
                                     status: status, stufe: stufe))
        }
        let manuell = verstoesse.filter { $0.art == .manuell }.count
        if manuell > 0 {
            lampen.append(Ampellampe(id: "manuell", titel: String(localized: "Journal"),
                                     wert: String(localized: "\(manuell) als nicht regeltreu markiert"),
                                     status: verstoss, stufe: .rot))
        }
        return lampen
    }
}

/// Regel-Ampel: Stand des letzten Handelstags im gewählten Zeitraum je Regel.
struct RegelAmpelKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        if let stand = modell.letzterTagesstand {
            let waehrung = modell.waehrung
            let amTag = modell.verstoesse.filter { $0.tag == stand.tag }
            let lampen = Ampellampe.lampen(regeln: modell.regeln, stand: stand, verstoesse: amTag,
                                           trades: modell.trades(eroeffnetAm: stand.tag), waehrung: waehrung)
            let betroffen = Set(amTag.map(\.trade)).count
            if !lampen.isEmpty {
                Karte("Regel-Ampel") {
                    Text("Handelstag \(Format.datum(stand.tag)): \(stand.trades) Trades, \(Format.geld(stand.netto, waehrung)) netto, \(betroffen) mit Verstoß.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                    ForEach(lampen) { lampe in
                        HStack(spacing: Abstand.raster * 2) {
                            Circle()
                                .fill(farbe(lampe.stufe))
                                .frame(width: 10, height: 10)
                            Text(verbatim: lampe.titel)
                                .foregroundStyle(thema.text)
                            Spacer()
                            Text(verbatim: lampe.wert)
                                .font(Schrift.tabelle)
                                .foregroundStyle(thema.textSchwach)
                            Text(verbatim: lampe.status)
                                .font(Schrift.beschriftung)
                                .foregroundStyle(farbe(lampe.stufe))
                                .frame(minWidth: 96, alignment: .trailing)
                        }
                    }
                    Text("Geprüft nach dem Import, nicht live. Regeln änderst du in den Einstellungen unter „Regeln“.")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
            }
        }
    }

    private func farbe(_ stufe: Ampelstufe) -> Color {
        switch stufe {
        case .gruen: thema.gewinn
        case .gelb: .orange
        case .rot: thema.verlust
        }
    }
}

/// Kapitalkurve und Disziplin-Kurve nebeneinander am Mac, untereinander am iPhone.
struct Kurvenpaar<Links: View, Rechts: View>: View {
    private let links: () -> Links
    private let rechts: () -> Rechts

    init(@ViewBuilder links: @escaping () -> Links, @ViewBuilder rechts: @escaping () -> Rechts) {
        self.links = links
        self.rechts = rechts
    }

    var body: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
            links()
            rechts()
        }
        #else
        VStack(spacing: Abstand.kachelAbstand) {
            links()
            rechts()
        }
        #endif
    }
}

/// Disziplin-Kurve (Vorbild Edgewonk „Tiltmeter“): je regeltreuem Trade +1, je Trade mit Verstoß −1.
struct DisziplinKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    private struct Punkt: Identifiable {
        let id: Int
        let wert: Int
        let regeltreu: Bool
    }

    var body: some View {
        let disziplin = modell.disziplin
        let waehrung = modell.waehrung
        let daten = [Punkt(id: 0, wert: 0, regeltreu: true)]
            + disziplin.punkte.enumerated().map { Punkt(id: $0.offset + 1, wert: $0.element.wert, regeltreu: $0.element.regeltreu) }
        Karte("Disziplin-Kurve") {
            Chart(daten) { punkt in
                if punkt.id == 0 {
                    RuleMark(y: .value("Null", 0))
                        .foregroundStyle(thema.linie)
                }
                LineMark(x: .value("Trade", punkt.id), y: .value("Disziplin", punkt.wert))
                    .foregroundStyle(thema.akzent)
                    .lineStyle(StrokeStyle(lineWidth: Diagramm.linie))
                if !punkt.regeltreu {
                    PointMark(x: .value("Trade", punkt.id), y: .value("Disziplin", punkt.wert))
                        .foregroundStyle(thema.verlust)
                        .symbolSize(Diagramm.marker * Diagramm.marker / 2)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(thema.linie)
                    AxisValueLabel().foregroundStyle(thema.textSchwach)
                }
            }
            .frame(height: 160)
            HStack(spacing: Abstand.raster * 2) {
                Kapsel(text: String(localized: "\(disziplin.regeltreu) regeltreu"))
                Kapsel(text: String(localized: "\(disziplin.verletzt) mit Verstoß"), betont: disziplin.verletzt > 0)
                if let quote = disziplin.quote {
                    Kapsel(text: String(localized: "\(Format.prozent(quote)) regeltreu"))
                }
            }
            Text("Netto regeltreu \(Format.geld(disziplin.nettoRegeltreu, waehrung)), mit Regelbruch \(Format.geld(disziplin.nettoVerletzt, waehrung)). Rote Punkte sind Trades mit Verstoß; gezählt im gewählten Zeitraum.")
                .font(Schrift.beschriftung)
                .foregroundStyle(thema.textSchwach)
            if !disziplin.genugDaten {
                StichprobenHinweis(anzahl: disziplin.punkte.count)
            }
        }
    }
}

/// Stand der Prop-Firm-Challenge über alle Trades des Kontos: Gewinnziel, Abstand zur Gesamtgrenze, Handelstage,
/// Konsistenz, Verstöße. Tagesverlust und Gesamtgrenze sind eine Näherung auf Schlusssalden (Stand-Doc 21).
struct ChallengeKarte: View {
    @Environment(AppModell.self) private var modell
    @Environment(\.thema) private var thema

    var body: some View {
        if let regeln = modell.regeln.propFirm, let ergebnis = modell.propFirmErgebnis {
            let waehrung = modell.waehrung
            let netto = ergebnis.saldo - regeln.startkapital
            Karte(verbatim: regeln.name) {
                HStack(alignment: .firstTextBaseline, spacing: Abstand.raster * 2) {
                    Text(verbatim: Format.betrag(ergebnis.saldo, waehrung))
                        .font(Schrift.zahlGross)
                        .foregroundStyle(thema.text)
                    Text("Saldo nach Schlusskursen, Start \(Format.betrag(regeln.startkapital, waehrung)), \(Format.geld(netto, waehrung))")
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                    Spacer()
                    Text(verbatim: statusText(ergebnis))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(statusFarbe(ergebnis))
                }
                if let ziel = regeln.gewinnziel {
                    Fortschrittsbalken(titel: "Gewinnziel", anteil: Format.double(netto / ziel),
                                       text: "\(Format.geld(netto, waehrung)) von +\(Format.betrag(ziel, waehrung))",
                                       farbe: netto >= ziel ? thema.gewinn : thema.akzent)
                }
                if let grenze = ergebnis.gesamtverlustGrenze, let maxVerlust = regeln.maxGesamtverlust {
                    let puffer = ergebnis.saldo - grenze
                    Fortschrittsbalken(titel: "Abstand zur Gesamtgrenze", anteil: Format.double(puffer / maxVerlust),
                                       text: String(localized: "\(Format.betrag(puffer, waehrung)) bis \(Format.betrag(grenze, waehrung))"),
                                       farbe: puffer <= maxVerlust * 3 / 10 ? thema.verlust : thema.akzent)
                }
                HStack(spacing: Abstand.raster * 2) {
                    Kapsel(text: handelstageText(ergebnis, regeln))
                    if let anteil = ergebnis.konsistenzAnteil {
                        Kapsel(text: konsistenzText(anteil, regeln), betont: regeln.konsistenzMaxAnteil.map { anteil > $0 } ?? false)
                    }
                    Kapsel(text: String(localized: "\(ergebnis.verstoesse.count) Verstöße"), betont: !ergebnis.verstoesse.isEmpty)
                }
                if !ergebnis.verstoesse.isEmpty {
                    Text(verbatim: verstoesseText(ergebnis.verstoesse))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.verlust)
                }
                Text("Näherung: Tagesverlust und Gesamtgrenze sind auf Schlusssalden geprüft, ohne Equity zwischen den Trades. Ein gemeldeter Verstoß ist sicher, ein fehlender nicht. Handelstag der Firma ab \(tageswechsel(regeln)).")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private func statusText(_ ergebnis: PropFirmPruefung.Ergebnis) -> String {
        switch ergebnis.bestanden {
        case .some(true): String(localized: "Bestanden")
        case .some(false): ergebnis.verstoesse.isEmpty ? String(localized: "Läuft") : String(localized: "Verstoß")
        case .none: ergebnis.verstoesse.isEmpty ? String(localized: "Ohne Verstoß") : String(localized: "Verstoß")
        }
    }

    private func statusFarbe(_ ergebnis: PropFirmPruefung.Ergebnis) -> Color {
        if !ergebnis.verstoesse.isEmpty { return thema.verlust }
        return ergebnis.bestanden == true ? thema.gewinn : thema.akzent
    }

    private func handelstageText(_ ergebnis: PropFirmPruefung.Ergebnis, _ regeln: PropFirmRegeln) -> String {
        if let mindestens = regeln.mindestHandelstage {
            return String(localized: "\(ergebnis.handelstage) von \(mindestens) Handelstagen")
        }
        return String(localized: "\(ergebnis.handelstage) Handelstage")
    }

    private func konsistenzText(_ anteil: Decimal, _ regeln: PropFirmRegeln) -> String {
        if let grenze = regeln.konsistenzMaxAnteil {
            return String(localized: "Bester Tag \(Format.prozent(anteil)), erlaubt \(Format.prozent(grenze))")
        }
        return String(localized: "Bester Tag \(Format.prozent(anteil))")
    }

    private func verstoesseText(_ verstoesse: [PropFirmPruefung.Verstoss]) -> String {
        let jeArt = Dictionary(grouping: verstoesse, by: \.art)
        return PropFirmPruefung.Art.allCases.compactMap { art in
            jeArt[art].map { "\(art.titel) \($0.count)" }
        }.joined(separator: " · ")
    }

    private func tageswechsel(_ regeln: PropFirmRegeln) -> String {
        let m = max(0, min(regeln.tageswechselMinuten, 24 * 60 - 1))
        return String(format: "%02ld:%02ld", m / 60, m % 60) + " " + regeln.zeitzone
    }
}

/// Schmaler Balken mit Beschriftung links und Wert rechts; `anteil` wird auf 0 bis 1 begrenzt.
struct Fortschrittsbalken: View {
    let titel: LocalizedStringKey
    let anteil: Double
    let text: String
    let farbe: Color
    @Environment(\.thema) private var thema

    var body: some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            HStack {
                Text(titel)
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
                Spacer()
                Text(verbatim: text)
                    .font(Schrift.beschriftung)
                    .monospacedDigit()
                    .foregroundStyle(thema.text)
            }
            GeometryReader { geometrie in
                ZStack(alignment: .leading) {
                    Capsule().fill(thema.flaeche2)
                    Capsule()
                        .fill(farbe)
                        .frame(width: geometrie.size.width * min(max(anteil, 0), 1))
                }
            }
            .frame(height: 8)
        }
    }
}

extension PropFirmPruefung.Art {
    var titel: String {
        switch self {
        case .tagesverlust: String(localized: "Tagesverlust")
        case .gesamtverlust: String(localized: "Gesamtgrenze")
        case .haltenUeberTageswechsel: String(localized: "Halten über den Tageswechsel")
        case .haltenUeberWochenende: String(localized: "Halten übers Wochenende")
        case .lotsJeTrade: String(localized: "Lots je Trade")
        case .ohneStop: String(localized: "Ohne Stop")
        default: rawValue
        }
    }
}
