import Foundation

/// Daten für die Auswertungsseite mit Grafiken (Tim 05.10.2026: „welche Tage zum Beispiel oder welche Uhrzeit
/// gut und schlecht läuft“). Reine Rechenfunktionen ohne Texte; Beschriftung und Lokalisierung macht die App.
///
/// Gemeinsame Regeln:
/// - Beträge in Kontowährung: Trades vorher durch `Waehrungsangleich` geben.
/// - Trades ohne Uhrzeit (`Trade.nurDatum`) fehlen bei Stunde, Haltedauer und Zeitstrahl; sie werden dort gezählt.
/// - Tag eines Trades ist sein Schlusstag (`Trade.schlusstag`) in der Zeitzone des Nutzers: Das Tagesergebnis
///   ist realisiert, wenn der Trade geschlossen ist.
/// - `tradeIDs` stehen nach Schlusszeit, bei gleicher Zeit nach ID; die App zeigt damit per Klick die Trades.
public enum Tiefenanalyse {
    static func kalender(_ zeitzone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = zeitzone
        return k
    }

    /// ISO-Wochentag, 1 = Montag, wie `Aufteilung.wochentag`.
    static func isoWochentag(_ zeit: Date, kalender: Calendar) -> Int {
        (kalender.component(.weekday, from: zeit) + 5) % 7 + 1
    }

    static func nachSchluss(_ trades: [Trade]) -> [Trade] {
        trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
    }

    static func dezimalAlsDouble(_ wert: Decimal) -> Double {
        NSDecimalNumber(decimal: wert).doubleValue
    }
}

// MARK: - Heatmap Wochentag × Stunde

extension Tiefenanalyse {
    public struct HeatmapZelle: Sendable, Equatable {
        /// ISO-Wochentag der Eröffnung, 1 = Montag.
        public var wochentag: Int
        /// Stunde der Eröffnung, 0 bis 23.
        public var stunde: Int
        public var anzahl: Int
        public var netto: Decimal
        /// Anteil Gewinner, 0 bis 1.
        public var trefferquote: Decimal
        /// Mittelwert der R-Multiples; `nil`, wenn kein Trade der Zelle ein bekanntes Risiko hat.
        public var durchschnittR: Decimal?
        public var anzahlMitR: Int
        /// Mindestens `Heatmap.mindestanzahl` Trades; darunter nur Zahl, keine Schlussfolgerung.
        public var belastbar: Bool
        public var tradeIDs: [Trade.ID]
    }

    public struct Heatmap: Sendable, Equatable {
        /// Nur Zellen mit Trades, nach Wochentag und Stunde; leere Zellen ergänzt die App.
        public var zellen: [HeatmapZelle]
        /// Trades ohne Uhrzeit, die in keiner Zelle stehen.
        public var ohneUhrzeit: Int
        public var mindestanzahl: Int

        public func zelle(wochentag: Int, stunde: Int) -> HeatmapZelle? {
            zellen.first { $0.wochentag == wochentag && $0.stunde == stunde }
        }
    }

    /// Kennzahlen je Wochentag und Stunde der Eröffnung in der Zeitzone des Nutzers.
    /// - Parameter mindestanzahl: ab dieser Zahl Trades ist eine Zelle `belastbar` (Vorschlag 5).
    public static func heatmap(_ trades: [Trade], zeitzone: TimeZone, mindestanzahl: Int = 5) -> Heatmap {
        let k = kalender(zeitzone)
        let mitUhrzeit = nachSchluss(trades).filter { !$0.nurDatum }
        var gruppen: [Int: [Trade]] = [:]
        for t in mitUhrzeit {
            let schluessel = isoWochentag(t.openTime, kalender: k) * 100 + k.component(.hour, from: t.openTime)
            gruppen[schluessel, default: []].append(t)
        }
        var zellen: [HeatmapZelle] = []
        for schluessel in gruppen.keys.sorted() {
            let teil = gruppen[schluessel] ?? []
            let kz = Kennzahlen(trades: teil)
            let zelle = HeatmapZelle(
                wochentag: schluessel / 100, stunde: schluessel % 100, anzahl: kz.anzahl, netto: kz.netto,
                trefferquote: kz.trefferquote ?? 0, durchschnittR: kz.erwartungswertR, anzahlMitR: kz.anzahlMitR,
                belastbar: kz.anzahl >= mindestanzahl, tradeIDs: teil.map(\.id))
            zellen.append(zelle)
        }
        return Heatmap(zellen: zellen, ohneUhrzeit: trades.count - mitUhrzeit.count, mindestanzahl: mindestanzahl)
    }
}

// MARK: - Tagesverlauf

extension Tiefenanalyse {
    public struct Tagesverlauf: Sendable, Equatable {
        public struct Eintrag: Sendable, Equatable {
            public var tradeID: Trade.ID
            public var symbol: String
            public var einstieg: Date
            public var ausstieg: Date
            public var netto: Decimal
            public var ergebnis: Trade.Outcome
            /// Summe netto aller Trades des Tages mit Uhrzeit bis einschließlich diesem Schluss.
            public var summeNachSchluss: Decimal
            /// Markierte Fehlermuster dieses Trades (nur `revancheTrade` und `ueberhandeln`).
            public var muster: [Fehlermuster]
        }

        public struct Punkt: Sendable, Equatable {
            public var zeit: Date
            public var summe: Decimal
        }

        /// Zusammenhängende Trades (nach Eröffnung) mit demselben Muster; von erster Eröffnung bis letztem Schluss.
        public struct Phase: Sendable, Equatable {
            public var muster: Fehlermuster
            public var von: Date
            public var bis: Date
            public var tradeIDs: [Trade.ID]
        }

        public var tag: Journaltag
        /// Trades des Tages mit Uhrzeit, nach Schlusszeit.
        public var eintraege: [Eintrag]
        /// Erst alle Revanche-Phasen, dann alle Überhandeln-Phasen, je nach Beginn.
        public var phasen: [Phase]
        /// Trades des Tages ohne Uhrzeit: nicht im Zeitstrahl, aber im Tagesergebnis.
        public var ohneUhrzeit: [Trade.ID]
        public var nettoOhneUhrzeit: Decimal
        /// Tagesergebnis einschließlich der Trades ohne Uhrzeit.
        public var netto: Decimal

        /// Punkte für die Linie der laufenden Tagessumme, einer je Schluss; die Linie beginnt bei 0.
        public var punkte: [Punkt] {
            eintraege.map { Punkt(zeit: $0.ausstieg, summe: $0.summeNachSchluss) }
        }
    }

    /// Fehlermuster, die der Tagesverlauf als Phase markiert.
    public static let tagesverlaufMuster: [Fehlermuster] = [.revancheTrade, .ueberhandeln]

    /// Ablauf eines Handelstags für eine Zeitleiste.
    /// - Parameters:
    ///   - trades: Trades, aus denen der Tag gefiltert wird (Schlusstag), z. B. `Auswertung.trades`.
    ///   - befunde: vorhandene Fehlermuster-Erkennung, z. B. `Auswertung.befunde`; hier wird nichts neu geprüft,
    ///     weil „Überhandeln“ den Median über alle Tage braucht.
    public static func tagesverlauf(_ trades: [Trade], tag: Journaltag, befunde: [Befund],
                                    zeitzone: TimeZone) -> Tagesverlauf {
        let k = kalender(zeitzone)
        let amTag = nachSchluss(trades).filter { Journaltag($0.schlusstag(k), zeitzone: zeitzone) == tag }
        let ohne = amTag.filter(\.nurDatum)
        var musterJeTrade: [Trade.ID: Set<Fehlermuster>] = [:]
        for b in befunde where tagesverlaufMuster.contains(b.muster) {
            for id in b.trades { musterJeTrade[id, default: []].insert(b.muster) }
        }
        var summe: Decimal = 0
        var eintraege: [Tagesverlauf.Eintrag] = []
        for t in amTag where !t.nurDatum {
            summe += t.netProfit
            let eigene = musterJeTrade[t.id] ?? []
            let muster = tagesverlaufMuster.filter { eigene.contains($0) }
            eintraege.append(Tagesverlauf.Eintrag(
                tradeID: t.id, symbol: t.symbol, einstieg: t.openTime, ausstieg: t.closeTime, netto: t.netProfit,
                ergebnis: t.outcome, summeNachSchluss: summe, muster: muster))
        }
        var phasen: [Tagesverlauf.Phase] = []
        for muster in tagesverlaufMuster {
            phasen.append(contentsOf: Self.phasen(muster, eintraege))
        }
        let nettoOhne: Decimal = ohne.map(\.netProfit).reduce(0, +)
        return Tagesverlauf(tag: tag, eintraege: eintraege, phasen: phasen, ohneUhrzeit: ohne.map(\.id),
                            nettoOhneUhrzeit: nettoOhne, netto: summe + nettoOhne)
    }

    static func phasen(_ muster: Fehlermuster, _ eintraege: [Tagesverlauf.Eintrag]) -> [Tagesverlauf.Phase] {
        let nachEinstieg = eintraege.sorted { ($0.einstieg, $0.tradeID) < ($1.einstieg, $1.tradeID) }
        var ergebnis: [Tagesverlauf.Phase] = []
        var laufend: Tagesverlauf.Phase?
        for e in nachEinstieg {
            guard e.muster.contains(muster) else {
                if let p = laufend { ergebnis.append(p) }
                laufend = nil
                continue
            }
            if var p = laufend {
                p.bis = max(p.bis, e.ausstieg)
                p.tradeIDs.append(e.tradeID)
                laufend = p
            } else {
                laufend = Tagesverlauf.Phase(muster: muster, von: e.einstieg, bis: e.ausstieg, tradeIDs: [e.tradeID])
            }
        }
        if let p = laufend { ergebnis.append(p) }
        return ergebnis
    }
}

// MARK: - Punktwolken

extension Tiefenanalyse {
    public struct HaltedauerPunkt: Sendable, Equatable {
        public var tradeID: Trade.ID
        /// Sekunden von Eröffnung bis Schluss.
        public var haltedauer: TimeInterval
        public var netto: Decimal
        public var ergebnis: Trade.Outcome
    }

    /// Haltedauer gegen Ergebnis je Trade, nach Schlusszeit; Trades ohne Uhrzeit fehlen.
    public static func haltedauerGegenNetto(_ trades: [Trade]) -> [HaltedauerPunkt] {
        nachSchluss(trades).filter { !$0.nurDatum }.map {
            HaltedauerPunkt(tradeID: $0.id, haltedauer: $0.holdingTime, netto: $0.netProfit, ergebnis: $0.outcome)
        }
    }

    public struct Tagespunkt: Sendable, Equatable {
        public var tag: Journaltag
        /// Trades des Tages; Teilverkäufe einer Position zählen als einer (wie bei „Überhandeln“).
        public var trades: Int
        public var netto: Decimal
        public var tradeIDs: [Trade.ID]
    }

    /// Gerade y = steigung × x + achsenabschnitt nach der Methode der kleinsten Quadrate.
    /// Bewusst in `Double`: Sie dient nur zum Zeichnen einer Trendlinie, nicht als Betrag.
    public struct Regression: Sendable, Equatable {
        public var steigung: Double
        public var achsenabschnitt: Double

        public func wert(bei x: Double) -> Double { steigung * x + achsenabschnitt }
    }

    public struct TradesJeTag: Sendable, Equatable {
        /// Ein Punkt je Handelstag (Schlusstag), nach Tag sortiert.
        public var punkte: [Tagespunkt]
        /// Tagesergebnis gegen Trades je Tag; `nil` bei weniger als 3 Tagen oder gleicher Anzahl an allen Tagen.
        public var regression: Regression?
    }

    /// Trades pro Tag gegen Tagesergebnis, für die Frage „Wird es schlechter, wenn ich mehr handle?“.
    public static func tradesJeTag(_ trades: [Trade], zeitzone: TimeZone) -> TradesJeTag {
        let k = kalender(zeitzone)
        var jeTag: [Journaltag: [Trade]] = [:]
        for t in nachSchluss(trades) {
            jeTag[Journaltag(t.schlusstag(k), zeitzone: zeitzone), default: []].append(t)
        }
        var punkte: [Tagespunkt] = []
        for tag in jeTag.keys.sorted() {
            let teil = jeTag[tag] ?? []
            let positionen = Set(teil.map(\.positionsschluessel)).count
            let netto: Decimal = teil.map(\.netProfit).reduce(0, +)
            punkte.append(Tagespunkt(tag: tag, trades: positionen, netto: netto, tradeIDs: teil.map(\.id)))
        }
        let x = punkte.map { Double($0.trades) }
        let y = punkte.map { dezimalAlsDouble($0.netto) }
        return TradesJeTag(punkte: punkte, regression: regression(x: x, y: y))
    }

    /// Lineare Regression; `nil` bei weniger als 3 Punkten, ungleich langen Listen oder Varianz 0 in x.
    public static func regression(x: [Double], y: [Double]) -> Regression? {
        guard x.count >= 3, x.count == y.count else { return nil }
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n
        let my = y.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for i in x.indices {
            sxx += (x[i] - mx) * (x[i] - mx)
            sxy += (x[i] - mx) * (y[i] - my)
        }
        guard sxx > 0 else { return nil }
        let steigung = sxy / sxx
        return Regression(steigung: steigung, achsenabschnitt: my - steigung * mx)
    }
}
