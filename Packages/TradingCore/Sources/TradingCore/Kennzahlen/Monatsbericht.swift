import Foundation

/// Monatsbericht (Doc 18, F11): Zeitraumbericht über einen Kalendermonat, für ein PDF oder zum
/// Weitergeben. Rechnet nichts neu; das PDF baut die App. Ein Trade zählt zum Monat, in dem er
/// geschlossen wurde, wie in `Auswertung`.
public struct Monatsbericht: Sendable {
    public var jahr: Int
    public var monat: Int
    /// Der Bericht über den Monat; die Werte unten lesen ihn (seit 0.20.0, Doc 47).
    public var bericht: Zeitraumbericht

    /// Kennzahlen, Vergleich mit dem Vormonat, Kapitalverlauf und Fehlermuster des Monats.
    public var auswertung: Auswertung { bericht.auswertung }
    /// Regelverstöße an Trades des Monats, nach Eröffnung.
    public var regelverstoesse: [Regelverstoss] { bericht.regelverstoesse }
    /// Verstöße gegen Prop-Firm-Regeln an Trades des Monats; leer ohne `regeln.propFirm`.
    public var propFirmVerstoesse: [PropFirmPruefung.Verstoss] { bericht.propFirmVerstoesse }
    /// Eigene und Prop-Firm-Verstöße zusammen; ein Trade zählt einmal.
    public var disziplin: Disziplin { bericht.disziplin }
    /// Stärkste Unterschiede laut Muster-Finder; leer unter `Kennzahlen.mindestanzahl` Trades.
    public var muster: [Muster] { bericht.muster }
    /// Ziele, deren Zeitraum den Monat berührt, nach Beginn.
    public var ziele: [Reviewziel] { bericht.ziele }
    /// Steuer-Orientierung: Summen je Topf vom Jahresbeginn bis Monatsende (kein Steuerbescheid).
    public var steuerBisMonatsende: [Topfsumme] { bericht.steuerBisEnde }
    public var planwirkung: Planwirkung { bericht.planwirkung }
    public var verpasste: VerpassteAuswertung { bericht.verpasste }
    public var beste: [Trade] { bericht.beste }
    public var schlechteste: [Trade] { bericht.schlechteste }
    /// Trades des Monats in fremder Währung, die zum Referenzkurs in die Kontowährung umgerechnet wurden
    /// (Näherung, Doc 40 W2); alle Summen oben rechnen damit.
    public var umgerechnet: Int { bericht.umgerechnet }
    /// Trades des Monats in fremder Währung ohne Kurs: fehlen in allen Summen außer der Steuer.
    public var ohneKurs: Int { bericht.ohneKurs }
    /// Fremde Währungen der Trades im Monat, sortiert.
    public var fremdwaehrungen: [String] { bericht.fremdwaehrungen }

    /// `nil` bei ungültigem Monat.
    /// - Parameters:
    ///   - trades: alle Trades des Kontos, auch außerhalb des Monats (Vormonat, Steuerjahr).
    ///   - manuell: Trades, die im Journal als „nicht regeltreu“ markiert sind.
    ///   - kontowaehrung: alle Summen lauten darauf; Trades in anderer Währung rechnet `kurse` um
    ///     (`Waehrungsangleich`), ohne Kurs fehlen sie und zählen in `ohneKurs`.
    public init?(trades: [Trade], jahr: Int, monat: Int, zeitzone: TimeZone, kontowaehrung: String,
                 regeln: Handelsregeln = Handelsregeln(), manuell: Set<String> = [],
                 ziele: [Reviewziel] = [], notizen: [Tagesnotiz] = [], verpasst: [VerpassterTrade] = [],
                 geloeschteOrders: [Date] = [], kurse: Referenzkurse? = nil, musterAnzahl: Int = 3,
                 topAnzahl: Int = 3) {
        guard let zeitraum = Zeitspanne.monat(jahr: jahr, monat: monat, zeitzone: zeitzone) else { return nil }
        self.jahr = jahr
        self.monat = monat
        bericht = Zeitraumbericht(trades: trades, zeitraum: zeitraum, zeitzone: zeitzone,
                                  kontowaehrung: kontowaehrung, regeln: regeln, manuell: manuell, ziele: ziele,
                                  notizen: notizen, verpasst: verpasst, geloeschteOrders: geloeschteOrders,
                                  kurse: kurse, musterAnzahl: musterAnzahl, topAnzahl: topAnzahl)
    }

    /// Anzahl der Verstöße einer Art im Monat.
    public func anzahl(_ art: Regelverstoss.Art) -> Int { bericht.anzahl(art) }

    /// Trades ohne Uhrzeit (Trade Republic, Scalable); das PDF nennt sie, weil Stunden und Haltedauer
    /// für sie fehlen.
    public var tradesOhneUhrzeit: Int { bericht.tradesOhneUhrzeit }
}
