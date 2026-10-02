import Foundation

/// Bericht über eine beliebige Zeitspanne (Tim 02.10.2026, Frage 4; Doc 47): Woche, Monat oder frei
/// gewählte Tage, etwa als Grundlage der wöchentlichen Auswertung mit Henry. Bündelt, was andere Teile
/// schon rechnen; `Monatsbericht` ist ein Zeitraumbericht über einen Kalendermonat. Ein Trade zählt zur
/// Spanne, in der er geschlossen wurde, wie in `Auswertung`.
public struct Zeitraumbericht: Sendable {
    public var zeitraum: Zeitspanne
    /// Kennzahlen, Vergleich mit dem gleich langen Zeitraum davor, Kapitalverlauf und Fehlermuster.
    public var auswertung: Auswertung
    /// Ergebnis je Kalendertag mit mindestens einem geschlossenen Trade, nach Datum.
    public var tage: [Tagesergebnis]
    /// Regelverstöße an Trades der Spanne, nach Eröffnung.
    public var regelverstoesse: [Regelverstoss]
    /// Verstöße gegen Prop-Firm-Regeln an Trades der Spanne; leer ohne `regeln.propFirm`.
    public var propFirmVerstoesse: [PropFirmPruefung.Verstoss]
    /// Eigene und Prop-Firm-Verstöße zusammen; ein Trade zählt einmal.
    public var disziplin: Disziplin
    /// Stärkste Unterschiede laut Muster-Finder; leer unter `Kennzahlen.mindestanzahl` Trades.
    public var muster: [Muster]
    /// Ziele, deren Zeitraum die Spanne berührt, nach Beginn.
    public var ziele: [Reviewziel]
    /// Jahr des letzten Tags der Spanne; danach richtet sich die Steuer-Orientierung.
    public var steuerjahr: Int
    /// Steuer-Orientierung: Summen je Topf vom Beginn des Steuerjahrs bis zum Ende der Spanne
    /// (kein Steuerbescheid).
    public var steuerBisEnde: [Topfsumme]
    public var planwirkung: Planwirkung
    public var verpasste: VerpassteAuswertung
    public var beste: [Trade]
    public var schlechteste: [Trade]
    /// Trades der Spanne in fremder Währung, die zum Referenzkurs in die Kontowährung umgerechnet wurden
    /// (Näherung, Doc 40 W2); alle Summen oben rechnen damit.
    public var umgerechnet: Int
    /// Trades der Spanne in fremder Währung ohne Kurs: fehlen in allen Summen außer der Steuer.
    public var ohneKurs: Int
    /// Fremde Währungen der Trades in der Spanne, sortiert.
    public var fremdwaehrungen: [String]

    /// Netto und Anzahl der an einem Tag geschlossenen Trades, in Kontowährung.
    public struct Tagesergebnis: Sendable, Equatable {
        public var tag: Journaltag
        public var anzahl: Int
        public var netto: Decimal
    }

    /// - Parameters:
    ///   - trades: alle Trades des Kontos, auch außerhalb der Spanne (Vorzeitraum, Steuerjahr).
    ///   - zeitraum: etwa `Zeitspanne.woche(mit:zeitzone:)` oder `Zeitspanne.kalenderwoche(jahr:woche:zeitzone:)`.
    ///   - manuell: Trades, die im Journal als „nicht regeltreu“ markiert sind.
    ///   - kontowaehrung: alle Summen lauten darauf; Trades in anderer Währung rechnet `kurse` um
    ///     (`Waehrungsangleich`), ohne Kurs fehlen sie und zählen in `ohneKurs`.
    public init(trades: [Trade], zeitraum: Zeitspanne, zeitzone: TimeZone, kontowaehrung: String,
                regeln: Handelsregeln = Handelsregeln(), manuell: Set<String> = [],
                ziele: [Reviewziel] = [], notizen: [Tagesnotiz] = [], verpasst: [VerpassterTrade] = [],
                geloeschteOrders: [Date] = [], kurse: Referenzkurse? = nil, musterAnzahl: Int = 3,
                topAnzahl: Int = 3) {
        self.zeitraum = zeitraum
        let angleich = Waehrungsangleich(trades, kontowaehrung: kontowaehrung, kurse: kurse, zeitzone: zeitzone)
        let alle = angleich.trades
        auswertung = Auswertung(trades: alle, geloeschteOrders: geloeschteOrders, zeitraum: zeitraum,
                                zeitzone: zeitzone)
        let imZeitraum = auswertung.trades
        let ids = Set(imZeitraum.map(\.id))
        tage = Self.tage(imZeitraum, zeitzone: zeitzone)
        regelverstoesse = Regelpruefung.pruefe(alle, regeln: regeln, zeitzone: zeitzone, manuell: manuell)
            .filter { ids.contains($0.trade) }
        propFirmVerstoesse = regeln.propFirm.map { PropFirmPruefung.pruefe(alle, regeln: $0).verstoesse }?
            .filter { ids.contains($0.trade) } ?? []
        disziplin = Disziplin(trades: imZeitraum, verstoesse: regelverstoesse, propFirm: propFirmVerstoesse)
        muster = Array(MusterFinder.finde(imZeitraum, zeitzone: zeitzone).prefix(musterAnzahl))
        self.ziele = ziele.filter { $0.von < zeitraum.bis && $0.bis > zeitraum.von }.sorted { $0.von < $1.von }
        let jahr = Journaltag(zeitraum.bis.addingTimeInterval(-1), zeitzone: zeitzone).jahr
        steuerjahr = jahr
        steuerBisEnde = Steuerorientierung.toepfe(trades.filter { $0.closeTime < zeitraum.bis },
                                                  kontowaehrung: kontowaehrung, jahr: jahr, kurse: kurse)
        planwirkung = Planwirkung(trades: imZeitraum, notizen: notizen, zeitzone: zeitzone)
        verpasste = VerpassteAuswertung(verpasst.filter { zeitraum.enthaelt($0.zeit) })
        beste = auswertung.beste(topAnzahl)
        schlechteste = auswertung.schlechteste(topAnzahl)
        let original = Dictionary(trades.map { ($0.id, $0.waehrung(kontowaehrung: kontowaehrung)) },
                                  uniquingKeysWith: { erste, _ in erste })
        let umgerechnetImZeitraum = imZeitraum.filter { angleich.umgerechnet.contains($0.id) }
        let ohneKursImZeitraum = angleich.ohneKurs.filter { zeitraum.enthaelt($0.closeTime) }
        umgerechnet = umgerechnetImZeitraum.count
        ohneKurs = ohneKursImZeitraum.count
        fremdwaehrungen = Set((umgerechnetImZeitraum + ohneKursImZeitraum).compactMap { original[$0.id] }).sorted()
    }

    /// Anzahl der Verstöße einer Art in der Spanne.
    public func anzahl(_ art: Regelverstoss.Art) -> Int {
        regelverstoesse.filter { $0.art == art }.count
    }

    /// Trades ohne Uhrzeit (Trade Republic, Scalable); ein Bericht nennt sie, weil Stunden und Haltedauer
    /// für sie fehlen.
    public var tradesOhneUhrzeit: Int { auswertung.trades.filter(\.nurDatum).count }

    private static func tage(_ trades: [Trade], zeitzone: TimeZone) -> [Tagesergebnis] {
        let nachTag = Dictionary(grouping: trades) { Journaltag($0.closeTime, zeitzone: zeitzone) }
        var ergebnis: [Tagesergebnis] = []
        for (tag, liste) in nachTag {
            let netto = liste.reduce(Decimal(0)) { $0 + $1.netProfit }
            ergebnis.append(Tagesergebnis(tag: tag, anzahl: liste.count, netto: netto))
        }
        return ergebnis.sorted { $0.tag < $1.tag }
    }
}
