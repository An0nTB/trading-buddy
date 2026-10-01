import Foundation

extension Fehlermuster {
    /// Prüft alle Regeln und liefert nur die Muster mit Treffern.
    /// - Parameters:
    ///   - geloeschteOrders: Anzahl gelöschter Pending Orders im selben Zeitraum.
    ///   - zeitzone: Tagesgrenze für „Trades pro Tag“, in der Regel die des Nutzers.
    public static func pruefe(_ trades: [Trade], geloeschteOrders: Int = 0, zeitzone: TimeZone,
                              schwellen s: Schwellen = Schwellen()) -> [Befund] {
        let nachEroeffnung = trades.sorted { ($0.openTime, $0.id) < ($1.openTime, $1.id) }
        let nachSchluss = trades.sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
        let n = trades.count
        var befunde: [Befund?] = []

        // Revanche: kurz nach einem Verlust eröffnet, mit mehr Lots als üblich.
        let medianLots = median(trades.map(\.lots))
        let revanche = nachEroeffnung.filter { t in
            guard let medianLots, t.lots > medianLots else { return false }
            return nachSchluss.contains { v in
                v.outcome == .loss && v.id != t.id && v.closeTime <= t.openTime
                    && t.openTime.timeIntervalSince(v.closeTime) <= s.revancheMinuten * 60
            }
        }
        befunde.append(befund(.revancheTrade, revanche, stichprobe: n))

        // Überhandeln: Tage mit deutlich mehr Trades als üblich.
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let jeTag = Dictionary(grouping: nachEroeffnung) { kalender.startOfDay(for: $0.openTime) }
        if let medianTag = median(jeTag.values.map { Decimal($0.count) }) {
            let grenze = medianTag + Decimal(s.ueberhandelnUeberMedian)
            let betroffen = nachEroeffnung.filter { Decimal(jeTag[kalender.startOfDay(for: $0.openTime)]!.count) > grenze }
            befunde.append(befund(.ueberhandeln, betroffen, stichprobe: jeTag.count))
        }

        // Stop nicht eingehalten: Verlust deutlich über 1 R.
        let mitR = nachEroeffnung.filter { $0.rMultiple != nil }
        befunde.append(befund(.stopNichtEingehalten, mitR.filter { $0.rMultiple! < s.stopVerlustR },
                              stichprobe: mitR.count))

        // Gewinne zu früh: Gewinner, die weit vor dem gesetzten Ziel geschlossen wurden.
        let gewinnerMitZiel = nachEroeffnung.filter { $0.outcome == .win && zielanteil($0) != nil }
        befunde.append(befund(.gewinneZuFrueh, gewinnerMitZiel.filter { zielanteil($0)! < s.zielAnteil },
                              stichprobe: gewinnerMitZiel.count))

        // Verlierer laufen lassen: Verlierer im Schnitt deutlich länger gehalten als Gewinner.
        let k = Kennzahlen(trades: trades)
        if let g = k.haltedauerGewinner, let v = k.haltedauerVerlierer, g > 0, v / g > s.haltedauerFaktor {
            befunde.append(befund(.verliererLaufenLassen, nachEroeffnung.filter { $0.outcome == .loss },
                                  stichprobe: n, wert: Decimal(v / g)))
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

        // Schwankende Größe: Risiko je Trade stark gestreut.
        let risiken = mitR.compactMap(\.risk).map { NSDecimalNumber(decimal: $0).doubleValue }
        if risiken.count >= 2 {
            let mittel = risiken.reduce(0, +) / Double(risiken.count)
            let streuung = (risiken.map { ($0 - mittel) * ($0 - mittel) }.reduce(0, +) / Double(risiken.count)).squareRoot()
            if mittel > 0, streuung / mittel > s.variationskoeffizient {
                befunde.append(Befund(muster: .schwankendeGroesse, trades: [], netto: 0, summeR: nil,
                                      wert: Decimal(streuung / mittel), stichprobe: risiken.count))
            }
        }

        // Größe nach Gewinnserie: nach mehreren Gewinnen in Folge deutlich mehr Risiko.
        let medianRisiko = median(mitR.compactMap(\.risk))
        let nachSerie = mitR.filter { t in
            guard let medianRisiko, let risiko = t.risk, risiko > medianRisiko * s.groessenFaktor else { return false }
            let davor = nachSchluss.filter { $0.closeTime <= t.openTime && $0.id != t.id }
            return davor.suffix(s.gewinnserie).count == s.gewinnserie
                && davor.suffix(s.gewinnserie).allSatisfy { $0.outcome == .win }
        }
        befunde.append(befund(.groesseNachGewinnserie, nachSerie, stichprobe: mitR.count))

        // Ständiges Umplanen: viele gelöschte Pending Orders.
        if let quote = Kennzahlen.stornoquote(ausgefuehrt: n, geloescht: geloeschteOrders), quote > s.stornoquote {
            befunde.append(Befund(muster: .staendigesUmplanen, trades: [], netto: 0, summeR: nil,
                                  wert: quote, stichprobe: n + geloeschteOrders))
        }
        return befunde.compactMap { $0 }
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
