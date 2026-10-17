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
                              manuell: Set<String> = [], setups: [String: String] = [:], playbook: [Setup] = [],
                              offene: [OffenerTrade] = [], jetzt: Date = Date()) -> [Regelverstoss] {
        pruefe(angleich.trades + angleich.ohneKurs, regeln: regeln, zeitzone: zeitzone, manuell: manuell,
               ohneBetrag: angleich.ohneKursIDs, setups: setups, playbook: playbook, offene: offene, jetzt: jetzt)
    }

    /// - Parameters:
    ///   - ohneBetrag: Trades, deren Beträge nicht in Kontowährung vorliegen (`Waehrungsangleich.ohneKurs`).
    ///     Sie zählen für „Trades je Tag“, „Verluste in Folge“, „manuell“, Setup-Grenzen, Haltedauer und offene
    ///     Positionen, nicht für Beträge (Tages-, Monatsverlust, Risiko, offenes Risiko, Kontostand; G1, Doc 49).
    ///   - setups: Setup aus dem Journal je Trade-ID (auch für `offene`); verbindet Trades mit den Regeln ihrer
    ///     Karte in `playbook` (E4, E5), ohne Rücksicht auf Groß- und Kleinschreibung.
    ///   - offene: Positionen, die noch offen sind (Auszug oder von Hand). Sie zählen bei offenen Positionen und
    ///     offenem Risiko (E6) und bei der Haltedauer bis `jetzt` (E5).
    public static func pruefe(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                              manuell: Set<String> = [], ohneBetrag: Set<String> = [],
                              setups: [String: String] = [:], playbook: [Setup] = [], offene: [OffenerTrade] = [],
                              jetzt: Date = Date()) -> [Regelverstoss] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let nachEroeffnung = trades.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
        let jeTag = Dictionary(grouping: nachEroeffnung) { $0.eroeffnungstag(kalender) }
        let geschlossenJeTag = schlussJeTag(trades, kalender: kalender)
        let karten = Dictionary(playbook.map { (Setup.schluessel($0.name), $0) }, uniquingKeysWith: { erste, _ in erste })
        func karte(_ id: String) -> Setup? { setups[id].flatMap { karten[Setup.schluessel($0)] } }
        let mitBetrag = trades.filter { !ohneBetrag.contains($0.id) }
        func stand(_ zeit: Date) -> Decimal? { regeln.kontostand?.stand(bei: zeit, trades: mitBetrag) }
        var verstoesse: [Regelverstoss] = []

        for tag in jeTag.keys.sorted() {
            let tagesTrades = jeTag[tag]!
            var eroeffnungen: [String] = []
            var jeSetup: [String: [String]] = [:]
            let standTag = stand(tag)
            let tagesgrenze = Handelsregeln.grenze(betrag: regeln.maxTagesverlust,
                                                   prozent: regeln.maxTagesverlustProzent, stand: standTag)
            let risikogrenze = Handelsregeln.grenze(betrag: regeln.maxRisikoJeTrade,
                                                    prozent: regeln.maxRisikoJeTradeProzent, stand: standTag)
            for t in tagesTrades {
                if !eroeffnungen.contains(t.positionsschluessel) { eroeffnungen.append(t.positionsschluessel) }
                let nummer = eroeffnungen.firstIndex(of: t.positionsschluessel)!
                var arten: [Regelverstoss.Art] = []
                let vorher = geschlossenVor(t, in: geschlossenJeTag[tag] ?? [], kalender: kalender)
                if let max = regeln.maxTradesJeTag, nummer >= max { arten.append(.tradesJeTag) }
                if let max = tagesgrenze {
                    let netto = vorher.filter { !ohneBetrag.contains($0.id) }.map(\.netProfit).reduce(0, +)
                    if netto <= -max { arten.append(.tagesverlust) }
                }
                if let n = regeln.stoppNachVerlusten, n > 0, verlusteInFolge(vorher) >= n {
                    arten.append(.stoppNachVerlusten)
                }
                // Nur das Risiko aus dem Stop: Ein selbst gesetztes geplantes Risiko ist kein Verstoß je Trade.
                // Der tatsächliche Verlust über der Grenze zählt weiter, auch bei angenommenem Risiko.
                if let max = risikogrenze, !ohneBetrag.contains(t.id),
                   (t.stopRisiko ?? 0) > max || t.netProfit < -max {
                    arten.append(.risikoJeTrade)
                }
                if manuell.contains(t.id) { arten.append(.manuell) }
                if let k = karte(t.id) {
                    let schluessel = Setup.schluessel(k.name)
                    var eigene = jeSetup[schluessel, default: []]
                    if !eigene.contains(t.positionsschluessel) { eigene.append(t.positionsschluessel) }
                    jeSetup[schluessel] = eigene
                    if let max = k.maxTradesJeTag, eigene.firstIndex(of: t.positionsschluessel)! >= max {
                        arten.append(.tradesJeSetup)
                    }
                    if let h = k.haltedauer, verletzt(h, von: t.openTime, bis: t.closeTime, nurDatum: t.nurDatum,
                                                       kalender: kalender) {
                        arten.append(.haltedauer)
                    }
                }
                verstoesse += arten.map { Regelverstoss(art: $0, trade: t.id, tag: tag) }
            }
        }
        verstoesse += monatsverstoesse(nachEroeffnung, regeln: regeln, kalender: kalender, ohneBetrag: ohneBetrag,
                                       stand: stand)
        verstoesse += offenVerstoesse(nachEroeffnung, offene: offene, regeln: regeln, kalender: kalender,
                                      ohneBetrag: ohneBetrag, stand: stand)
        for o in offene {
            guard let h = karte(o.id)?.haltedauer,
                  verletzt(h, von: o.openTime, bis: jetzt, nurDatum: o.nurDatum, kalender: kalender) else { continue }
            let tag = Trade.tagesbeginn(o.openTime, nurDatum: o.nurDatum, kalender: kalender)
            verstoesse.append(Regelverstoss(art: .haltedauer, trade: o.id, tag: tag))
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
                                    manuell: Set<String> = [], setups: [String: String] = [:],
                                    playbook: [Setup] = [], offene: [OffenerTrade] = [],
                                    jetzt: Date = Date()) -> [Tagesstand] {
        tagesstaende(angleich.trades + angleich.ohneKurs, regeln: regeln, zeitzone: zeitzone, manuell: manuell,
                     ohneBetrag: angleich.ohneKursIDs, setups: setups, playbook: playbook, offene: offene, jetzt: jetzt)
    }

    /// Tagesstand je Handelstag, sortiert nach Tag. Trades zählen am Tag der Eröffnung,
    /// Netto und Verluste in Folge am Tag des Schlusses (realisiert, auch aus Übernacht-Positionen).
    /// `ohneBetrag` wie bei `pruefe`.
    public static func tagesstaende(_ trades: [Trade], regeln: Handelsregeln, zeitzone: TimeZone,
                                    manuell: Set<String> = [], ohneBetrag: Set<String> = [],
                                    setups: [String: String] = [:], playbook: [Setup] = [],
                                    offene: [OffenerTrade] = [], jetzt: Date = Date()) -> [Tagesstand] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let verstoesse = pruefe(trades, regeln: regeln, zeitzone: zeitzone, manuell: manuell, ohneBetrag: ohneBetrag,
                                setups: setups, playbook: playbook, offene: offene, jetzt: jetzt)
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
