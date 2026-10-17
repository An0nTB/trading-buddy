import Foundation

/// Eine noch offene Position für die Regelprüfung (E5, E6): aus dem Auszug oder von Hand eingetragen.
public struct OffenerTrade: Sendable, Equatable {
    /// Kennung wie bei den Trades (Ticket), für Verstöße und `setups`.
    public var id: String
    public var openTime: Date
    public var nurDatum: Bool
    /// Risiko in Kontowährung wie `Trade.risk` (Stop, sonst geplantes Risiko); `nil` zählt beim offenen Risiko nicht.
    public var risiko: Decimal?
    /// Gemeinsame Kennung mit geschlossenen Teilen (`Trade.positionsschluessel`); ohne Angabe eigene Position.
    public var positionsschluessel: String?

    public init(id: String, openTime: Date, nurDatum: Bool = false, risiko: Decimal? = nil,
                positionsschluessel: String? = nil) {
        self.id = id
        self.openTime = openTime
        self.nurDatum = nurDatum
        self.risiko = risiko
        self.positionsschluessel = positionsschluessel
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
    /// Risiko ist die Summe der dann noch offenen Teile. Alle Teile einer Position bekommen den Verstoß.
    static func offenVerstoesse(_ nachEroeffnung: [Trade], offene: [OffenerTrade], regeln: Handelsregeln,
                                kalender: Calendar, ohneBetrag: Set<String>,
                                stand: (Date) -> Decimal?) -> [Regelverstoss] {
        guard regeln.maxOffenePositionen != nil || regeln.maxOffenesRisiko != nil
                || regeln.maxOffenesRisikoProzent != nil else { return [] }
        struct Teil {
            var schluss: Date?
            var nurDatum: Bool
            var risiko: Decimal

            func offen(bei zeit: Date, nurDatum: Bool, kalender: Calendar) -> Bool {
                guard let schluss else { return true }
                if self.nurDatum || nurDatum {
                    return Trade.tagesbeginn(schluss, nurDatum: self.nurDatum, kalender: kalender)
                        >= Trade.tagesbeginn(zeit, nurDatum: nurDatum, kalender: kalender)
                }
                return schluss > zeit
            }
        }
        struct Position {
            var ids: [String]
            var openTime: Date
            var nurDatum: Bool
            var teile: [Teil]
        }
        var positionen: [Position] = []
        var index: [String: Int] = [:]
        for t in nachEroeffnung {
            let risiko = ohneBetrag.contains(t.id) ? 0 : (t.risk ?? 0)
            let teil = Teil(schluss: t.closeTime, nurDatum: t.nurDatum, risiko: risiko)
            if let i = index[t.positionsschluessel] {
                positionen[i].ids.append(t.id)
                positionen[i].teile.append(teil)
            } else {
                index[t.positionsschluessel] = positionen.count
                positionen.append(Position(ids: [t.id], openTime: t.openTime, nurDatum: t.nurDatum,
                                           teile: [teil]))
            }
        }
        for o in offene {
            let schluessel = o.positionsschluessel ?? "offen:\(o.id)"
            let teil = Teil(schluss: nil, nurDatum: o.nurDatum, risiko: ohneBetrag.contains(o.id) ? 0 : (o.risiko ?? 0))
            // Nur einen Rest mit geschlossenen Teilen verbinden; getrennte offene Käufe bleiben eigenständig.
            if let i = index.removeValue(forKey: schluessel) {
                positionen[i].ids.append(o.id)
                positionen[i].teile.append(teil)
            } else {
                positionen.append(Position(ids: [o.id], openTime: o.openTime, nurDatum: o.nurDatum, teile: [teil]))
            }
        }
        positionen.sort { ($0.openTime, $0.ids[0]) < ($1.openTime, $1.ids[0]) }

        var verstoesse: [Regelverstoss] = []
        for (n, p) in positionen.enumerated() {
            // Sortiert nach Eröffnung: Alle davor sind nicht später eröffnet; offen ist, wer erst danach schloss.
            let offeneTeile = positionen[..<n].map { vorher in
                vorher.teile.filter { $0.offen(bei: p.openTime, nurDatum: p.nurDatum, kalender: kalender) }
            }.filter { !$0.isEmpty }
            let tag = Trade.tagesbeginn(p.openTime, nurDatum: p.nurDatum, kalender: kalender)
            var arten: [Regelverstoss.Art] = []
            if let max = regeln.maxOffenePositionen, offeneTeile.count >= max { arten.append(.offenePositionen) }
            if let max = Handelsregeln.grenze(betrag: regeln.maxOffenesRisiko, prozent: regeln.maxOffenesRisikoProzent,
                                              stand: stand(tag)),
               (offeneTeile.flatMap { $0 } + p.teile).map(\.risiko).reduce(0, +) > max {
                arten.append(.offenesRisiko)
            }
            for art in arten { verstoesse += p.ids.map { Regelverstoss(art: art, trade: $0, tag: tag) } }
        }
        return verstoesse
    }
}
