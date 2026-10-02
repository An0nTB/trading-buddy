import Foundation

/// Buchgewinn offener Positionen zu einem neuen Kurs (Paket Kurse offener Trades).
/// Was offen ist, weiß die App nur aus dem letzten Import; der Kurs kommt von außen (TradingQuotes).
public enum OffeneBewertung {
    public struct Ergebnis: Sendable, Equatable {
        /// Ticket (MetaTrader) oder Kennung der Ausführung.
        public var id: String
        public var symbol: String
        public var seite: Side
        /// Lots (MetaTrader) oder Stück.
        public var menge: Decimal
        public var einstieg: Decimal
        public var kurs: Decimal
        /// Ergebnis aus der Kursbewegung, ohne Kosten. `nil`, wenn der Wert je Kurspunkt unbekannt ist.
        public var brutto: Decimal?
        /// Bisher angefallene Kosten (Kommission, Swap, Kaufgebühr), als Kassenwirkung meist negativ.
        public var kosten: Decimal
        /// Brutto plus Kosten.
        public var netto: Decimal? { brutto.map { $0 + kosten } }
        /// Wert einer Kurseinheit in Kontowährung.
        public var wertJePunkt: Decimal?
        /// Wert je Punkt stammt aus einem kleinen Auszugsergebnis (unter 0,50) und ist durch die
        /// Rundung auf Cent um mehr als 1 % unsicher.
        public var unsicher: Bool
        /// Währung des Ergebnisses: Kontowährung bei MetaTrader (`nil`, steht nicht im Auszug), sonst die der Ausführung.
        public var waehrung: String?
    }

    /// MetaTrader: Wert je Kurspunkt aus dem Auszug selbst (Kursergebnis ÷ Kursbewegung, wie bei `Trade.risk`),
    /// deshalb ohne Kontraktgrößen. Näherung bei Paaren, deren Gegenwährung nicht die Kontowährung ist:
    /// Der Umrechnungskurs zum Auszugszeitpunkt bleibt stehen.
    public static func bewerte(_ p: OpenPosition, kurs: Decimal) -> Ergebnis {
        let alteBewegung = bewegung(p.side, von: p.openPrice, nach: p.currentPrice)
        let wertJePunkt: Decimal? = alteBewegung == 0 ? nil : p.profit / alteBewegung
        let neueBewegung = bewegung(p.side, von: p.openPrice, nach: kurs)
        let brutto = wertJePunkt.map { (neueBewegung * $0).gerundet(2) }
        let unsicher = wertJePunkt != nil && abs(p.profit) < Decimal(string: "0.5")!
        return Ergebnis(id: p.ticket, symbol: p.symbol, seite: p.side, menge: p.lots, einstieg: p.openPrice,
                        kurs: kurs, brutto: brutto, kosten: p.commission + p.swap,
                        wertJePunkt: wertJePunkt, unsicher: unsicher, waehrung: nil)
    }

    /// Offener Kauf aus der Positionsbildung (Trade Republic, Scalable, Krypto): Stück × Kurs gegen den Einstand.
    /// Kurs in der Währung der Ausführung; umrechnen muss der Aufrufer vorher.
    public static func bewerte(_ kauf: Ausfuehrung, kurs: Decimal) -> Ergebnis {
        let einstand = -kauf.betrag
        let brutto = (kauf.menge * kurs - einstand).gerundet(2)
        let einstieg = kauf.menge == 0 ? kauf.preis : einstand / kauf.menge
        return Ergebnis(id: kauf.id, symbol: kauf.name.isEmpty ? kauf.kennung : kauf.name, seite: .buy,
                        menge: kauf.menge, einstieg: einstieg, kurs: kurs, brutto: brutto,
                        kosten: kauf.gebuehr, wertJePunkt: kauf.menge, unsicher: false, waehrung: kauf.waehrung)
    }

    /// Summe der Nettoergebnisse; `nil`, wenn eines fehlt oder Währungen gemischt sind.
    public static func summe(_ ergebnisse: [Ergebnis]) -> Decimal? {
        let waehrungen = Set(ergebnisse.map { $0.waehrung ?? "" })
        guard waehrungen.count <= 1 else { return nil }
        var gesamt: Decimal = 0
        for e in ergebnisse {
            guard let netto = e.netto else { return nil }
            gesamt += netto
        }
        return gesamt
    }

    /// Kursbewegung in Gewinnrichtung: Kauf gewinnt bei steigendem, Verkauf bei fallendem Kurs.
    static func bewegung(_ seite: Side, von einstieg: Decimal, nach kurs: Decimal) -> Decimal {
        seite == .buy ? kurs - einstieg : einstieg - kurs
    }
}
