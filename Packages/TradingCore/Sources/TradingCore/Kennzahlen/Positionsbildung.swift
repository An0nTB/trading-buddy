import Foundation

/// Bildet aus Käufen und Verkäufen abgeschlossene Trades nach FIFO: Jeder Verkauf schließt
/// die ältesten offenen Käufe derselben Kennung, so wie das deutsche Steuerrecht für
/// Wertpapiere im Depot rechnet. Kosten und Steuern der Käufe gehen anteilig in den Trade ein.
/// Splits ändern die Stückzahl der offenen Käufe, der Einstand bleibt gleich.
public enum Positionsbildung {
    public struct Ergebnis: Sendable, Equatable {
        /// Ein Trade je Verkauf, nach Verkaufszeit.
        public var trades: [Trade]
        /// Noch offene Käufe mit ihrer Restmenge, nach Kaufzeit.
        public var offen: [Ausfuehrung]
        /// Verkaufte Stücke ohne Kauf in den Daten, meist weil der Kauf vor dem Exportzeitraum liegt.
        /// Ohne Einstand gibt es kein Ergebnis; die App bittet um einen längeren Export.
        public var ohneBestand: [Ausfuehrung]
    }

    private enum Ereignis {
        case split(Kapitalmassnahme), kauf(Ausfuehrung), verkauf(Ausfuehrung)

        var zeit: Date {
            switch self {
            case .split(let m): m.zeit
            case .kauf(let a), .verkauf(let a): a.zeit
            }
        }

        /// Bei gleicher Zeit (Buchungen nur mit Datum): erst Split, dann Kauf, dann Verkauf.
        var rang: Int {
            switch self {
            case .split: 0
            case .kauf: 1
            case .verkauf: 2
            }
        }
    }

    public static func bilde(_ ausfuehrungen: [Ausfuehrung], kapitalmassnahmen: [Kapitalmassnahme] = []) -> Ergebnis {
        let splits = kapitalmassnahmen.filter { $0.art == .split }.map { Ereignis.split($0) }
        let handel = ausfuehrungen.map { $0.seite == .buy ? Ereignis.kauf($0) : Ereignis.verkauf($0) }
        let ereignisse = (splits + handel).enumerated()
            .sorted { ($0.element.zeit, $0.element.rang, $0.offset) < ($1.element.zeit, $1.element.rang, $1.offset) }
            .map { $0.element }
        var bestand: [String: [Ausfuehrung]] = [:]
        var trades: [Trade] = []
        var ohneBestand: [Ausfuehrung] = []
        for ereignis in ereignisse {
            switch ereignis {
            case .split(let m):
                bestand[m.kennung] = teile(bestand[m.kennung] ?? [], zusatz: m.menge)
            case .kauf(let a):
                bestand[a.kennung, default: []].append(a)
            case .verkauf(let a):
                var rest = a.menge
                var lose: [(kauf: Ausfuehrung, menge: Decimal)] = []
                var kaeufe = bestand[a.kennung] ?? []
                while rest > 0, let kauf = kaeufe.first {
                    let menge = min(rest, kauf.menge)
                    lose.append((kauf: kauf, menge: menge))
                    rest -= menge
                    if menge == kauf.menge { kaeufe.removeFirst() } else { kaeufe[0] = anteil(kauf, kauf.menge - menge) }
                }
                bestand[a.kennung] = kaeufe
                if rest < a.menge { trades.append(trade(verkauf: rest == 0 ? a : anteil(a, a.menge - rest), lose: lose)) }
                if rest > 0 { ohneBestand.append(anteil(a, rest)) }
            }
        }
        let offen = bestand.values.flatMap { $0 }.sorted { ($0.zeit, $0.id) < ($1.zeit, $1.id) }
        return Ergebnis(trades: trades, offen: offen, ohneBestand: ohneBestand)
    }

    /// Ausführung mit kleinerer Menge; Betrag, Gebühr und Steuer im gleichen Verhältnis.
    static func anteil(_ a: Ausfuehrung, _ menge: Decimal) -> Ausfuehrung {
        var teil = a
        let faktor = menge / a.menge
        teil.menge = menge
        teil.betrag = a.betrag * faktor
        teil.gebuehr = a.gebuehr * faktor
        teil.steuer = a.steuer * faktor
        return teil
    }

    /// Split: Stückzahl je Kauf im Verhältnis neu zu alt, gerundet auf zehn Stellen wie beim Broker.
    static func teile(_ kaeufe: [Ausfuehrung], zusatz: Decimal) -> [Ausfuehrung] {
        let summe = kaeufe.map(\.menge).reduce(0, +)
        guard summe > 0 else { return kaeufe }
        let faktor = (summe + zusatz) / summe
        return kaeufe.map { kauf in
            var neu = kauf
            neu.menge = (kauf.menge * faktor).gerundet(10)
            neu.preis = (kauf.preis / faktor).gerundet(10)
            return neu
        }
    }

    private static func trade(verkauf v: Ausfuehrung, lose: [(kauf: Ausfuehrung, menge: Decimal)]) -> Trade {
        let anteile = lose.map { anteil($0.kauf, $0.menge) }
        let einstand = anteile.map(\.betrag).reduce(0, +)
        return Trade(id: v.id, symbol: v.name.isEmpty ? v.kennung : v.name, side: .buy, lots: v.menge,
                     openTime: anteile.map(\.zeit).min() ?? v.zeit, closeTime: v.zeit,
                     openPrice: -einstand / v.menge, closePrice: v.betrag / v.menge,
                     commission: anteile.map(\.gebuehr).reduce(0, +) + v.gebuehr,
                     profit: v.betrag + einstand,
                     taxes: anteile.map(\.steuer).reduce(0, +) + v.steuer,
                     produktart: v.produktart != .unbekannt ? v.produktart : anteile.first?.produktart ?? .unbekannt)
    }
}
