import Foundation
import TradingCore

/// Werkzeug `hole_tiefenanalyse`: dieselben Rechnungen wie die Seite „Auswertung“ der App (`Tiefenanalyse`,
/// `RKennzahlen`, `Leistungsscore`, `BestExitAuswertung`), damit Claude dieselben Zahlen sieht (Doc 02 Nr. 65).
/// Beträge in Kontowährung nach dem Währungsangleich wie `hole_auswertung`.
extension Ausgabe {
    public static func tiefenanalyse(_ anfrage: Anfrage) -> String {
        let b = anfrage.bericht()
        let a = b.auswertung
        let zone = anfrage.zeitzone
        let trades = a.trades
        var t = ["# Henry · Tiefenanalyse \(Format.zeitraum(a.zeitraum, zone))", kopf(anfrage)]
        if let hinweis = anfrage.vorgabe { t.append(hinweis) }
        guard !trades.isEmpty else {
            t.append("Keine Trades im Zeitraum.")
            return t.joined(separator: "\n")
        }
        t.append(contentsOf: rAbschnitt(trades))
        t.append(contentsOf: heatmapAbschnitt(trades, zone))
        t.append(contentsOf: staerkenAbschnitt(anfrage, trades))
        t.append(contentsOf: musterkostenAbschnitt(a))
        t.append(contentsOf: drawdownAbschnitt(trades, zone))
        t.append(contentsOf: scoreAbschnitt(anfrage, b))
        t.append(contentsOf: anfrage.bestExitAbschnitt(trades))

        t.append("\n## Datenlage")
        let k = a.kennzahlen
        t.append(k.genugDaten ? "- \(k.anzahl) Trades: ab 30 belastbar, Gruppen darunter nur beschreiben."
                              : "- Nur \(k.anzahl) Trades (unter 30): nur beschreiben, nicht folgern.")
        let ohneUhrzeit = trades.filter(\.nurDatum).count
        if ohneUhrzeit > 0 {
            t.append("- \(ohneUhrzeit) Trades nur mit Datum: fehlen bei Wochentag × Stunde, Stunde und Haltedauer.")
        }
        t.append("- Die App zeigt dieselben Rechnungen auf der Seite „Auswertung“; Trades einer Gruppe über hole_trades "
            + "mit ticket.")
        t.append("\n" + Rezept.tiefenText)
        if anfrage.export.personaTon { t.append(Rezept.personaRegel) }
        return t.joined(separator: "\n")
    }

    /// R-Kennzahlen (`RKennzahlen`); R aus dem Stop oder, ohne Stop, aus dem geplanten Risiko (angenommen).
    static func rAbschnitt(_ trades: [Trade]) -> [String] {
        let r = RKennzahlen(trades: trades)
        var t = ["\n## Ergebnis in R"]
        guard r.anzahlMitR > 0 else {
            t.append("Kein Trade mit R: weder Stop noch geplantes Risiko.")
            return t
        }
        let angenommen = trades.filter(\.risikoAngenommen).count
        let mitR = "\(r.anzahlMitR) von \(trades.count)" + (angenommen > 0 ? ", davon \(angenommen) angenommen" : "")
        t.append(Format.tabelle(["Kennzahl", "Wert"], [
            ["Trades mit R", mitR],
            ["Ø Gewinn / Ø Verlust", "\(Format.r(r.durchschnittGewinnR)) / \(Format.r(r.durchschnittVerlustR))"],
            ["Erwartungswert", Format.r(r.erwartungswertR)],
            ["Größter Verlust", Format.r(r.groessterVerlustR)],
            ["Verluste über 1 R", "\(r.verlusteUeber1R) (\(Format.prozent(r.anteilVerlusteUeber1R)) der Verlierer mit R)"],
        ]))
        if angenommen > 0 {
            t.append("Angenommen heißt: ohne Stop, R aus dem in der App eingetragenen geplanten Risiko.")
        }
        return t
    }

    /// Beste und schlechteste Felder Wochentag × Stunde der Eröffnung (`Tiefenanalyse.heatmap`), nur belastbare.
    static func heatmapAbschnitt(_ trades: [Trade], _ zone: TimeZone) -> [String] {
        let karte = Tiefenanalyse.heatmap(trades, zeitzone: zone)
        var t = ["\n## Wochentag × Stunde der Eröffnung (Felder ab \(karte.mindestanzahl) Trades)"]
        let belastbar = karte.zellen.filter(\.belastbar)
        // Bei gleichem Netto früherer Wochentag und frühere Stunde zuerst.
        func vorher(_ x: Tiefenanalyse.HeatmapZelle, _ y: Tiefenanalyse.HeatmapZelle, absteigend: Bool) -> Bool {
            if x.netto != y.netto { return absteigend ? x.netto > y.netto : x.netto < y.netto }
            return (x.wochentag, x.stunde) < (y.wochentag, y.stunde)
        }
        let beste = belastbar.filter { $0.netto > 0 }.sorted { vorher($0, $1, absteigend: true) }
        let schlechteste = belastbar.filter { $0.netto < 0 }.sorted { vorher($0, $1, absteigend: false) }
        if beste.isEmpty && schlechteste.isEmpty {
            t.append("Kein Feld mit mindestens \(karte.mindestanzahl) Trades und Netto ungleich 0 "
                + "(\(karte.zellen.count) Felder mit Trades).")
        } else {
            func zeile(_ zelle: Tiefenanalyse.HeatmapZelle, _ art: String) -> [String] {
                ["\(gruppenname(String(zelle.wochentag), .wochentag)) \(zelle.stunde) Uhr", art, "\(zelle.anzahl)",
                 Format.zahl(zelle.netto), Format.prozent(zelle.trefferquote), Format.r(zelle.durchschnittR)]
            }
            let zeilen: [[String]] = beste.prefix(3).map { zeile($0, "stark") }
                + schlechteste.prefix(3).map { zeile($0, "schwach") }
            t.append(Format.tabelle(["Feld", "Art", "Trades", "Netto", "Treffer", "Ø R"], zeilen))
            t.append("\(belastbar.count) von \(karte.zellen.count) Feldern mit Trades haben mindestens "
                + "\(karte.mindestanzahl) Trades.")
        }
        if karte.ohneUhrzeit > 0 { t.append("\(karte.ohneUhrzeit) Trades ohne Uhrzeit fehlen hier.") }
        return t
    }

    /// Stärkste und schwächste Gruppen (`Tiefenanalyse.staerkenUndSchwaechen`), Setup aus dem Journal.
    static func staerkenAbschnitt(_ anfrage: Anfrage, _ trades: [Trade]) -> [String] {
        var setups: [Trade.ID: String] = [:]
        for trade in trades {
            if let setup = anfrage.journal(trade)?.setup, !setup.isEmpty { setups[trade.id] = setup }
        }
        let s = Tiefenanalyse.staerkenUndSchwaechen(trades, zeitzone: anfrage.zeitzone, setups: setups)
        var t = ["\n## Stärken und Schwächen (Gruppen ab \(s.mindestanzahl) Trades)"]
        guard !s.staerkste.isEmpty || !s.schwaechste.isEmpty else {
            t.append("Keine Gruppe mit mindestens \(s.mindestanzahl) Trades und Netto ungleich 0.")
            return t
        }
        func zeile(_ g: Tiefenanalyse.Gruppenbefund, _ art: String) -> [String] {
            [merkmalname(g.dimension), gruppenname(g), art, "\(g.anzahl)", Format.zahl(g.netto),
             Format.prozent(g.trefferquote), Format.r(g.durchschnittR)]
        }
        let zeilen: [[String]] = s.staerkste.map { zeile($0, "stark") } + s.schwaechste.map { zeile($0, "schwach") }
        t.append(Format.tabelle(["Merkmal", "Gruppe", "Art", "Trades", "Netto", "Treffer", "Ø R"], zeilen))
        t.append("Merkmale: Wochentag, Stunde der Eröffnung, Haltedauer, Symbol, Schlussmonat"
            + (setups.isEmpty ? "; Setup fehlt, weil im Journal keins eingetragen ist." : ", Setup (Journal)."))
        return t
    }

    static func merkmalname(_ d: Tiefenanalyse.Gruppendimension) -> String {
        switch d {
        case .wochentag: "Wochentag"
        case .stunde: "Stunde"
        case .haltedauer: "Haltedauer"
        case .symbol: "Symbol"
        case .setup: "Setup"
        case .monat: "Monat"
        }
    }

    static func gruppenname(_ g: Tiefenanalyse.Gruppenbefund) -> String {
        switch g.dimension {
        case .wochentag: gruppenname(g.schluessel, .wochentag)
        case .stunde: gruppenname(g.schluessel, .stunde)
        case .haltedauer: gruppenname(g.schluessel, .haltedauer)
        case .symbol, .setup, .monat: g.schluessel
        }
    }

    /// Was die Fehlermuster gekostet haben (`Tiefenanalyse.fehlermusterKosten`), teuerstes zuerst.
    static func musterkostenAbschnitt(_ a: Auswertung) -> [String] {
        let kosten = Tiefenanalyse.fehlermusterKosten(a)
        var t = ["\n## Kosten der Fehlermuster"]
        guard !kosten.isEmpty else {
            t.append("Kein Fehlermuster mit Treffern im Zeitraum.")
            return t
        }
        let zeilen: [[String]] = kosten.map { k in
            [k.muster.bezeichnung + (k.istRegelbruch ? " (Regelbruch)" : ""), "\(k.anzahl)", Format.zahl(k.netto),
             "\(Format.r(k.summeR)) (\(k.anzahlMitR))", Format.zahl(k.nettoOhne)]
        }
        t.append(Format.tabelle(["Muster", "Trades", "Netto", "Summe R (Trades mit R)", "Netto ohne diese"], zeilen))
        t.append("„Netto ohne diese“ nur bei Regelbrüchen: das Ergebnis des Zeitraums ohne diese Trades. "
            + "Ein Trade kann mehreren Mustern angehören; die Zeilen nicht addieren.")
        return t
    }

    /// Größter Rückgang vom Hoch und längste Serien (`Tiefenanalyse.drawdown`), ab Kontostand 0 im Zeitraum.
    static func drawdownAbschnitt(_ trades: [Trade], _ zone: TimeZone) -> [String] {
        let d = Tiefenanalyse.drawdown(trades)
        var t = ["\n## Rückgang und Serien"]
        if d.maxDrawdown > 0, let tief = d.tiefpunkt {
            var zeile = "Größter Rückgang \(Format.zahl(d.maxDrawdown))"
            zeile += d.hochVorMaxDrawdown.map { " vom Hoch am \(Format.datum($0, zone, mitZeit: false))" }
                ?? " vom Start des Zeitraums"
            zeile += " bis zum Tiefpunkt am \(Format.datum(tief, zone, mitZeit: false)); "
            if let erholt = d.erholt {
                zeile += "wieder erreicht am \(Format.datum(erholt, zone, mitZeit: false)), "
                    + "\(Format.dauer(d.dauerBisErholung)) nach dem Tiefpunkt."
            } else {
                zeile += "bis Ende des Zeitraums nicht wieder erreicht."
            }
            t.append(zeile)
        } else {
            t.append("Kein Rückgang vom Hoch im Zeitraum.")
        }
        func serie(_ s: Tiefenanalyse.Serie, _ name: String) -> String {
            guard s.anzahl > 0, let von = s.von, let bis = s.bis else { return "keine \(name)" }
            return "\(s.anzahl) \(name), zusammen \(Format.zahl(s.summe)) (\(Format.datum(von, zone, mitZeit: false)) "
                + "bis \(Format.datum(bis, zone, mitZeit: false)))"
        }
        t.append("Längste Serien: \(serie(d.laengsteVerlustserie, "Verluste")); "
            + "\(serie(d.laengsteGewinnserie, "Gewinne")).")
        return t
    }

    /// Leistungsscore 0 bis 100 (`Leistungsscore`). Regeltreue nur, wenn es Regeln oder Journalangaben dazu gibt;
    /// sonst wäre jeder Trade „regeltreu“ und der Score zu gut.
    static func scoreAbschnitt(_ anfrage: Anfrage, _ b: Zeitraumbericht) -> [String] {
        let trades = b.auswertung.trades
        let mitRegeln = anfrage.konto.regeln.map { !$0.leer } ?? false
        let mitJournal = trades.contains { anfrage.journal($0)?.regeltreue != nil }
        let regeltreue = mitRegeln || mitJournal ? b.disziplin.quote : nil
        var t = ["\n## Leistungsscore (0 bis 100)"]
        guard let score = Leistungsscore(trades: trades, zeitzone: anfrage.zeitzone, regeltreue: regeltreue) else {
            t.append("Kein Score: erst ab \(Leistungsscore.mindestanzahl) Trades im Zeitraum (hier \(trades.count)).")
            return t
        }
        t.append("Gesamt \(Format.zahl(score.gesamt, stellen: 0)) aus \(score.anzahl) Trades.")
        let zeilen: [[String]] = score.komponenten.map { k in
            [teilname(k.komponente), rohwert(k), Format.zahl(k.wert, stellen: 0), Format.prozent(k.gewicht)]
        }
        t.append(Format.tabelle(["Teil", "Rohwert", "Punkte", "Gewicht"], zeilen))
        var hinweis = "Anker vorläufig (R5), am eigenen Datensatz zu kalibrieren; beschreibt den Zeitraum, keine Prognose."
        if regeltreue == nil { hinweis += " Ohne Regeltreue: keine Handelsregeln und keine Journalangabe dazu." }
        t.append(hinweis)
        return t
    }

    static func teilname(_ k: Leistungsscore.Komponente) -> String {
        switch k {
        case .trefferquote: "Trefferquote"
        case .payoff: "Payoff"
        case .profitfaktor: "Profitfaktor"
        case .bestaendigkeit: "Beständigkeit (profitable Tage)"
        case .drawdown: "Rückgang (Anteil der Gewinne)"
        case .regeltreue: "Regeltreue"
        }
    }

    static func rohwert(_ k: Leistungsscore.Komponentenwert) -> String {
        switch k.komponente {
        case .trefferquote, .bestaendigkeit, .drawdown, .regeltreue: Format.prozent(k.rohwert)
        case .payoff, .profitfaktor: Format.zahl(k.rohwert)
        }
    }
}

extension Anfrage {
    /// Best-Exit der Trades mit Stop (`BestExitAuswertung`) aus den Analysen der App; leer, wenn die App für keinen
    /// Trade des Zeitraums Minutenkerzen hat.
    func bestExitAbschnitt(_ trades: [Trade]) -> [String] {
        guard konto.ausstieg != nil else { return [] }
        let jeTrade = konto.ausstiegJeTrade
        let mitStop = trades.filter { $0.stopRisiko != nil }
        let einzeln = mitStop.compactMap { t in jeTrade[t.id]?.bestExit?.bestExit(tradeID: t.id) }
        guard !einzeln.isEmpty else { return [] }
        // Beträge nur, wenn alle analysierten Trades in Kontowährung lauten (1 R in der Währung des Trades).
        let original = Dictionary(alleTrades.map { ($0.id, $0.waehrung(kontowaehrung: kontowaehrung)) },
                                  uniquingKeysWith: { erste, _ in erste })
        let ids = Set(einzeln.map(\.tradeID))
        let gleich = !kontowaehrung.isEmpty && ids.allSatisfy { original[$0] == kontowaehrung }
        let b = BestExitAuswertung(einzeln, ohneRisiko: trades.count - mitStop.count,
                                   ohneKerzen: mitStop.count - einzeln.count, gleicheWaehrung: gleich)
        var t = ["\n## Best-Exit (feste Ziele in R gegen den tatsächlichen Ausstieg)"]
        func zeile(_ s: BestExitAuswertung.Stufe) -> [String] {
            var differenz = Format.r(s.differenzR)
            if let betrag = s.differenzBetrag { differenz += " (\(Format.zahl(betrag)))" }
            return [Format.r(s.ziel), "\(s.anzahl)", "\(s.zielErreicht)", "\(s.stopZuerst)", "\(s.ohneEntscheidung)",
                    Format.r(s.summeR), Format.r(s.durchschnittR), differenz]
        }
        let kopf = ["Ziel", "Trades", "Ziel erreicht", "Stop zuerst", "Offen", "Summe R", "Ø R",
                    "Differenz R" + (gleich ? " (Betrag in \(kontowaehrung))" : "")]
        t.append(Format.tabelle(kopf, b.stufen.map(zeile)))
        t.append("Tatsächlich: Summe \(Format.r(b.summeTatsaechlichR)), Ø \(Format.r(b.durchschnittTatsaechlichR)) "
            + "aus \(b.anzahl) Trades" + (b.besteStufe.map { "; höchste Summe bei \(Format.r($0))" } ?? "") + ". "
            + "Ausstieg jeweils am besten Kurs (nicht planbar, nur Obergrenze): Summe "
            + "\(Format.r(b.summeTheoretischesMaximumR)).")
        var lage = "Ausgelassen: \(b.ohneRisiko) ohne brauchbaren Stop, \(b.ohneKerzen) ohne Minutenkerzen."
        let unscharf = b.stufen.map(\.anzahlUnscharf).reduce(0, +)
        if unscharf > 0 { lage += " \(unscharf) Fälle mit Stop und Ziel in derselben Kerze, als Stop gezählt." }
        if b.anzahlKerzenUnscharf > 0 {
            lage += " Bei \(b.anzahlKerzenUnscharf) Trades reichen die Kerzen über Ein- oder Ausstieg hinaus."
        }
        t.append(lage + " Ausführung genau am Kurs, ohne Schlupf; 1 R ist der Abstand zum Stop wie beim Ergebnis in R.")
        return t
    }
}
