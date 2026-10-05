import Foundation

extension Fehlermuster {
    /// Prüft alle Regeln und liefert nur die Muster mit Treffern.
    /// - Parameters:
    ///   - geloeschteOrders: Anzahl gelöschter Pending Orders im selben Zeitraum.
    ///   - zeitzone: Tagesgrenze für „Trades pro Tag“, in der Regel die des Nutzers.
    ///   - schwellen: Bei „Überhandeln“ steht in `Befund.wert` die Grenze (siehe `ueberhandelnGrenze`).
    public static func pruefe(_ trades: [Trade], geloeschteOrders: Int = 0, zeitzone: TimeZone,
                              schwellen s: Schwellen = Schwellen()) -> [Befund] {
        let nachEroeffnung = trades.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
        let nachSchluss = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        let n = trades.count
        var befunde: [Befund?] = []
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone

        // Revanche: kurz nach einem Verlust eröffnet, größer als üblich (`groessenmass`).
        // Minutenabstände brauchen Uhrzeiten; Trades nur mit Datum fallen hier heraus.
        let medianGroesse = Dictionary(grouping: trades) { misstEinsatz($0) }
            .compactMapValues { gruppe in median(gruppe.map { groessenmass($0) }) }
        let mitUhrzeit = nachEroeffnung.filter { !$0.nurDatum }
        let revanche = mitUhrzeit.filter { t in
            guard let m = medianGroesse[misstEinsatz(t)], groessenmass(t) > m else { return false }
            return nachSchluss.contains { v in
                v.outcome == .loss && !v.nurDatum && v.id != t.id && v.closeTime <= t.openTime
                    && t.openTime.timeIntervalSince(v.closeTime) <= s.revancheMinuten * 60
            }
        }
        befunde.append(befund(.revancheTrade, revanche, stichprobe: mitUhrzeit.count))

        // Überhandeln: nur die Positionen über dem üblichen Maß des Tages, nicht der ganze Tag (Tim 05.10.2026).
        // Teilverkäufe zählen als ein Trade: alle Teile tragen die laufende Nummer ihrer Position.
        let jeTag = tradesJeTag(trades, zeitzone: zeitzone)
        if let grenze = ueberhandelnGrenze(jeTag: jeTag, schwellen: s) {
            var positionenJeTag: [Date: [String]] = [:]
            var betroffen: [Trade] = []
            for t in nachEroeffnung {
                let tag = t.eroeffnungstag(kalender)
                var positionen = positionenJeTag[tag] ?? []
                if !positionen.contains(t.positionsschluessel) { positionen.append(t.positionsschluessel) }
                positionenJeTag[tag] = positionen
                let nummer = (positionen.firstIndex(of: t.positionsschluessel) ?? 0) + 1
                if nummer > grenze { betroffen.append(t) }
            }
            befunde.append(befund(.ueberhandeln, betroffen, stichprobe: jeTag.count, wert: Decimal(grenze)))
        }

        // Stop nicht eingehalten: Verlust deutlich über 1 R. Nur Trades mit R aus dem Stop: Bei angenommenem
        // Risiko (`risikoAngenommen`) gibt es keinen Stop, der gebrochen werden könnte; ein Verlust über dem
        // geplanten Risiko ist „geplantes Risiko überschritten“ und steht in `RKennzahlen.verlusteUeber1R`.
        let mitStopR = nachEroeffnung.filter { $0.rMultiple != nil && !$0.risikoAngenommen }
        befunde.append(befund(.stopNichtEingehalten, mitStopR.filter { $0.rMultiple! < s.stopVerlustR },
                              stichprobe: mitStopR.count))

        // Gewinne zu früh: Gewinner, die weit vor dem gesetzten Ziel geschlossen wurden.
        let gewinnerMitZiel = nachEroeffnung.filter { $0.outcome == .win && zielanteil($0) != nil }
        befunde.append(befund(.gewinneZuFrueh, gewinnerMitZiel.filter { zielanteil($0)! < s.zielAnteil },
                              stichprobe: gewinnerMitZiel.count))

        // Verlierer laufen lassen: Verlierer im Schnitt deutlich länger gehalten als Gewinner.
        let k = Kennzahlen(trades: trades)
        if let g = k.haltedauerGewinner, let v = k.haltedauerVerlierer, g > 0, v / g > s.haltedauerFaktor {
            befunde.append(befund(.verliererLaufenLassen, mitUhrzeit.filter { $0.outcome == .loss },
                                  stichprobe: mitUhrzeit.count, wert: Decimal(v / g)))
        }

        // Verbilligen: Nachkauf in gleicher Richtung zu schlechterem Kurs, während die erste Position offen ist.
        let verbilligt = nachEroeffnung.filter { t in
            nachEroeffnung.contains { e in
                e.id != t.id && e.symbol == t.symbol && e.side == t.side
                    && e.openTime < t.openTime && t.openTime < e.closeTime
                    && (t.side == .buy ? t.openPrice < e.openPrice : t.openPrice > e.openPrice)
            }
        }
        befunde.append(befund(.verbilligen, verbilligt, stichprobe: n))

        befunde.append(befund(.ohneStop, nachEroeffnung.filter { $0.stopLoss == nil }, stichprobe: n))

        // Schwankende Größe: Risiko je Trade stark gestreut. Wie „Größe nach Gewinnserie“ nur mit Risiko aus
        // dem Stop: Ein vorgegebenes Standard-Risiko ist keine echte Positionsgröße.
        let risiken = mitStopR.compactMap(\.stopRisiko).map { NSDecimalNumber(decimal: $0).doubleValue }
        if risiken.count >= 2 {
            let mittel = risiken.reduce(0, +) / Double(risiken.count)
            let streuung = (risiken.map { ($0 - mittel) * ($0 - mittel) }.reduce(0, +) / Double(risiken.count)).squareRoot()
            if mittel > 0, streuung / mittel > s.variationskoeffizient {
                befunde.append(Befund(muster: .schwankendeGroesse, trades: [], netto: 0, summeR: nil,
                                      wert: Decimal(streuung / mittel), stichprobe: risiken.count))
            }
        }

        // Größe nach Gewinnserie: nach mehreren Gewinnen in Folge deutlich mehr Risiko.
        let medianRisiko = median(mitStopR.compactMap(\.stopRisiko))
        let nachSerie = mitStopR.filter { t in
            guard let medianRisiko, let risiko = t.stopRisiko, risiko > medianRisiko * s.groessenFaktor else {
                return false
            }
            let davor = nachSchluss.filter { $0.sicherGeschlossen(vor: t, kalender: kalender) }
            return davor.suffix(s.gewinnserie).count == s.gewinnserie
                && davor.suffix(s.gewinnserie).allSatisfy { $0.outcome == .win }
        }
        befunde.append(befund(.groesseNachGewinnserie, nachSerie, stichprobe: mitStopR.count))

        // Ständiges Umplanen: viele gelöschte Pending Orders.
        if let quote = Kennzahlen.stornoquote(ausgefuehrt: n, geloescht: geloeschteOrders), quote > s.stornoquote {
            befunde.append(Befund(muster: .staendigesUmplanen, trades: [], netto: 0, summeR: nil,
                                  wert: quote, stichprobe: n + geloeschteOrders))
        }
        return befunde.compactMap { $0 }
    }

    /// Positionen je Eröffnungstag: Tagesbeginn im Kalender der Zeitzone → Anzahl. Teilverkäufe einer Position
    /// zählen als eine (`positionsschluessel`). Für die Begründung „22 Trades an diesem Tag, üblich sind 10“.
    public static func tradesJeTag(_ trades: [Trade], zeitzone: TimeZone) -> [Date: Int] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        return Dictionary(grouping: trades) { $0.eroeffnungstag(kalender) }
            .mapValues { Set($0.map(\.positionsschluessel)).count }
    }

    /// Grenze für „Überhandeln“: Positionen eines Tages mit laufender Nummer darüber gelten als überhandelt.
    /// Ein eigenes Limit (`maxTradesProTag`) hat Vorrang; sonst Median der Positionen je Tag plus
    /// `ueberhandelnUeberMedian`, aber erst ab `ueberhandelnMindestTage` Tagen mit Trades. `nil`: keine Prüfung.
    /// Ein halber Median wird abgerundet (Median 4,5 + 2 ergibt 6): Gezählt wird in ganzen Positionen.
    public static func ueberhandelnGrenze(_ trades: [Trade], zeitzone: TimeZone,
                                          schwellen: Schwellen = Schwellen()) -> Int? {
        ueberhandelnGrenze(jeTag: tradesJeTag(trades, zeitzone: zeitzone), schwellen: schwellen)
    }

    static func ueberhandelnGrenze(jeTag: [Date: Int], schwellen s: Schwellen) -> Int? {
        if let limit = s.maxTradesProTag { return max(limit, 0) }
        let anzahlen = jeTag.values.sorted()
        guard !anzahlen.isEmpty, anzahlen.count >= s.ueberhandelnMindestTage else { return nil }
        let mitte = anzahlen.count / 2
        let medianTag = anzahlen.count % 2 == 1 ? anzahlen[mitte] : (anzahlen[mitte - 1] + anzahlen[mitte]) / 2
        return medianTag + s.ueberhandelnUeberMedian
    }

    /// Größe eines Trades für „mehr als üblich“ (Revanche). Bei Scheinen, Aktien, Fonds und Krypto der Einsatz
    /// (Eröffnungskurs mal Stück): Stückzahlen verschiedener Produkte sind nicht vergleichbar, ein Schein zu 3 €
    /// hat 700 Stück, einer zu 47 € 45 Stück. Bei CFD und allen übrigen Arten die Lots wie bisher.
    static func groessenmass(_ t: Trade) -> Decimal {
        misstEinsatz(t) ? t.openPrice * t.lots : t.lots
    }

    /// Wird die Größe als Einsatz gemessen? Verglichen wird nur innerhalb derselben Messart.
    static func misstEinsatz(_ t: Trade) -> Bool {
        switch t.produktart {
        case .derivat, .aktie, .fonds, .krypto: true
        case .cfd, .anleihe, .sonstiges, .unbekannt: false
        }
    }

    /// Erreichter Anteil der geplanten Bewegung bis zum Ziel. `nil` ohne Ziel auf der Gewinnseite.
    static func zielanteil(_ t: Trade) -> Decimal? {
        guard let ziel = t.takeProfit else { return nil }
        let geplant = t.side == .buy ? ziel - t.openPrice : t.openPrice - ziel
        let erzielt = t.side == .buy ? t.closePrice - t.openPrice : t.openPrice - t.closePrice
        return geplant > 0 ? erzielt / geplant : nil
    }

    static func median(_ werte: [Decimal]) -> Decimal? {
        guard !werte.isEmpty else { return nil }
        let s = werte.sorted()
        let mitte = s.count / 2
        return s.count % 2 == 1 ? s[mitte] : (s[mitte - 1] + s[mitte]) / 2
    }

    private static func befund(_ muster: Fehlermuster, _ trades: [Trade], stichprobe: Int,
                               wert: Decimal? = nil) -> Befund? {
        guard !trades.isEmpty else { return nil }
        let r = trades.compactMap(\.rMultiple)
        return Befund(muster: muster, trades: trades.map(\.id), netto: trades.map(\.netProfit).reduce(0, +),
                      summeR: r.isEmpty ? nil : r.reduce(0, +), wert: wert, stichprobe: stichprobe)
    }
}
