import Foundation
import TradingCore

/// Verstöße gegen die eigenen Handelsregeln und Muster für die Auswertung (P8). Gerechnet mit denselben
/// Funktionen wie in der App (`Regelpruefung`, `MusterFinder`); der Connector speichert nichts.
extension Anfrage {
    /// Tickets, die im Journal als „nicht regeltreu“ stehen; sie zählen wie in der App als Verstoß `manuell`.
    var manuellVerletzt: Set<String> {
        Set(konto.journal.filter { $0.value.regeltreue == false }.keys)
    }

    /// Verstöße der Trades in `trades`, geprüft über den ganzen Tag. Anzahl-Regeln („Trades je Tag“,
    /// „Stopp nach Verlusten“) und Journal-Verstöße zählen alle Trades des Kontos in jeder Währung wie in der App;
    /// Betragsgrenzen nur die Trades dieser Antwort, denn Beträge verschiedener Währungen gehören nicht in eine Summe.
    /// Dieselbe Prüfung wie in der App über `ohneBetrag` (Rechenkern 0.22.0, Dritter Gegencheck G1 und G2).
    func verstoesse(_ trades: [Trade]) -> [Regelverstoss] {
        let ids = Set(trades.map(\.id))
        let andere = andereWaehrungen.values.flatMap { $0 }
        return Regelpruefung.pruefe(konto.trades + andere, regeln: konto.regeln ?? Handelsregeln(),
                                    zeitzone: zeitzone, manuell: manuellVerletzt, ohneBetrag: Set(andere.map(\.id)))
            .filter { ids.contains($0.trade) }
    }

    /// Abschnitt „Eigene Handelsregeln“; leer, wenn weder Regeln noch Journal-Verstöße vorliegen.
    /// - Parameter propFirm: Zeile zur Prop-Firm-Prüfung aus `propFirmzeile`; ohne sie nur der Hinweis auf die App.
    func regelabschnitt(_ trades: [Trade], propFirm: String? = nil) -> [String] {
        let verstoesse = verstoesse(trades)
        guard konto.regeln != nil || !verstoesse.isEmpty else { return [] }
        var t = ["\n## Eigene Handelsregeln (eingetragen in der App, geprüft nach dem Import)"]
        t.append("Regeln: " + (konto.regeln.map(Self.regeltext) ?? "keine Grenzen eingetragen") + ".")
        let zone = zeitzone
        let zeilen: [[String]] = Regelverstoss.Art.allCases.compactMap { art in
            let teil = verstoesse.filter { $0.art == art }
            guard !teil.isEmpty else { return nil }
            let ids = Set(teil.map(\.trade))
            let netto = trades.filter { ids.contains($0.id) }.map(\.netProfit).reduce(0, +)
            let tage = Set(teil.map(\.tag)).sorted().map { Format.datum($0, zone, mitZeit: false) }
            let tagtext = tage.count > 5 ? tage.prefix(5).joined(separator: ", ") + " …" : tage.joined(separator: ", ")
            return [art.bezeichnung, "\(ids.count)", "\(tage.count) (\(tagtext))", Format.zahl(netto)]
        }
        if zeilen.isEmpty {
            t.append("Kein Verstoß im Zeitraum (\(trades.count) Trades geprüft).")
        } else {
            t.append(Format.tabelle(["Regel", "Trades", "Tage", "Netto dieser Trades"], zeilen))
            let betroffen = Set(verstoesse.map(\.trade))
            let mit = Kennzahlen(trades: trades.filter { betroffen.contains($0.id) })
            let ohne = Kennzahlen(trades: trades.filter { !betroffen.contains($0.id) })
            t.append("Trades mit mindestens einem Verstoß: \(mit.anzahl) von \(trades.count), netto \(Format.zahl(mit.netto)), "
                + "Erwartungswert \(Format.r(mit.erwartungswertR)). Ohne Verstoß: \(ohne.anzahl) Trades, netto "
                + "\(Format.zahl(ohne.netto)), Erwartungswert \(Format.r(ohne.erwartungswertR)). "
                + "Ein Trade kann mehrere Regeln zugleich verletzen.")
        }
        if let propFirm {
            t.append(propFirm)
        } else if konto.regeln?.propFirm != nil {
            t.append("Prop-Firm-Regeln sind eingetragen; ihre Prüfung zeigt die App, sie ist hier nicht enthalten.")
        }
        return t
    }

    /// Abschnitt „Muster“: Gruppen, die sich deutlich vom Rest unterscheiden, mit Zufallsprüfung.
    /// Leer, wenn keine Gruppe und kein Rest 30 Trades erreicht.
    /// - Parameter vorgegeben: schon gefundene Muster (`Zeitraumbericht.muster`), sonst sucht der Abschnitt selbst.
    func musterabschnitt(_ trades: [Trade], vorgegeben: [Muster]? = nil, hoechstens: Int = 5) -> [String] {
        let gefunden = vorgegeben ?? MusterFinder.finde(trades, zeitzone: zeitzone)
        var gezeigt: [Muster] = []
        for m in gefunden where gezeigt.count < hoechstens {
            // Bei zwei Gruppen (etwa Kauf und Verkauf) ist das Gegenstück dieselbe Aussage.
            let gegenstueck = gezeigt.contains {
                $0.aufteilung == m.aufteilung && $0.anzahl == m.anzahlRest && $0.anzahlRest == m.anzahl
                    && $0.effekt == -m.effekt
            }
            if !gegenstueck { gezeigt.append(m) }
        }
        guard !gezeigt.isEmpty else { return [] }
        let zeilen: [[String]] = gezeigt.map { m in
            ["\(Ausgabe.dimensionsname(m.aufteilung)): \(Ausgabe.gruppenname(m.schluessel, m.aufteilung))",
             "\(m.anzahl) / \(m.anzahlRest)", Format.zahl(m.erwartungswert), Format.zahl(m.erwartungswertRest),
             Format.zahl(m.effekt), Format.zahl(m.zufallsanteil(trades: trades), stellen: 3)]
        }
        return ["\n## Muster (beschreiben vergangene Trades, keine Prognose)",
                Format.tabelle(["Gruppe", "Trades / Rest", "Netto je Trade", "Rest je Trade", "Unterschied",
                                "Zufallsanteil"], zeilen),
                "Nur Gruppen mit je mindestens 30 Trades in Gruppe und Rest (\(gefunden.count) gefunden), nach Größe des "
                    + "Unterschieds. Zufallsanteil: Anteil von 1.000 zufällig gezogenen Gruppen gleicher Größe mit "
                    + "mindestens so großem Unterschied; unter 0,05 schwer mit Zufall zu erklären. Wer viele Gruppen "
                    + "vergleicht, findet auch zufällige Unterschiede."]
    }

    static func regeltext(_ r: Handelsregeln) -> String {
        var teile: [String] = []
        if let n = r.maxTradesJeTag { teile.append("höchstens \(n) Trades je Tag") }
        if let n = r.stoppNachVerlusten { teile.append("Schluss nach \(n) Verlusten in Folge am Tag") }
        if let b = r.maxTagesverlust { teile.append("Tagesverlust höchstens \(Format.zahl(b))") }
        if let b = r.maxRisikoJeTrade { teile.append("Risiko je Trade höchstens \(Format.zahl(b))") }
        if r.propFirm != nil { teile.append("Prop-Firm-Regeln") }
        return teile.isEmpty ? "keine Grenzen eingetragen" : teile.joined(separator: "; ")
    }
}

extension Regelverstoss.Art {
    /// Gleiche Wortwahl wie die Regel-Ampel der App.
    var bezeichnung: String {
        switch self {
        case .tagesverlust: "Tagesverlust"
        case .tradesJeTag: "Trades am Tag"
        case .stoppNachVerlusten: "Verluste in Folge"
        case .risikoJeTrade: "Risiko je Trade"
        case .manuell: "Im Journal „nicht regeltreu“"
        }
    }
}
