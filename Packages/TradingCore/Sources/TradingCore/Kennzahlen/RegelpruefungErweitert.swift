import Foundation

/// Eine noch offene Position für die Regelprüfung (E5, E6): aus dem Auszug oder von Hand eingetragen.
public struct OffenerTrade: Sendable, Equatable {
    /// Kennung wie bei den Trades (Ticket), für Verstöße und `setups`.
    public var id: String
    public var openTime: Date
    public var nurDatum: Bool
    /// Risiko in Kontowährung wie `Trade.risk` (Stop, sonst geplantes Risiko); `nil` zählt beim offenen Risiko nicht.
    public var risiko: Decimal?

    public init(id: String, openTime: Date, nurDatum: Bool = false, risiko: Decimal? = nil) {
        self.id = id
        self.openTime = openTime
        self.nurDatum = nurDatum
        self.risiko = risiko
    }
}

extension Regelpruefung {
    /// Verletzt eine Position, offen von `von` bis `bis`, die Haltedauer der Karte? „Gleicher Tag“: Schluss an einem
    /// anderen Kalendertag als die Eröffnung. „Kein Wochenende“: über mehrere Tage und dabei ein Samstag oder
    /// Sonntag; Freitag bis Montag ist damit ein Verstoß, Donnerstag bis Freitag nicht.
    static func verletzt(_ haltedauer: Setup.Haltedauer, von: Date, bis: Date, nurDatum: Bool,
                         kalender: Calendar) -> Bool {
        let beginn = Trade.tagesbeginn(von, nurDatum: nurDatum, kalender: kalender)
        let ende = Trade.tagesbeginn(bis, nurDatum: nurDatum, kalender: kalender)
        guard ende > beginn else { return false }
        switch haltedauer {
        case .gleicherTag:
            return true
        case .keinWochenende:
            var tag = beginn
            for _ in 0..<8 {
                if [1, 7].contains(kalender.component(.weekday, from: tag)) { return true } // Sonntag, Samstag
                guard let naechster = kalender.date(byAdding: .day, value: 1, to: tag), naechster <= ende else {
                    return false
                }
                tag = naechster
            }
            return true
        }
    }

    /// Monatsverlust (E3): Ein Trade verstößt, wenn bei seiner Eröffnung der realisierte Nettoverlust im selben
    /// Kalendermonat die Grenze schon erreicht hatte. Gezählt wird wie beim Tagesverlust nur, was sicher vorher
    /// geschlossen war; der Monat zählt nach dem Schlusstag.
    static func monatsverstoesse(_ nachEroeffnung: [Trade], regeln: Handelsregeln, kalender: Calendar,
                                 ohneBetrag: Set<String>, stand: (Date) -> Decimal?) -> [Regelverstoss] {
        guard regeln.maxMonatsverlust != nil || regeln.maxMonatsverlustProzent != nil else { return [] }
        func monat(_ tag: Date) -> Date { kalender.dateInterval(of: .month, for: tag)!.start }
        let geschlossenJeMonat = Dictionary(grouping: nachEroeffnung.filter { !ohneBetrag.contains($0.id) }) {
            monat($0.schlusstag(kalender))
        }
        var verstoesse: [Regelverstoss] = []
        for t in nachEroeffnung {
            let tag = t.eroeffnungstag(kalender)
            let beginn = monat(tag)
            guard let max = Handelsregeln.grenze(betrag: regeln.maxMonatsverlust,
                                                 prozent: regeln.maxMonatsverlustProzent, stand: stand(beginn))
            else { continue }
            let netto = (geschlossenJeMonat[beginn] ?? []).filter { $0.sicherGeschlossen(vor: t, kalender: kalender) }
                .map(\.netProfit).reduce(0, +)
            if netto <= -max { verstoesse.append(Regelverstoss(art: .monatsverlust, trade: t.id, tag: tag)) }
        }
        return verstoesse
    }

    /// Offene Positionen und offenes Risiko (E6) beim Einstieg: Gezählt werden die Positionen, die vorher eröffnet
    /// wurden und zu diesem Zeitpunkt noch offen waren, dazu die neue. Teilverkäufe sind eine Position; ihr
    /// Risiko ist die Summe der Teile. Alle Teile einer Position bekommen den Verstoß.
    static func offenVerstoesse(_ nachEroeffnung: [Trade], offene: [OffenerTrade], regeln: Handelsregeln,
                                kalender: Calendar, ohneBetrag: Set<String>,
                                stand: (Date) -> Decimal?) -> [Regelverstoss] {
        guard regeln.maxOffenePositionen != nil || regeln.maxOffenesRisiko != nil
                || regeln.maxOffenesRisikoProzent != nil else { return [] }
        struct Position {
            var ids: [String]
            var openTime: Date
            var nurDatum: Bool
            var schluss: Date?
            var risiko: Decimal
        }
        var positionen: [Position] = []
        var index: [String: Int] = [:]
        for t in nachEroeffnung {
            let risiko = ohneBetrag.contains(t.id) ? 0 : (t.risk ?? 0)
            if let i = index[t.positionsschluessel] {
                positionen[i].ids.append(t.id)
                positionen[i].schluss = max(positionen[i].schluss!, t.closeTime)
                positionen[i].risiko += risiko
            } else {
                index[t.positionsschluessel] = positionen.count
                positionen.append(Position(ids: [t.id], openTime: t.openTime, nurDatum: t.nurDatum,
                                           schluss: t.closeTime, risiko: risiko))
            }
        }
        positionen += offene.map { Position(ids: [$0.id], openTime: $0.openTime, nurDatum: $0.nurDatum, schluss: nil,
                                            risiko: $0.risiko ?? 0) }
        positionen.sort { ($0.openTime, $0.ids[0]) < ($1.openTime, $1.ids[0]) }

        var verstoesse: [Regelverstoss] = []
        for (n, p) in positionen.enumerated() {
            // Sortiert nach Eröffnung: Alle davor sind nicht später eröffnet; offen ist, wer erst danach schloss.
            let offenDabei = positionen[..<n].filter { ($0.schluss ?? .distantFuture) > p.openTime }
            let tag = Trade.tagesbeginn(p.openTime, nurDatum: p.nurDatum, kalender: kalender)
            var arten: [Regelverstoss.Art] = []
            if let max = regeln.maxOffenePositionen, offenDabei.count >= max { arten.append(.offenePositionen) }
            if let max = Handelsregeln.grenze(betrag: regeln.maxOffenesRisiko, prozent: regeln.maxOffenesRisikoProzent,
                                              stand: stand(tag)),
               offenDabei.map(\.risiko).reduce(p.risiko, +) > max {
                arten.append(.offenesRisiko)
            }
            for art in arten { verstoesse += p.ids.map { Regelverstoss(art: art, trade: $0, tag: tag) } }
        }
        return verstoesse
    }
}
