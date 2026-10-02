import Foundation

/// Prüft abgeschlossene Trades gegen die eigenen Handelsregeln (Doc 18, F1).
/// Tagesgrenze ist der Kalendertag der Eröffnung in der Zeitzone des Nutzers, wie bei „Überhandeln“.
/// Gezählt wird nur, was zum Eröffnungszeitpunkt schon feststand: Verluste, die vorher am selben Tag
/// geschlossen wurden. Ein Trade kann mehrere Regeln zugleich verletzen.
public enum Regelpruefung {
    public static func pruefe(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                              manuell: Set<String> = []) -> [Regelverstoss] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let nachEroeffnung = trades.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
        let jeTag = Dictionary(grouping: nachEroeffnung) { kalender.startOfDay(for: $0.openTime) }
        var verstoesse: [Regelverstoss] = []

        for tag in jeTag.keys.sorted() {
            let tagesTrades = jeTag[tag]!
            for (nummer, t) in tagesTrades.enumerated() {
                var arten: [Regelverstoss.Art] = []
                let vorher = geschlossenVor(t, am: tag, in: tagesTrades, kalender: kalender)
                if let max = regeln.maxTradesJeTag, nummer >= max { arten.append(.tradesJeTag) }
                if let max = regeln.maxTagesverlust {
                    let netto = vorher.map(\.netProfit).reduce(0, +)
                    if netto <= -max { arten.append(.tagesverlust) }
                }
                if let n = regeln.stoppNachVerlusten, n > 0, verlusteInFolge(vorher) >= n {
                    arten.append(.stoppNachVerlusten)
                }
                if let max = regeln.maxRisikoJeTrade, (t.risk ?? 0) > max || t.netProfit < -max {
                    arten.append(.risikoJeTrade)
                }
                if manuell.contains(t.id) { arten.append(.manuell) }
                verstoesse += arten.map { Regelverstoss(art: $0, trade: t.id, tag: tag) }
            }
        }
        return verstoesse
    }

    /// Stand eines Tages für die Ampel in der Übersicht: was bis Tagesende verbraucht war.
    public struct Tagesstand: Sendable, Equatable {
        public var tag: Date
        public var trades: Int
        public var netto: Decimal
        /// Verluste in Folge am Tagesende.
        public var verlusteInFolge: Int
        public var verstoesse: Int
    }

    /// Tagesstand je Handelstag, sortiert nach Tag.
    public static func tagesstaende(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                                    manuell: Set<String> = []) -> [Tagesstand] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let verstoesse = pruefe(trades, regeln: regeln, zeitzone: zeitzone, manuell: manuell)
        let jeTag = Dictionary(grouping: trades) { kalender.startOfDay(for: $0.openTime) }
        return jeTag.keys.sorted().map { tag in
            let tagesTrades = jeTag[tag]!
            let nachSchluss = tagesTrades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
            let betroffen = Set(verstoesse.filter { $0.tag == tag }.map(\.trade))
            return Tagesstand(tag: tag, trades: tagesTrades.count, netto: tagesTrades.map(\.netProfit).reduce(0, +),
                              verlusteInFolge: verlusteInFolge(nachSchluss), verstoesse: betroffen.count)
        }
    }

    /// Trades desselben Tages, die vor der Eröffnung von `t` geschlossen wurden, nach Schlusszeit.
    static func geschlossenVor(_ t: Trade, am tag: Date, in tagesTrades: [Trade], kalender: Calendar) -> [Trade] {
        tagesTrades
            .filter { $0.id != t.id && $0.closeTime <= t.openTime && kalender.startOfDay(for: $0.closeTime) == tag }
            .sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
    }

    /// Verluste am Ende der Folge, ohne Unterbrechung durch einen Gewinner oder Breakeven.
    static func verlusteInFolge(_ nachSchluss: [Trade]) -> Int {
        nachSchluss.reversed().prefix { $0.outcome == .loss }.count
    }
}
