import Foundation

/// Kennzahlen in R (Vielfache des geplanten Risikos), nur über Trades mit bekanntem Risiko (`Trade.risk`).
/// Gewinner und Verlierer nach Ergebnis netto wie in `Kennzahlen`; das Vorzeichen von R folgt dem Netto.
public struct RKennzahlen: Sendable, Equatable {
    public var anzahlMitR: Int
    public var anzahlGewinnerMitR: Int
    public var anzahlVerliererMitR: Int
    /// Ø R der Gewinner, positiv.
    public var durchschnittGewinnR: Decimal?
    /// Ø R der Verlierer, negativ.
    public var durchschnittVerlustR: Decimal?
    /// Ø R aller Trades mit Risiko (wie `Kennzahlen.erwartungswertR`).
    public var erwartungswertR: Decimal?
    /// Negativster R-Wert unter den Verlierern; `nil` ohne Verlierer mit R.
    public var groessterVerlustR: Decimal?
    /// Verlierer mit R unter −1: Verlust größer als geplant.
    public var verlusteUeber1R: Int
    /// `verlusteUeber1R` ÷ `anzahlVerliererMitR`; `nil` ohne Verlierer mit R.
    public var anteilVerlusteUeber1R: Decimal?

    public init(trades: [Trade]) {
        let mitR = trades.filter { $0.rMultiple != nil }
        let gewinne = mitR.filter { $0.outcome == .win }.compactMap(\.rMultiple)
        let verluste = mitR.filter { $0.outcome == .loss }.compactMap(\.rMultiple)
        let alle = mitR.compactMap(\.rMultiple)
        let summeGewinne: Decimal = gewinne.reduce(0, +)
        let summeVerluste: Decimal = verluste.reduce(0, +)
        let summeAlle: Decimal = alle.reduce(0, +)
        let ueber1R = verluste.filter { $0 < -1 }.count

        anzahlMitR = alle.count
        anzahlGewinnerMitR = gewinne.count
        anzahlVerliererMitR = verluste.count
        durchschnittGewinnR = gewinne.isEmpty ? nil : summeGewinne / Decimal(gewinne.count)
        durchschnittVerlustR = verluste.isEmpty ? nil : summeVerluste / Decimal(verluste.count)
        erwartungswertR = alle.isEmpty ? nil : summeAlle / Decimal(alle.count)
        groessterVerlustR = verluste.min()
        verlusteUeber1R = ueber1R
        anteilVerlusteUeber1R = verluste.isEmpty ? nil : Decimal(ueber1R) / Decimal(verluste.count)
    }
}

// MARK: - Histogramme

extension Tiefenanalyse {
    /// Klasse eines Histogramms, halboffen [untergrenze, obergrenze). `nil` heißt offen: Randklasse für alle
    /// Werte unter `−klassenJeSeite × breite` bzw. ab `klassenJeSeite × breite`.
    public struct Klasse: Sendable, Equatable {
        public var untergrenze: Decimal?
        public var obergrenze: Decimal?
        public var anzahl: Int
        public var tradeIDs: [Trade.ID]
    }

    public struct RVerteilung: Sendable, Equatable {
        public var breite: Decimal
        /// Lückenlos von der untersten bis zur obersten besetzten Klasse, leere Klassen dazwischen mit 0.
        public var klassen: [Klasse]
        /// Trades ohne bekanntes Risiko, in keiner Klasse.
        public var ohneRisiko: Int
    }

    public struct Betragsverteilung: Sendable, Equatable {
        public var breite: Decimal
        public var klassen: [Klasse]
    }

    /// Verteilung der R-Multiples, Standard in halben R: …, [−1,5; −1), [−1; −0,5), [−0,5; 0), …
    /// R wird vor der Einteilung auf 8 Nachkommastellen gerundet, damit Divisionsreste wie −1,000…01
    /// nicht in die Nachbarklasse fallen.
    public static func rVerteilung(_ trades: [Trade], breite: Decimal = Decimal(string: "0.5")!,
                                   klassenJeSeite: Int = 10) -> RVerteilung {
        let sortiert = nachSchluss(trades)
        var werte: [(Trade.ID, Decimal)] = []
        for t in sortiert {
            if let r = t.rMultiple { werte.append((t.id, r.gerundet(8))) }
        }
        let verteilt = klassen(werte, breite: breite, klassenJeSeite: klassenJeSeite)
        return RVerteilung(breite: breite, klassen: verteilt, ohneRisiko: trades.count - werte.count)
    }

    /// Verteilung der Ergebnisse netto in Betragsklassen.
    /// - Parameter breite: Klassenbreite in Kontowährung. Ohne Angabe die kleinste Stufe 1, 2 oder 5 × 10ⁿ,
    ///   die größer ist als der größte Betrag ÷ `klassenJeSeite`; so passen alle Werte ohne Randklasse.
    public static func betragsverteilung(_ trades: [Trade], breite: Decimal? = nil,
                                         klassenJeSeite: Int = 10) -> Betragsverteilung {
        let sortiert = nachSchluss(trades)
        let werte = sortiert.map { ($0.id, $0.netProfit) }
        let groesster = sortiert.map { abs($0.netProfit) }.max() ?? 0
        let schritt = breite ?? runderSchritt(ueber: groesster / Decimal(max(klassenJeSeite, 1)))
        return Betragsverteilung(breite: schritt,
                                 klassen: klassen(werte, breite: schritt, klassenJeSeite: klassenJeSeite))
    }

    /// Kleinste Zahl der Form 1, 2 oder 5 × 10ⁿ, die echt größer als `m` ist; 1 für `m <= 0`.
    static func runderSchritt(ueber m: Decimal) -> Decimal {
        guard m > 0 else { return 1 }
        var p: Decimal = 1
        while p <= m { p *= 10 }
        while p / 10 > m { p /= 10 }
        // Jetzt gilt p ÷ 10 <= m < p.
        let zehntel = p / 10
        if zehntel * 2 > m { return zehntel * 2 }
        if zehntel * 5 > m { return zehntel * 5 }
        return p
    }

    static func klassen(_ werte: [(Trade.ID, Decimal)], breite: Decimal, klassenJeSeite: Int) -> [Klasse] {
        guard !werte.isEmpty, breite > 0, klassenJeSeite > 0 else { return [] }
        let grenze = breite * Decimal(klassenJeSeite)
        var unten: [Trade.ID] = []
        var oben: [Trade.ID] = []
        var jeIndex: [Int: [Trade.ID]] = [:]
        for (id, wert) in werte {
            if wert < -grenze {
                unten.append(id)
            } else if wert >= grenze {
                oben.append(id)
            } else {
                jeIndex[abgerundet(wert / breite), default: []].append(id)
            }
        }
        var ergebnis: [Klasse] = []
        if !unten.isEmpty {
            ergebnis.append(Klasse(untergrenze: nil, obergrenze: -grenze, anzahl: unten.count, tradeIDs: unten))
        }
        if let kleinster = jeIndex.keys.min(), let groesster = jeIndex.keys.max() {
            let von = unten.isEmpty ? kleinster : -klassenJeSeite
            let bis = oben.isEmpty ? groesster : klassenJeSeite - 1
            for i in von...bis {
                let ids = jeIndex[i] ?? []
                ergebnis.append(Klasse(untergrenze: Decimal(i) * breite, obergrenze: Decimal(i + 1) * breite,
                                       anzahl: ids.count, tradeIDs: ids))
            }
        }
        if !oben.isEmpty {
            ergebnis.append(Klasse(untergrenze: grenze, obergrenze: nil, anzahl: oben.count, tradeIDs: oben))
        }
        return ergebnis
    }

    /// Größte ganze Zahl <= `wert`. Unabhängig davon, ob `.down` auf der Plattform zur Null oder nach unten rundet.
    static func abgerundet(_ wert: Decimal) -> Int {
        var eingang = wert
        var r = Decimal()
        NSDecimalRound(&r, &eingang, 0, .down)
        if r > wert { r -= 1 }
        return NSDecimalNumber(decimal: r).intValue
    }
}

// MARK: - Anteile für Kreisdiagramme

extension Tiefenanalyse {
    /// Ein Stück eines Kreis- oder Donut-Diagramms. Alle Werte nicht negativ; `anteil` ist `wert` ÷ Summe aller
    /// Werte der Liste (0 bis 1, zusammen 1). Eine Liste mit Summe 0 (keine Trades) ist leer.
    public struct Anteil: Sendable, Equatable {
        public enum Art: Sendable, Equatable {
            /// Benannter Eintrag; `schluessel` gilt.
            case eintrag
            /// Alles außerhalb der ersten Einträge (Top N); `schluessel` ist leer.
            case rest
            /// Ohne Zuordnung: Trades ohne Setup bzw. Verluste ohne Fehlermuster; `schluessel` ist leer.
            case ohne
        }

        /// Ergebnis „gewinner“/„verlierer“/„breakeven“, Richtung „buy“/„sell“, Symbol, Setup-Name oder
        /// `Fehlermuster.rawValue`.
        public var schluessel: String
        public var wert: Decimal
        public var anteil: Decimal
        public var art: Art
        public var tradeIDs: [Trade.ID]
    }

    /// Gewinner, Verlierer und Breakeven nach Anzahl, immer in dieser Reihenfolge; leer ohne Trades.
    public static func anteileErgebnis(_ trades: [Trade]) -> [Anteil] {
        let sortiert = nachSchluss(trades)
        let gewinner = sortiert.filter { $0.outcome == .win }.map(\.id)
        let verlierer = sortiert.filter { $0.outcome == .loss }.map(\.id)
        let breakeven = sortiert.filter { $0.outcome == .breakeven }.map(\.id)
        let roh = [eintrag("gewinner", gewinner), eintrag("verlierer", verlierer), eintrag("breakeven", breakeven)]
        return anteile(roh)
    }

    /// Long („buy“) und Short („sell“) nach Anzahl, immer in dieser Reihenfolge; leer ohne Trades.
    public static func anteileRichtung(_ trades: [Trade]) -> [Anteil] {
        let sortiert = nachSchluss(trades)
        let kauf = sortiert.filter { $0.side == .buy }.map(\.id)
        let verkauf = sortiert.filter { $0.side == .sell }.map(\.id)
        return anteile([eintrag(Side.buy.rawValue, kauf), eintrag(Side.sell.rawValue, verkauf)])
    }

    /// Anzahl je Symbol: die `top` häufigsten (bei Gleichstand nach Name), danach ein Eintrag `rest`.
    public static func anteileSymbole(_ trades: [Trade], top: Int = 5) -> [Anteil] {
        let sortiert = nachSchluss(trades)
        return anteile(topMitRest(sortiert.map { ($0.id, $0.symbol) }, top: top))
    }

    /// Anzahl je Setup wie bei den Symbolen; Trades ohne Setup als eigener Eintrag `ohne` am Ende.
    /// - Parameter setups: Setup-Name je Trade-ID (aus Journal oder Checkliste); leere Namen zählen als ohne.
    public static func anteileSetups(_ trades: [Trade], setups: [Trade.ID: String], top: Int = 5) -> [Anteil] {
        let sortiert = nachSchluss(trades)
        var mit: [(Trade.ID, String)] = []
        var ohne: [Trade.ID] = []
        for t in sortiert {
            if let s = setups[t.id], !s.isEmpty { mit.append((t.id, s)) } else { ohne.append(t.id) }
        }
        var eintraege = topMitRest(mit, top: top)
        if !ohne.isEmpty { eintraege.append(Roh(schluessel: "", wert: Decimal(ohne.count), art: .ohne, ids: ohne)) }
        return anteile(eintraege)
    }

    /// Verlustsumme (Betrag) je Fehlermuster. Nur Muster, die Regelbruch eines Trades sind (`istRegelbruch`).
    /// Jeder Verlierer zählt genau einmal: beim ersten seiner Muster in der Reihenfolge von
    /// `Fehlermuster.allCases`; so ergeben die Anteile zusammen 1. Verlierer ohne Muster als `ohne` am Ende.
    /// Muster nach Wert absteigend; Einträge mit Wert 0 fehlen.
    public static func anteileVerlusteJeMuster(_ trades: [Trade], befunde: [Befund]) -> [Anteil] {
        var musterJeTrade: [Trade.ID: Fehlermuster] = [:]
        for muster in Fehlermuster.allCases where muster.istRegelbruch {
            for b in befunde where b.muster == muster {
                for id in b.trades where musterJeTrade[id] == nil { musterJeTrade[id] = muster }
            }
        }
        var jeMuster: [Fehlermuster: [Trade]] = [:]
        var ohne: [Trade] = []
        for t in nachSchluss(trades) where t.outcome == .loss {
            if let m = musterJeTrade[t.id] { jeMuster[m, default: []].append(t) } else { ohne.append(t) }
        }
        var eintraege: [Roh] = []
        for muster in Fehlermuster.allCases {
            guard let teil = jeMuster[muster] else { continue }
            let betrag: Decimal = -teil.map(\.netProfit).reduce(0, +)
            eintraege.append(Roh(schluessel: muster.rawValue, wert: betrag, art: .eintrag, ids: teil.map(\.id)))
        }
        // Stabil: bei gleichem Wert bleibt die Reihenfolge der Muster.
        eintraege = eintraege.enumerated()
            .sorted { ($1.element.wert, $0.offset) < ($0.element.wert, $1.offset) }
            .map(\.element)
        if !ohne.isEmpty {
            let betrag: Decimal = -ohne.map(\.netProfit).reduce(0, +)
            eintraege.append(Roh(schluessel: "", wert: betrag, art: .ohne, ids: ohne.map(\.id)))
        }
        return anteile(eintraege)
    }

    struct Roh {
        var schluessel: String
        var wert: Decimal
        var art: Anteil.Art
        var ids: [Trade.ID]
    }

    static func eintrag(_ schluessel: String, _ ids: [Trade.ID]) -> Roh {
        Roh(schluessel: schluessel, wert: Decimal(ids.count), art: .eintrag, ids: ids)
    }

    static func topMitRest(_ paare: [(Trade.ID, String)], top: Int) -> [Roh] {
        var jeSchluessel: [String: [Trade.ID]] = [:]
        for (id, s) in paare { jeSchluessel[s, default: []].append(id) }
        let reihenfolge = jeSchluessel.keys.sorted { a, b in
            let na = jeSchluessel[a]?.count ?? 0
            let nb = jeSchluessel[b]?.count ?? 0
            return na != nb ? na > nb : a < b
        }
        let n = max(top, 0)
        var ergebnis = reihenfolge.prefix(n).map { eintrag($0, jeSchluessel[$0] ?? []) }
        // Rest in der Reihenfolge der Eingabe (nach Schlusszeit), nicht nach Gruppen.
        let gezeigt = Set(reihenfolge.prefix(n))
        let rest = paare.filter { !gezeigt.contains($0.1) }.map { $0.0 }
        if !rest.isEmpty { ergebnis.append(Roh(schluessel: "", wert: Decimal(rest.count), art: .rest, ids: rest)) }
        return ergebnis
    }

    static func anteile(_ roh: [Roh]) -> [Anteil] {
        let summe: Decimal = roh.map(\.wert).reduce(0, +)
        guard summe > 0 else { return [] }
        return roh.map { Anteil(schluessel: $0.schluessel, wert: $0.wert, anteil: $0.wert / summe, art: $0.art,
                                tradeIDs: $0.ids) }
    }
}
