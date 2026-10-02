import Foundation

/// Vergleicht Handelstage mit Plan vor dem ersten Trade gegen Tage ohne Plan (Doc 18 F4, B12:
/// Aufzeichnung vor dem Trade gilt als Kern). Tag ist der Kalendertag der Eröffnung in der Zeitzone
/// des Nutzers, wie bei den Handelsregeln. Tage ohne Trades zählen nicht.
public struct Planwirkung: Sendable, Equatable {
    public var tageMitPlan: Int
    public var tageOhnePlan: Int
    public var tradesMitPlan: Int
    public var tradesOhnePlan: Int
    public var nettoMitPlan: Decimal
    public var nettoOhnePlan: Decimal
    /// Handelstage mit Plan, nach Tag sortiert; die App kann sie markieren.
    public var tageMitPlanListe: [Journaltag]
    /// Tage nur mit Trades ohne Uhrzeit (Trade Republic, Scalable), deren Plan erst im Lauf des Tages
    /// gespeichert wurde: ob vor dem ersten Trade, ist unbekannt. Sie zählen auf keiner Seite.
    /// Ein Plan erst nach dem Tag zählt als ohne Plan (Gegencheck K4).
    public var tageUnklar: Int

    /// Mindestzahl Handelstage je Seite, ab der ein Vergleich mehr als Beschreibung ist (Vorschlag).
    public static let mindestTage = 10

    public var nettoJeTagMitPlan: Decimal? { tageMitPlan > 0 ? nettoMitPlan / Decimal(tageMitPlan) : nil }
    public var nettoJeTagOhnePlan: Decimal? { tageOhnePlan > 0 ? nettoOhnePlan / Decimal(tageOhnePlan) : nil }
    public var genugDaten: Bool { tageMitPlan >= Self.mindestTage && tageOhnePlan >= Self.mindestTage }

    public init(trades: [Trade], notizen: [Tagesnotiz], zeitzone: TimeZone) {
        var notizJeTag: [Journaltag: Tagesnotiz] = [:]
        for n in notizen { notizJeTag[n.tag] = n }
        var jeTag: [Journaltag: [Trade]] = [:]
        let kalender = Journaltag.gregorianisch(zeitzone)
        for t in trades { jeTag[Journaltag(t.eroeffnungstag(kalender), zeitzone: zeitzone), default: []].append(t) }

        tageMitPlan = 0
        tageOhnePlan = 0
        tradesMitPlan = 0
        tradesOhnePlan = 0
        nettoMitPlan = 0
        nettoOhnePlan = 0
        tageMitPlanListe = []
        tageUnklar = 0
        for tag in jeTag.keys.sorted() {
            let tagesTrades = jeTag[tag]!
            let mitUhrzeit = tagesTrades.filter { !$0.nurDatum }
            let netto = tagesTrades.map(\.netProfit).reduce(0, +)
            let mitPlan: Bool
            if let erster = mitUhrzeit.map(\.openTime).min() {
                mitPlan = notizJeTag[tag]?.hatPlan(vor: erster) == true
            } else {
                // Ohne Uhrzeit: sicher vor dem ersten Trade ist nur ein Plan von vor Tagesbeginn.
                let beginn = tag.beginn(in: zeitzone)
                let ende = Journaltag.gregorianisch(zeitzone).date(byAdding: .day, value: 1, to: beginn)!
                let notiz = notizJeTag[tag]
                if notiz?.hatPlan(vor: beginn) == true {
                    mitPlan = true
                } else if notiz?.hatPlan(vor: ende) == true {
                    tageUnklar += 1
                    continue
                } else {
                    mitPlan = false
                }
            }
            if mitPlan {
                tageMitPlan += 1
                tradesMitPlan += tagesTrades.count
                nettoMitPlan += netto
                tageMitPlanListe.append(tag)
            } else {
                tageOhnePlan += 1
                tradesOhnePlan += tagesTrades.count
                nettoOhnePlan += netto
            }
        }
    }
}

/// Verpasste Trades je Grund. `regelSperre` heißt „gewollt verpasst“ und zählt nicht zum entgangenen
/// Ergebnis, weil die eigene Regel richtig gegriffen hat.
public struct VerpassteAuswertung: Sendable, Equatable {
    public struct JeGrund: Sendable, Equatable {
        public var grund: VerpassterTrade.Grund
        public var anzahl: Int
        /// Davon mit geschätztem Ergebnis in R.
        public var mitSchaetzung: Int
        public var summeR: Decimal
    }

    public var anzahl: Int
    public var gewollt: Int
    /// Summe der Schätzungen in R ohne gewollt verpasste.
    public var entgangenR: Decimal
    /// Nur Gründe, die vorkommen; nach Anzahl absteigend, bei Gleichstand in der Reihenfolge der Gründe.
    public var jeGrund: [JeGrund]
    /// Anzahl je Setup-Name; verpasste Trades ohne Setup fehlen hier.
    public var jeSetup: [String: Int]

    public init(_ verpasst: [VerpassterTrade]) {
        anzahl = verpasst.count
        gewollt = verpasst.filter { $0.grund == .regelSperre }.count
        entgangenR = verpasst.filter { $0.grund != .regelSperre }.compactMap(\.ergebnisR).reduce(0, +)
        var gruppen: [JeGrund] = []
        for grund in VerpassterTrade.Grund.allCases {
            let teil = verpasst.filter { $0.grund == grund }
            guard !teil.isEmpty else { continue }
            let schaetzungen = teil.compactMap(\.ergebnisR)
            gruppen.append(JeGrund(grund: grund, anzahl: teil.count, mitSchaetzung: schaetzungen.count,
                                   summeR: schaetzungen.reduce(0, +)))
        }
        // Stabile Sortierung: Reihenfolge der Gründe bleibt bei gleicher Anzahl erhalten.
        jeGrund = gruppen.enumerated()
            .sorted { ($1.element.anzahl, $0.offset) < ($0.element.anzahl, $1.offset) }
            .map(\.element)
        var setups: [String: Int] = [:]
        for v in verpasst {
            if let s = v.setup, !s.isEmpty { setups[s, default: 0] += 1 }
        }
        jeSetup = setups
    }
}
