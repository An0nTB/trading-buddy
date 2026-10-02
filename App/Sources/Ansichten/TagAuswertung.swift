import SwiftUI
import TradingCore

/// Die zwei Auswertungskarten unter der Tagesseite: Planwirkung über alle Handelstage des Kontos und
/// verpasste Trades im Monat des gewählten Tages.
struct TagAuswertungen: View {
    let tagModell: TagModell
    @Environment(AppModell.self) private var modell

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Abstand.kachelAbstand, alignment: .top)],
                  alignment: .leading, spacing: Abstand.kachelAbstand) {
            PlanwirkungKarte(wirkung: tagModell.planwirkung(modell.alleTrades), waehrung: modell.waehrung)
            VerpassteAuswertungKarte(auswertung: tagModell.verpassteAuswertung,
                                     monat: tagModell.tag.beginn(in: tagModell.zeitzone))
        }
    }
}

/// Tage mit Plan vor dem ersten Trade gegen Tage ohne; unter 10 Tagen je Seite nur beschreibend.
struct PlanwirkungKarte: View {
    let wirkung: Planwirkung?
    let waehrung: String
    @Environment(\.thema) private var thema

    var body: some View {
        Karte("Planwirkung") {
            if let wirkung {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand) {
                    seite(titel: String(localized: "Mit Plan · \(wirkung.tageMitPlan) Tage"),
                          jeTag: wirkung.nettoJeTagMitPlan, trades: wirkung.tradesMitPlan)
                    seite(titel: String(localized: "Ohne Plan · \(wirkung.tageOhnePlan) Tage"),
                          jeTag: wirkung.nettoJeTagOhnePlan, trades: wirkung.tradesOhnePlan)
                }
                if !wirkung.genugDaten {
                    Kapsel(text: String(localized: "Unter \(Planwirkung.mindestTage) Tagen je Seite: beschreibt nur, belegt nichts"))
                }
                if wirkung.tageUnklar > 0 {
                    Text(verbatim: unklarText(wirkung.tageUnklar))
                        .font(Schrift.beschriftung)
                        .foregroundStyle(thema.textSchwach)
                }
                Text("Zählt, ob der Plan vor dem ersten Trade des Tages gespeichert war. Tage ohne Trades fallen heraus. Grundlage sind alle Trades des gewählten Kontos.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            } else {
                Text("Noch keine Trades im gewählten Konto.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    /// Tage nur mit Trades ohne Uhrzeit und Plan vom selben Tag (TradingCore 0.17.0): zählen auf keiner Seite.
    private func unklarText(_ tage: Int) -> String {
        let grund = String(localized: "Trades ohne Uhrzeit, Plan am selben Tag gespeichert.")
        return tage == 1
            ? String(localized: "1 Tag unklar: \(grund) Er zählt auf keiner Seite.")
            : String(localized: "\(tage) Tage unklar: \(grund) Sie zählen auf keiner Seite.")
    }

    private func seite(titel: String, jeTag: Decimal?, trades: Int) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: titel)
                .font(Schrift.beschriftung)
                .textCase(.uppercase)
                .foregroundStyle(thema.kachelTitel)
            Text(verbatim: jeTag.map { Format.geld($0, waehrung) } ?? "–")
                .font(Schrift.zahlGross)
                .foregroundStyle(jeTag.map(thema.vorzeichen) ?? thema.textSchwach)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: String(localized: "je Tag · \(trades) Trades"))
                .font(Schrift.beschriftung)
                .monospacedDigit()
                .foregroundStyle(thema.textSchwach)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Verpasste Trades im Monat: Anzahl, gewollt verpasst, entgangen in R, je Grund als Balken.
struct VerpassteAuswertungKarte: View {
    let auswertung: VerpassteAuswertung
    let monat: Date
    @Environment(\.thema) private var thema

    var body: some View {
        Karte(verbatim: String(localized: "Verpasste Trades · \(Format.monat(monat))")) {
            if auswertung.anzahl == 0 {
                Text("In diesem Monat noch keine verpassten Trades erfasst.")
                    .font(Schrift.fliesstext)
                    .foregroundStyle(thema.textSchwach)
            } else {
                HStack(alignment: .top, spacing: Abstand.kachelAbstand * 2) {
                    zahl(String(localized: "Anzahl"), "\(auswertung.anzahl)")
                    zahl(String(localized: "Gewollt"), "\(auswertung.gewollt)")
                    zahl(String(localized: "Entgangen"), Format.r(auswertung.entgangenR))
                }
                ForEach(auswertung.jeGrund, id: \.grund) { zeile in
                    grundZeile(zeile)
                }
                Text("Regelsperre zählt als gewollt verpasst und nicht zum entgangenen Ergebnis. Entgangen ist die Summe deiner Schätzungen in R.")
                    .font(Schrift.beschriftung)
                    .foregroundStyle(thema.textSchwach)
            }
        }
    }

    private func zahl(_ titel: String, _ wert: String) -> some View {
        VStack(alignment: .leading, spacing: Abstand.raster) {
            Text(verbatim: titel)
                .font(Schrift.beschriftung)
                .textCase(.uppercase)
                .foregroundStyle(thema.kachelTitel)
            Text(verbatim: wert)
                .font(Schrift.zahlGross)
                .foregroundStyle(thema.text)
        }
    }

    private func grundZeile(_ zeile: VerpassteAuswertung.JeGrund) -> some View {
        let gewollt = zeile.grund == .regelSperre
        let anteil = CGFloat(zeile.anzahl) / CGFloat(max(auswertung.anzahl, 1))
        return VStack(alignment: .leading, spacing: Abstand.raster) {
            HStack {
                Text(verbatim: gewollt ? String(localized: "Regelsperre (gewollt)") : zeile.grund.titel)
                    .foregroundStyle(thema.text)
                Spacer()
                Text(verbatim: wertText(zeile, gewollt: gewollt))
                    .font(Schrift.tabelle)
                    .foregroundStyle(gewollt ? thema.textSchwach : thema.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(thema.flaeche2)
                    Capsule()
                        .fill(gewollt ? thema.textSchwach : thema.akzent)
                        .frame(width: geo.size.width * anteil)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    private func wertText(_ zeile: VerpassteAuswertung.JeGrund, gewollt: Bool) -> String {
        if gewollt { return String(localized: "\(zeile.anzahl) · zählt nicht") }
        guard zeile.mitSchaetzung > 0 else { return "\(zeile.anzahl)" }
        return "\(zeile.anzahl) · \(Format.r(zeile.summeR))"
    }
}
