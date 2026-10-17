import Foundation
import TradingCore

/// Was die Regel-Ampel außer dem Tagesstand braucht (E2 bis E6, Tim 17.10.2026). Leer heißt: wie vor 0.29.0,
/// nur Beträge, keine Monats-, Setup- und Positionsgrenzen.
struct Ampelbezug {
    /// Kontostand zu Beginn des Handelstags, Bezug der Prozentgrenzen; `nil` ohne eingetragenen Kontostand.
    var kontostand: Decimal?
    /// Realisiert netto im Kalendermonat des Handelstags bis zu dessen Ende.
    var monatsnetto: Decimal = 0
    /// Kontostand zu Beginn dieses Monats.
    var monatsstand: Decimal?
    /// Trades je Setup am Handelstag, nur Karten mit Grenze (E4).
    var setupTrades: [Setupzaehlung] = []
    /// Mindestens eine Karte hat eine Haltedauer (E5).
    var haltedauerAktiv = false
    /// Jetzt offene Positionen (E6) mit dem Kontostand von heute; sie gehören zu keinem Handelstag.
    var offene: [OffenerTrade] = []
    var standHeute: Decimal?
    /// Verstöße der jetzt offenen Positionen (offene Positionen, offenes Risiko, Haltedauer bis jetzt).
    var offeneVerstoesse: [Regelverstoss] = []

    /// Trades eines Setups an einem Tag gegen die Grenze seiner Karte.
    struct Setupzaehlung: Equatable {
        var setup: String
        var anzahl: Int
        var grenze: Int
    }
}

extension Ampellampe {
    /// Lampen der Regeln aus 0.29.0: Monatsverlust, Trades je Setup, Haltedauer, offene Positionen und Risiko, dazu
    /// ein Hinweis, wenn Prozentgrenzen ohne Kontostand nicht geprüft werden können.
    static func erweiterteLampen(regeln: Handelsregeln, verstoesse: [Regelverstoss], waehrung: String,
                                 bezug: Ampelbezug) -> [Ampellampe] {
        var lampen: [Ampellampe] = []
        let verstoss = String(localized: "Verstoß")
        let frei = String(localized: "frei")
        func hat(_ art: Regelverstoss.Art) -> Bool {
            verstoesse.contains { $0.art == art } || bezug.offeneVerstoesse.contains { $0.art == art }
        }

        if let grenze = Handelsregeln.grenze(betrag: regeln.maxMonatsverlust, prozent: regeln.maxMonatsverlustProzent,
                                             stand: bezug.monatsstand) {
            let verlust = max(0, -bezug.monatsnetto)
            let stufe: Ampelstufe = hat(.monatsverlust) || verlust >= grenze ? .rot : verlust >= grenze * 7 / 10 ? .gelb : .gruen
            let status = stufe == .rot ? (hat(.monatsverlust) ? verstoss : String(localized: "Grenze erreicht"))
                : stufe == .gelb ? String(localized: "nah an der Grenze") : frei
            lampen.append(Ampellampe(id: "monatsverlust", titel: String(localized: "Monatsverlust"),
                                     wert: String(localized: "\(Format.geld(bezug.monatsnetto, waehrung)) von −\(Format.betrag(grenze, waehrung))"),
                                     status: status, stufe: stufe))
        }
        for zaehlung in bezug.setupTrades {
            let stufe: Ampelstufe = zaehlung.anzahl > zaehlung.grenze ? .rot : zaehlung.anzahl == zaehlung.grenze ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "Grenze erreicht") : frei
            lampen.append(Ampellampe(id: "setup-" + Setup.schluessel(zaehlung.setup),
                                     titel: String(localized: "Trades am Tag mit \(zaehlung.setup)"),
                                     wert: String(localized: "\(zaehlung.anzahl) von \(zaehlung.grenze)"),
                                     status: status, stufe: stufe))
        }
        if bezug.haltedauerAktiv {
            let betroffen = Set((verstoesse + bezug.offeneVerstoesse).filter { $0.art == .haltedauer }.map(\.trade)).count
            lampen.append(Ampellampe(id: "haltedauer", titel: String(localized: "Haltedauer"),
                                     wert: betroffen == 0 ? String(localized: "alle im Rahmen")
                                         : String(localized: "\(betroffen) zu lange gehalten"),
                                     status: betroffen == 0 ? frei : verstoss, stufe: betroffen == 0 ? .gruen : .rot))
        }
        lampen += offeneLampen(regeln: regeln, waehrung: waehrung, bezug: bezug, hat: hat)
        let prozentGesetzt = regeln.maxTagesverlustProzent != nil || regeln.maxRisikoJeTradeProzent != nil
            || regeln.maxMonatsverlustProzent != nil || regeln.maxOffenesRisikoProzent != nil
        if prozentGesetzt && regeln.kontostand == nil {
            lampen.append(Ampellampe(id: "kontostand", titel: String(localized: "Prozentgrenzen"),
                                     wert: String(localized: "kein Kontostand eingetragen"),
                                     status: String(localized: "nicht geprüft"), stufe: .gelb))
        }
        return lampen
    }

    /// Offene Positionen und offenes Risiko jetzt (E6); die neue Position zählt mit, also ist die vierte bei
    /// Grenze 3 ein Verstoß.
    private static func offeneLampen(regeln: Handelsregeln, waehrung: String, bezug: Ampelbezug,
                                     hat: (Regelverstoss.Art) -> Bool) -> [Ampellampe] {
        var lampen: [Ampellampe] = []
        let verstoss = String(localized: "Verstoß")
        let frei = String(localized: "frei")
        if let grenze = regeln.maxOffenePositionen {
            let anzahl = bezug.offene.count
            let stufe: Ampelstufe = anzahl > grenze || hat(.offenePositionen) ? .rot : anzahl == grenze ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "Grenze erreicht") : frei
            lampen.append(Ampellampe(id: "offenePositionen", titel: String(localized: "Offene Positionen"),
                                     wert: String(localized: "\(anzahl) offen von \(grenze)"), status: status, stufe: stufe))
        }
        if let grenze = Handelsregeln.grenze(betrag: regeln.maxOffenesRisiko, prozent: regeln.maxOffenesRisikoProzent,
                                             stand: bezug.standHeute) {
            let summe = bezug.offene.compactMap(\.risiko).reduce(0, +)
            let ohneRisiko = bezug.offene.filter { $0.risiko == nil }.count
            let stufe: Ampelstufe = summe > grenze || hat(.offenesRisiko) ? .rot : summe >= grenze * 8 / 10 ? .gelb : .gruen
            let status = stufe == .rot ? verstoss : stufe == .gelb ? String(localized: "nah an der Grenze") : frei
            var wert = String(localized: "\(Format.betrag(summe, waehrung)) von \(Format.betrag(grenze, waehrung))")
            if ohneRisiko > 0 { wert += " · " + String(localized: "\(ohneRisiko) ohne Stop und Risiko") }
            lampen.append(Ampellampe(id: "offenesRisiko", titel: String(localized: "Offenes Risiko"), wert: wert,
                                     status: status, stufe: stufe))
        }
        return lampen
    }
}
