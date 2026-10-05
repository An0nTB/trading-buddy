import Foundation

/// Prüft abgeschlossene Trades gegen die eigenen Handelsregeln (Doc 18, F1).
/// Tagesgrenze ist der Kalendertag der Eröffnung in der Zeitzone des Nutzers, wie bei „Überhandeln“.
/// Gezählt wird nur, was zum Eröffnungszeitpunkt schon feststand: Ergebnisse, die vorher am selben Tag
/// geschlossen wurden, auch aus Positionen, die an einem früheren Tag eröffnet wurden.
/// Ein Trade kann mehrere Regeln zugleich verletzen. Teilverkäufe einer Position zählen bei
/// „Trades je Tag“ und „Verluste in Folge“ als ein Trade (`positionsschluessel`).
public enum Regelpruefung {
    /// Prüft alle Trades eines Währungsangleichs: auch die ohne Kurs, deren Beträge aber nicht (G1).
    public static func pruefe(_ angleich: Waehrungsangleich, regeln: Handelsregeln, zeitzone: TimeZone,
                              manuell: Set<String> = []) -> [Regelverstoss] {
        pruefe(angleich.trades + angleich.ohneKurs, regeln: regeln, zeitzone: zeitzone, manuell: manuell,
               ohneBetrag: angleich.ohneKursIDs)
    }

    /// - Parameter ohneBetrag: Trades, deren Beträge nicht in Kontowährung vorliegen (`Waehrungsangleich.ohneKurs`).
    ///   Sie zählen für „Trades je Tag“, „Verluste in Folge“ und „manuell“, nicht für Tagesverlust und Risiko
    ///   (Dritter Gegencheck G1, Doc 49).
    public static func pruefe(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                              manuell: Set<String> = [], ohneBetrag: Set<String> = []) -> [Regelverstoss] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let nachEroeffnung = trades.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
        let jeTag = Dictionary(grouping: nachEroeffnung) { $0.eroeffnungstag(kalender) }
        let geschlossenJeTag = schlussJeTag(trades, kalender: kalender)
        var verstoesse: [Regelverstoss] = []

        for tag in jeTag.keys.sorted() {
            let tagesTrades = jeTag[tag]!
            var eroeffnungen: [String] = []
            for t in tagesTrades {
                if !eroeffnungen.contains(t.positionsschluessel) { eroeffnungen.append(t.positionsschluessel) }
                let nummer = eroeffnungen.firstIndex(of: t.positionsschluessel)!
                var arten: [Regelverstoss.Art] = []
                let vorher = geschlossenVor(t, in: geschlossenJeTag[tag] ?? [], kalender: kalender)
                if let max = regeln.maxTradesJeTag, nummer >= max { arten.append(.tradesJeTag) }
                if let max = regeln.maxTagesverlust {
                    let netto = vorher.filter { !ohneBetrag.contains($0.id) }.map(\.netProfit).reduce(0, +)
                    if netto <= -max { arten.append(.tagesverlust) }
                }
                if let n = regeln.stoppNachVerlusten, n > 0, verlusteInFolge(vorher) >= n {
                    arten.append(.stoppNachVerlusten)
                }
                // Nur das Risiko aus dem Stop: Ein selbst gesetztes geplantes Risiko ist kein Verstoß je Trade.
                // Der tatsächliche Verlust über der Grenze zählt weiter, auch bei angenommenem Risiko.
                if let max = regeln.maxRisikoJeTrade, !ohneBetrag.contains(t.id),
                   (t.stopRisiko ?? 0) > max || t.netProfit < -max {
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

    /// Tagesstände über alle Trades eines Währungsangleichs; Netto ohne die Trades ohne Kurs (G1).
    public static func tagesstaende(_ angleich: Waehrungsangleich, regeln: Handelsregeln, zeitzone: TimeZone,
                                    manuell: Set<String> = []) -> [Tagesstand] {
        tagesstaende(angleich.trades + angleich.ohneKurs, regeln: regeln, zeitzone: zeitzone, manuell: manuell,
                     ohneBetrag: angleich.ohneKursIDs)
    }

    /// Tagesstand je Handelstag, sortiert nach Tag. Trades zählen am Tag der Eröffnung,
    /// Netto und Verluste in Folge am Tag des Schlusses (realisiert, auch aus Übernacht-Positionen).
    /// `ohneBetrag` wie bei `pruefe`.
    public static func tagesstaende(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                                    manuell: Set<String> = [], ohneBetrag: Set<String> = []) -> [Tagesstand] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let verstoesse = pruefe(trades, regeln: regeln, zeitzone: zeitzone, manuell: manuell, ohneBetrag: ohneBetrag)
        let jeTag = Dictionary(grouping: trades) { $0.eroeffnungstag(kalender) }
        let geschlossenJeTag = schlussJeTag(trades, kalender: kalender)
        return Set(jeTag.keys).union(geschlossenJeTag.keys).sorted().map { tag in
            let nachSchluss = geschlossenJeTag[tag] ?? []
            let betroffen = Set(verstoesse.filter { $0.tag == tag }.map(\.trade))
            let eroeffnungen = Set((jeTag[tag] ?? []).map(\.positionsschluessel)).count
            let netto = nachSchluss.filter { !ohneBetrag.contains($0.id) }.map(\.netProfit).reduce(0, +)
            return Tagesstand(tag: tag, trades: eroeffnungen, netto: netto,
                              verlusteInFolge: verlusteInFolge(nachSchluss), verstoesse: betroffen.count)
        }
    }

    /// Trades je Kalendertag des Schlusses, nach Schlusszeit.
    static func schlussJeTag(_ trades: [Trade], kalender: Calendar) -> [Date: [Trade]] {
        let nachSchluss = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        return Dictionary(grouping: nachSchluss) { $0.schlusstag(kalender) }
    }

    /// Trades, die am Tag von `t` sicher vor seiner Eröffnung geschlossen wurden, gleich wann eröffnet;
    /// nach Schlusszeit. Ohne Uhrzeit ist die Reihenfolge am selben Tag unbekannt, solche zählen nicht.
    static func geschlossenVor(_ t: Trade, in geschlossenAmTag: [Trade], kalender: Calendar) -> [Trade] {
        geschlossenAmTag.filter { $0.sicherGeschlossen(vor: t, kalender: kalender) }
    }

    /// Verluste am Ende der Folge, ohne Unterbrechung durch einen Gewinner oder Breakeven.
    /// Teilverkäufe einer Position zählen zusammen, nach ihrem letzten Schluss.
    static func verlusteInFolge(_ nachSchluss: [Trade]) -> Int {
        var reihenfolge: [String] = []
        var netto: [String: Decimal] = [:]
        for t in nachSchluss {
            reihenfolge.removeAll { $0 == t.positionsschluessel }
            reihenfolge.append(t.positionsschluessel)
            netto[t.positionsschluessel, default: 0] += t.netProfit
        }
        return reihenfolge.reversed().prefix { netto[$0]! < 0 }.count
    }
}
