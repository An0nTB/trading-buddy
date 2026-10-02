import Foundation

/// Prüft abgeschlossene Trades rückwirkend gegen Prop-Firm-Regeln (Doc 18, F10).
/// Grundlage sind nur Schlusssalden: Ein Bruch durch offene Verluste zwischen zwei Trades bleibt unsichtbar.
/// Ein gemeldeter Verstoß ist sicher, ein fehlender bei `nurNaeherung` nicht (Recherche 02.10.2026).
/// Jeder Trade zählt zum Handelstag der Firma, in dem er geschlossen wurde.
public enum PropFirmPruefung {
    public enum Art: String, Codable, Sendable, CaseIterable {
        case tagesverlust, gesamtverlust, haltenUeberTageswechsel, haltenUeberWochenende, lotsJeTrade, ohneStop
    }

    /// Regeln, die die Firma auf Equity prüft, hier aber nur auf realisierten Salden.
    public static let nurNaeherung: Set<Art> = [.tagesverlust, .gesamtverlust]

    public struct Verstoss: Sendable, Equatable {
        public var art: Art
        public var trade: String
        /// Beginn des Handelstags der Firma.
        public var tag: Date
    }

    public struct Ergebnis: Sendable, Equatable {
        public var verstoesse: [Verstoss]
        /// Realisierter Saldo nach dem letzten Trade.
        public var saldo: Decimal
        /// Aktuelle Gesamtverlust-Grenze als Saldo; `nil` ohne Regel.
        public var gesamtverlustGrenze: Decimal?
        /// Schlusszeit des Trades, mit dem das Gewinnziel erreicht wurde.
        public var gewinnzielErreicht: Date?
        public var handelstage: Int
        /// Bester Tag ÷ Bezug; `nil` ohne Gewinntag oder ohne positiven Bezug.
        public var konsistenzAnteil: Decimal?
        /// Alle Ziele erreicht und kein Verstoß; `nil` ohne Gewinnziel.
        public var bestanden: Bool?
    }

    public static func pruefe(_ trades: [Trade], regeln r: PropFirmRegeln) -> Ergebnis {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: r.zeitzone) ?? TimeZone(secondsFromGMT: 0)!
        func beginn(_ kalendertag: Date) -> Date {
            kalender.date(bySettingHour: r.tageswechselMinuten / 60, minute: r.tageswechselMinuten % 60, second: 0,
                          of: kalendertag)!
        }
        func tag(_ zeit: Date) -> Date {
            let heute = kalender.startOfDay(for: zeit)
            return zeit >= beginn(heute) ? beginn(heute) : beginn(kalender.date(byAdding: .day, value: -1, to: heute)!)
        }

        var verstoesse: [Verstoss] = []
        for t in trades {
            let schlusstag = tag(t.closeTime)
            func melde(_ art: Art) { verstoesse.append(Verstoss(art: art, trade: t.id, tag: schlusstag)) }
            if r.keinHaltenUeberTageswechsel, tag(t.openTime) != schlusstag { melde(.haltenUeberTageswechsel) }
            if r.keinHaltenUeberWochenende, ueberSamstag(t, kalender) { melde(.haltenUeberWochenende) }
            if let max = r.maxLotsJeTrade, t.lots > max { melde(.lotsJeTrade) }
            if r.stopPflicht, t.stopLoss == nil { melde(.ohneStop) }
        }

        // Salden nach Schlusszeit: Tagesverlust ab Saldo zu Tagesbeginn, Gesamtgrenze ab höchstem Tagesend-Saldo.
        var saldo = r.startkapital, hoch = r.startkapital, tagesbeginn = r.startkapital
        var aktuellerTag: Date?
        var gesamtVerletzt = false
        var tagesnetto: [Date: Decimal] = [:]
        var zielErreicht: Date?
        func grenze() -> Decimal? {
            guard let max = r.maxGesamtverlust else { return nil }
            guard r.gesamtverlustart == .nachgezogenTagesende else { return r.startkapital - max }
            return r.einfrierenBeiSaldo.map { min(hoch - max, $0) } ?? hoch - max
        }
        for t in trades.sorted(by: { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }) {
            let d = tag(t.closeTime)
            if d != aktuellerTag {
                if aktuellerTag != nil { hoch = max(hoch, saldo) }
                tagesbeginn = saldo
                aktuellerTag = d
            }
            saldo += t.netProfit
            tagesnetto[d, default: 0] += t.netProfit
            if let max = r.maxTagesverlust, saldo < tagesbeginn - max,
               !verstoesse.contains(where: { $0.art == .tagesverlust && $0.tag == d }) {
                verstoesse.append(Verstoss(art: .tagesverlust, trade: t.id, tag: d))
            }
            if !gesamtVerletzt, let g = grenze(), saldo < g {
                verstoesse.append(Verstoss(art: .gesamtverlust, trade: t.id, tag: d))
                gesamtVerletzt = true
            }
            if zielErreicht == nil, let ziel = r.gewinnziel, saldo >= r.startkapital + ziel { zielErreicht = t.closeTime }
        }
        hoch = max(hoch, saldo)

        let tage: Int
        switch r.handelstagzaehlung {
        case .eroeffnung: tage = Set(trades.map { tag($0.openTime) }).count
        case .ergebnis: tage = tagesnetto.values.filter { $0 != 0 }.count
        case .gewinntag: tage = tagesnetto.values.filter { netto in r.mindestTagesgewinn.map { netto >= $0 } ?? (netto > 0) }.count
        }
        let gewinntage = tagesnetto.values.filter { $0 > 0 }
        let bezug = r.konsistenzbezug == .nettogewinn ? saldo - r.startkapital : gewinntage.reduce(0, +)
        let anteil: Decimal? = gewinntage.max().flatMap { bezug > 0 ? $0 / bezug : nil }

        let reihenfolge = Art.allCases
        verstoesse.sort {
            ($0.tag, $0.trade, reihenfolge.firstIndex(of: $0.art)!) < ($1.tag, $1.trade, reihenfolge.firstIndex(of: $1.art)!)
        }
        var bestanden: Bool?
        if r.gewinnziel != nil {
            let tageOK = r.mindestHandelstage.map { tage >= $0 } ?? true
            let konsistenzOK = r.konsistenzMaxAnteil.map { m in anteil.map { $0 <= m } ?? true } ?? true
            bestanden = verstoesse.isEmpty && zielErreicht != nil && tageOK && konsistenzOK
        }
        return Ergebnis(verstoesse: verstoesse, saldo: saldo, gesamtverlustGrenze: grenze(),
                        gewinnzielErreicht: zielErreicht, handelstage: tage, konsistenzAnteil: anteil,
                        bestanden: bestanden)
    }

    /// Liegt ein Samstag 00:00 Ortszeit der Firma zwischen Eröffnung und Schluss?
    static func ueberSamstag(_ t: Trade, _ kalender: Calendar) -> Bool {
        var tag = kalender.startOfDay(for: t.openTime)
        for _ in 0..<400 {
            tag = kalender.date(byAdding: .day, value: 1, to: tag)!
            if tag >= t.closeTime { return false }
            if kalender.component(.weekday, from: tag) == 7 { return true }
        }
        return true
    }
}
