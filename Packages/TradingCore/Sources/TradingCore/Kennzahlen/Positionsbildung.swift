import Foundation

/// Bildet aus Käufen und Verkäufen abgeschlossene Trades nach FIFO: Jeder Verkauf schließt
/// die ältesten offenen Käufe derselben Kennung, so wie das deutsche Steuerrecht für
/// Wertpapiere im Depot rechnet. Kosten und Steuern der Käufe gehen anteilig in den Trade ein.
/// Leerverkäufe bieten diese Broker nicht an; ein Verkauf ohne Bestand bricht deshalb ab.
public enum Positionsbildung {
    public struct Ergebnis: Sendable, Equatable {
        /// Ein Trade je Verkauf, nach Verkaufszeit.
        public var trades: [Trade]
        /// Noch offene Käufe mit ihrer Restmenge, nach Kaufzeit.
        public var offen: [Ausfuehrung]
    }

    public static func bilde(_ ausfuehrungen: [Ausfuehrung]) throws -> Ergebnis {
        var bestand: [String: [Ausfuehrung]] = [:]
        var trades: [Trade] = []
        for a in ausfuehrungen.sorted(by: { ($0.zeit, $0.id) < ($1.zeit, $1.id) }) {
            if a.seite == .buy {
                bestand[a.kennung, default: []].append(a)
                continue
            }
            var rest = a.menge
            var lose: [(kauf: Ausfuehrung, menge: Decimal)] = []
            var kaeufe = bestand[a.kennung] ?? []
            while rest > 0, let kauf = kaeufe.first {
                let menge = min(rest, kauf.menge)
                lose.append((kauf: kauf, menge: menge))
                rest -= menge
                if menge == kauf.menge { kaeufe.removeFirst() } else { kaeufe[0] = anteil(kauf, kauf.menge - menge) }
            }
            guard rest == 0 else { throw CSVImportFehler.verkaufOhneBestand(kennung: a.kennung, id: a.id) }
            bestand[a.kennung] = kaeufe
            trades.append(trade(verkauf: a, lose: lose))
        }
        let offen = bestand.values.flatMap { $0 }.sorted { ($0.zeit, $0.id) < ($1.zeit, $1.id) }
        return Ergebnis(trades: trades, offen: offen)
    }

    /// Kauf mit kleinerer Menge; Betrag, Gebühr und Steuer im gleichen Verhältnis.
    static func anteil(_ kauf: Ausfuehrung, _ menge: Decimal) -> Ausfuehrung {
        var teil = kauf
        let faktor = menge / kauf.menge
        teil.menge = menge
        teil.betrag = kauf.betrag * faktor
        teil.gebuehr = kauf.gebuehr * faktor
        teil.steuer = kauf.steuer * faktor
        return teil
    }

    private static func trade(verkauf v: Ausfuehrung, lose: [(kauf: Ausfuehrung, menge: Decimal)]) -> Trade {
        let anteile = lose.map { anteil($0.kauf, $0.menge) }
        let einstand = anteile.map(\.betrag).reduce(0, +)
        return Trade(id: v.id, symbol: v.name.isEmpty ? v.kennung : v.name, side: .buy, lots: v.menge,
                     openTime: anteile.map(\.zeit).min() ?? v.zeit, closeTime: v.zeit,
                     openPrice: -einstand / v.menge, closePrice: v.betrag / v.menge,
                     commission: anteile.map(\.gebuehr).reduce(0, +) + v.gebuehr,
                     profit: v.betrag + einstand,
                     taxes: anteile.map(\.steuer).reduce(0, +) + v.steuer)
    }
}
