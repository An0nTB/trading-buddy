import Foundation
import TradingCore

extension Anfrage {
    /// Ausstiegsanalysen der App für `trades` (Doc 39, B4), mit dem Trade dieser Anfrage: nach dem Währungsangleich
    /// lautet `liegengelassen` damit in Kontowährung wie auf der Seite „Ausstieg“ der App.
    func ausstiegsanalysen(_ trades: [Trade]) -> [Ausstiegsanalyse] {
        let jeTrade = konto.ausstiegJeTrade
        return trades.compactMap { t in jeTrade[t.id].map { $0.analyse(t) } }
    }

    /// Abschnitt „Ausstieg“ der Auswertung: Mediane aus `Ausstiegsauswertung` wie in der App, nur beschreibend.
    /// Leer, wenn die App für keinen Trade des Zeitraums Kerzen hat.
    func ausstiegsabschnitt(_ trades: [Trade]) -> [String] {
        let analysen = ausstiegsanalysen(trades)
        guard !analysen.isEmpty else { return [] }
        let a = Ausstiegsauswertung(analysen, gleicheWaehrung: true)
        let verlierer = a.verliererMitR > 0 ? "\(a.verliererMitEinemRPlus) von \(a.verliererMitR)" : "–"
        let summe = a.summeLiegengelassen.map { Format.zahl($0) + " " + konto.waehrung } ?? "–"
        var t = ["\n## Ausstieg (Kursverlauf während der Trades, aus Kerzen in der App)"]
        t.append(Format.tabelle(["Kennzahl", "Wert"], [
            ["Trades mit Kursen", "\(a.anzahl) von \(trades.count)"],
            ["Anteil der MFE erzielt, Median", Format.prozent(a.medianEffizienz)],
            ["MAE der Gewinner, Median", Format.r(a.medianMaeRGewinner)],
            ["MFE, Median", Format.r(a.medianMfeR)],
            ["Verlierer, die 1 R im Plus lagen", verlierer],
            ["Bis zur MFE offen, Summe vor Kosten", summe],
        ]))
        t.append("MAE: größter Abstand gegen den Trade, MFE: größter Abstand für den Trade, beide als Abstand in R "
            + "(nur Trades mit Stop). Median statt Mittelwert. Rückblick auf vergangene Kurse, keine Aussage über "
            + "künftige; die Summe ist kein erreichbarer Betrag, weil der beste Kurs erst hinterher feststeht.")
        if let quellen = kerzenquellen(trades) { t.append(quellen) }
        if a.anzahlUnscharf > 0 {
            t.append("\(a.anzahlUnscharf) Trades mit Kerzen über Ein- oder Ausstieg hinaus (Stunden- oder Tageskerzen): "
                + "MAE und MFE dort eher zu groß.")
        }
        return t
    }

    /// Tabelle für `hole_trades`: MAE, MFE und Bewegung nach dem Ausstieg der gezeigten Trades mit Kerzen.
    /// Abstände in R wie in der App, ohne Stop als Anteil am Einstiegskurs; leer ohne Analysen.
    func ausstiegstabelle(_ trades: [Trade]) -> [String] {
        let jeTrade = konto.ausstiegJeTrade
        let zeilen: [[String]] = trades.compactMap { t in
            guard let a = jeTrade[t.id]?.analyse(t) else { return nil }
            let stop = t.stopLoss.map { t.side == .buy ? t.openPrice - $0 : $0 - t.openPrice }
            func abstand(_ punkte: Decimal?) -> String {
                guard let punkte else { return "–" }
                if let stop, stop > 0 { return Format.r(punkte / stop) }
                return t.openPrice > 0 ? Format.prozent(punkte / t.openPrice) : "–"
            }
            return [t.id, abstand(a.mae), abstand(a.mfe), Format.prozent(a.effizienz), Format.zahl(a.liegengelassen),
                    abstand(a.nachAusstiegFuer), abstand(a.nachAusstiegGegen), a.unscharf ? "unscharf" : "–"]
        }
        guard !zeilen.isEmpty else { return [] }
        return ["\nAusstieg (aus Kerzen in der App; Rückblick, keine Aussage über künftige Kurse):",
                Format.tabelle(["Ticket", "MAE", "MFE", "MFE erzielt", "Bis MFE offen", "Danach für", "Danach gegen",
                                "Kerzen"], zeilen)] + (kerzenquellen(trades).map { [$0] } ?? [])
    }

    /// Herkunft der Kerzen hinter den Ausstiegsanalysen von `trades` mit Anzahl, dazu die Hinweise der App, etwa
    /// Geldkurs (Bid) bei MetaTrader oder USDT statt USD bei Binance (Doc 59 B9); `nil` ohne Angaben (ältere App).
    func kerzenquellen(_ trades: [Trade]) -> String? {
        let jeTrade = konto.ausstiegJeTrade
        let analysen = trades.compactMap { jeTrade[$0.id] }
        var anzahl: [String: Int] = [:]
        for a in analysen { if let q = a.quelle { anzahl[q, default: 0] += 1 } }
        guard !anzahl.isEmpty else { return nil }
        let teile = anzahl.keys.sorted().map { "\(Format.kurz($0, zeichen: 30)) \(anzahl[$0]!)" }
        var text = "Kerzen der App: \(teile.joined(separator: ", ")) Trades."
        var gesehen: Set<String> = []
        for a in analysen {
            guard let h = a.hinweis.map({ Format.kurz($0, zeichen: 200) }), gesehen.insert(h).inserted else { continue }
            text += " " + (h.hasSuffix(".") ? h : h + ".")
        }
        return text
    }

    /// Zeile für „Datenlage“, wenn die App für dieses Konto Ausstiegsanalysen mitschreibt; sonst `nil`.
    func ausstiegslage(_ trades: [Trade]) -> String? {
        guard konto.ausstieg != nil else { return nil }
        let mitKursen = ausstiegsanalysen(trades).count
        let mitUhrzeit = trades.filter { !$0.nurDatum }.count
        return "- Ausstieg: \(mitKursen) von \(mitUhrzeit) Trades mit Uhrzeit haben Kerzen in der App (Seite „Ausstieg“); "
            + "MAE und MFE einzelner Trades über hole_trades."
    }
}
