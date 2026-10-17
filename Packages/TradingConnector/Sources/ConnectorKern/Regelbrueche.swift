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
    /// - Parameter ohneKurs: Trades ohne EZB-Kurs im selben Zeitraum; ihre Verstöße zählen mit wie in App und PDF.
    func verstoesse(_ trades: [Trade], ohneKurs: [Trade] = []) -> [Regelverstoss] {
        let ids = Set((trades + ohneKurs).map(\.id))
        let andere = andereWaehrungen.values.flatMap { $0 }
        // Setup-Grenzen aus den Playbookkarten, offene Positionen mit Risiko in Kontowährung aus der App.
        return Regelpruefung.pruefe(konto.trades + andere, regeln: konto.regeln ?? Handelsregeln(),
                                    zeitzone: zeitzone, manuell: manuellVerletzt, ohneBetrag: Set(andere.map(\.id)),
                                    setups: konto.journal.compactMapValues(\.setup),
                                    playbook: (export.playbook ?? []).map(\.setupRegeln),
                                    offene: konto.offene ?? [], jetzt: export.erstellt)
            .filter { ids.contains($0.trade) }
    }

    /// Fehlende Grundlagen dürfen bei den Grenzen für offene Positionen keine Entwarnung ergeben.
    var offeneRegelnUnvollstaendig: Bool {
        let regeln = export.konten.first { $0.broker == konto.broker && $0.kontonummer == konto.kontonummer }?.regeln
            ?? konto.regeln
        guard let regeln else { return false }
        let risiko = regeln.maxOffenesRisiko != nil || regeln.maxOffenesRisikoProzent != nil
        guard regeln.maxOffenePositionen != nil || risiko else { return false }
        guard konto.offeneVollstaendig == true, let offene = konto.offene else { return true }
        let trades = konto.trades + andereWaehrungen.values.flatMap { $0 }
        if offene.contains(where: \.nurDatum) || trades.contains(where: \.nurDatum) { return true }
        guard risiko else { return false }
        if konto.waehrung != kontowaehrung || !andereWaehrungen.isEmpty
            || offene.contains(where: { $0.risiko == nil }) || trades.contains(where: { $0.risk == nil }) {
            return true
        }
        if regeln.maxOffenesRisikoProzent != nil {
            var kalender = Calendar(identifier: .gregorian)
            kalender.timeZone = zeitzone
            let tage = trades.map { $0.eroeffnungstag(kalender) } + offene.map {
                Trade.tagesbeginn($0.openTime, nurDatum: $0.nurDatum, kalender: kalender)
            }
            return tage.contains { (regeln.kontostand?.stand(bei: $0, trades: trades) ?? 0) <= 0 }
        }
        return false
    }

    /// Abschnitt „Eigene Handelsregeln“; leer, wenn weder Regeln noch Journal-Verstöße vorliegen.
    /// Trades ohne EZB-Kurs (`ohneKurs`) im Zeitraum zählen wie in App und PDF bei Anzahl und Verstößen mit
    /// (Tim 02.10.2026), ihre Beträge nicht.
    /// - Parameter propFirm: Zeile zur Prop-Firm-Prüfung aus `propFirmzeile`; ohne sie nur der Hinweis auf die App.
    func regelabschnitt(_ trades: [Trade], propFirm: String? = nil) -> [String] {
        let ohneKurs = self.ohneKurs.filter { zeitraum.enthaelt($0.closeTime) }
        let verstoesse = verstoesse(trades, ohneKurs: ohneKurs)
        let geprueft = trades.count + ohneKurs.count
        let unvollstaendig = offeneRegelnUnvollstaendig
        guard konto.regeln != nil || !verstoesse.isEmpty else { return [] }
        var t = ["\n## Eigene Handelsregeln (eingetragen in der App, geprüft nach dem Import)"]
        t.append("Regeln: " + (konto.regeln.map { Self.regeltext($0, zeitzone: zeitzone) } ?? "keine Grenzen eingetragen") + ".")
        if unvollstaendig {
            t.append("Offene Positionen und offenes Risiko: nicht vollständig geprüft; Positionsbestand, Uhrzeiten, "
                + "Risikobeträge oder Kontostand fehlen oder liegen nicht in Kontowährung vor.")
        }
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
        if zeilen.isEmpty && !unvollstaendig {
            t.append("Kein Verstoß im Zeitraum (\(geprueft) Trades geprüft).")
        } else if !zeilen.isEmpty {
            t.append(Format.tabelle(["Regel", "Trades", "Tage", "Netto dieser Trades"], zeilen))
            if !unvollstaendig {
                let betroffen = Set(verstoesse.map(\.trade))
                let mit = Kennzahlen(trades: trades.filter { betroffen.contains($0.id) })
                let ohne = Kennzahlen(trades: trades.filter { !betroffen.contains($0.id) })
                t.append("Trades mit mindestens einem Verstoß: \(betroffen.count) von \(geprueft), netto \(Format.zahl(mit.netto)), "
                    + "Erwartungswert \(Format.r(mit.erwartungswertR)). Ohne Verstoß: \(geprueft - betroffen.count) Trades, netto "
                    + "\(Format.zahl(ohne.netto)), Erwartungswert \(Format.r(ohne.erwartungswertR)). "
                    + "Ein Trade kann mehrere Regeln zugleich verletzen.")
            }
        }
        if !ohneKurs.isEmpty {
            let mitVerstoss = Set(verstoesse.map(\.trade)).intersection(ohneKurs.map(\.id)).count
            t.append("Mitgezählt wie in der App: \(ohneKurs.count) Trades in anderer Währung ohne EZB-Kurs am "
                + "Schlusstag, davon \(mitVerstoss) mit Verstoß. Sie zählen bei Anzahl und Verstößen, ihre Beträge "
                + "fehlen in Netto, Erwartungswert und Tagesverlust.")
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

    static func regeltext(_ r: Handelsregeln, zeitzone: TimeZone) -> String {
        var teile: [String] = []
        if let n = r.maxTradesJeTag { teile.append("höchstens \(n) Trades je Tag") }
        if let n = r.stoppNachVerlusten { teile.append("Schluss nach \(n) Verlusten in Folge am Tag") }
        if let b = r.maxTagesverlust { teile.append("Tagesverlust höchstens \(Format.zahl(b))") }
        if let b = r.maxRisikoJeTrade { teile.append("Risiko je Trade höchstens \(Format.zahl(b))") }
        if let p = r.maxTagesverlustProzent { teile.append("Tagesverlust höchstens \(Format.zahl(p)) % vom Kontostand") }
        if let p = r.maxRisikoJeTradeProzent { teile.append("Risiko je Trade höchstens \(Format.zahl(p)) % vom Kontostand") }
        if let b = r.maxMonatsverlust { teile.append("Monatsverlust höchstens \(Format.zahl(b))") }
        if let p = r.maxMonatsverlustProzent { teile.append("Monatsverlust höchstens \(Format.zahl(p)) % vom Kontostand") }
        if let n = r.maxOffenePositionen { teile.append("höchstens \(n) Positionen gleichzeitig offen") }
        if let b = r.maxOffenesRisiko { teile.append("offenes Risiko höchstens \(Format.zahl(b))") }
        if let p = r.maxOffenesRisikoProzent { teile.append("offenes Risiko höchstens \(Format.zahl(p)) % vom Kontostand") }
        if let k = r.kontostand {
            teile.append("Kontostand für Prozentgrenzen: \(Format.zahl(k.betrag)) am "
                + "\(Format.datum(k.seit, zeitzone, mitZeit: false)), fortgeschrieben mit "
                + "den Ergebnissen")
        }
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
        case .monatsverlust: "Monatsverlust"
        case .tradesJeSetup: "Trades am Tag je Setup"
        case .haltedauer: "Haltedauer des Setups"
        case .offenePositionen: "Offene Positionen"
        case .offenesRisiko: "Offenes Risiko"
        }
    }
}
