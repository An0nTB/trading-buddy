import Foundation

/// Monatsbericht (Doc 18, F11): bündelt, was andere Teile schon rechnen, für ein PDF oder zum
/// Weitergeben. Rechnet nichts neu; das PDF baut die App. Ein Trade zählt zum Monat, in dem er
/// geschlossen wurde, wie in `Auswertung`.
public struct Monatsbericht: Sendable {
    public var jahr: Int
    public var monat: Int
    /// Kennzahlen, Vergleich mit dem Vormonat, Kapitalverlauf und Fehlermuster des Monats.
    public var auswertung: Auswertung
    /// Regelverstöße an Trades des Monats, nach Eröffnung.
    public var regelverstoesse: [Regelverstoss]
    /// Verstöße gegen Prop-Firm-Regeln an Trades des Monats; leer ohne `regeln.propFirm`.
    public var propFirmVerstoesse: [PropFirmPruefung.Verstoss]
    /// Eigene und Prop-Firm-Verstöße zusammen; ein Trade zählt einmal.
    public var disziplin: Disziplin
    /// Stärkste Unterschiede laut Muster-Finder; leer unter `Kennzahlen.mindestanzahl` Trades.
    public var muster: [Muster]
    /// Ziele, deren Zeitraum den Monat berührt, nach Beginn.
    public var ziele: [Reviewziel]
    /// Steuer-Orientierung: Summen je Topf vom Jahresbeginn bis Monatsende (kein Steuerbescheid).
    public var steuerBisMonatsende: [Topfsumme]
    public var planwirkung: Planwirkung
    public var verpasste: VerpassteAuswertung
    public var beste: [Trade]
    public var schlechteste: [Trade]

    /// `nil` bei ungültigem Monat.
    /// - Parameters:
    ///   - trades: alle Trades des Kontos, auch außerhalb des Monats (Vormonat, Steuerjahr).
    ///   - manuell: Trades, die im Journal als „nicht regeltreu“ markiert sind.
    ///   - kontowaehrung: für die Steuer-Summen; andere Währungen nur mit `kurse`.
    public init?(trades: [Trade], jahr: Int, monat: Int, zeitzone: TimeZone, kontowaehrung: String,
                 regeln: Handelsregeln = Handelsregeln(), manuell: Set<String> = [],
                 ziele: [Reviewziel] = [], notizen: [Tagesnotiz] = [], verpasst: [VerpassterTrade] = [],
                 geloeschteOrders: [Date] = [], kurse: Referenzkurse? = nil, musterAnzahl: Int = 3,
                 topAnzahl: Int = 3) {
        guard let zeitraum = Zeitspanne.monat(jahr: jahr, monat: monat, zeitzone: zeitzone) else { return nil }
        self.jahr = jahr
        self.monat = monat
        auswertung = Auswertung(trades: trades, geloeschteOrders: geloeschteOrders, zeitraum: zeitraum,
                                zeitzone: zeitzone)
        let imMonat = auswertung.trades
        let ids = Set(imMonat.map(\.id))
        regelverstoesse = Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: zeitzone, manuell: manuell)
            .filter { ids.contains($0.trade) }
        propFirmVerstoesse = regeln.propFirm.map { PropFirmPruefung.pruefe(trades, regeln: $0).verstoesse }?
            .filter { ids.contains($0.trade) } ?? []
        disziplin = Disziplin(trades: imMonat, verstoesse: regelverstoesse, propFirm: propFirmVerstoesse)
        muster = Array(MusterFinder.finde(imMonat, zeitzone: zeitzone).prefix(musterAnzahl))
        self.ziele = ziele.filter { $0.von < zeitraum.bis && $0.bis > zeitraum.von }.sorted { $0.von < $1.von }
        steuerBisMonatsende = Steuerorientierung.toepfe(trades.filter { $0.closeTime < zeitraum.bis },
                                                        kontowaehrung: kontowaehrung, jahr: jahr, kurse: kurse)
        planwirkung = Planwirkung(trades: imMonat, notizen: notizen, zeitzone: zeitzone)
        verpasste = VerpassteAuswertung(verpasst.filter { zeitraum.enthaelt($0.zeit) })
        beste = auswertung.beste(topAnzahl)
        schlechteste = auswertung.schlechteste(topAnzahl)
    }

    /// Anzahl der Verstöße einer Art im Monat.
    public func anzahl(_ art: Regelverstoss.Art) -> Int {
        regelverstoesse.filter { $0.art == art }.count
    }

    /// Trades ohne Uhrzeit (Trade Republic, Scalable); das PDF nennt sie, weil Stunden und Haltedauer
    /// für sie fehlen.
    public var tradesOhneUhrzeit: Int { auswertung.trades.filter(\.nurDatum).count }
}
