import Foundation
import TradingCore

/// Auswahl für `hole_trades`.
public enum Tradeauswahl: String, Sendable, CaseIterable {
    case beste, schlechteste, chronologisch
}

extension Ausgabe {
    /// Konten und Zeitraum der Daten (Werkzeug `hole_datenstand`).
    public static func datenstand(_ export: JournalExport) -> String {
        let zone = export.nutzerZeitzone
        var t = ["# Trading Buddy · Datenstand",
                 "Export vom \(Format.datum(export.erstellt, zone)), Rechenkern \(export.rechenkern), "
                     + "Zeitzone \(export.zeitzone)."]
        if export.konten.isEmpty { t.append("Noch kein Konto importiert.") }
        for konto in export.konten {
            var zeile = "- \(konto.kurzname), \(konto.waehrung): \(konto.trades.count) Trades"
            let zeiten = konto.trades.map(\.closeTime)
            if let erster = zeiten.min(), let letzter = zeiten.max() {
                zeile += ", geschlossen \(Format.datum(erster, zone, mitZeit: false)) bis "
                    + Format.datum(letzter, zone, mitZeit: false)
            }
            t.append(zeile + ", \(konto.geloeschteOrders.count) gelöschte Orders.")
        }
        return t.joined(separator: "\n")
    }

    /// Kennzahlen je Gruppe eines Merkmals aus Rechenkern oder Journal (Werkzeug `hole_aufschluesselung`).
    public static func aufschluesselung(_ anfrage: Anfrage, nach merkmal: Aufschluesselung) -> String {
        switch merkmal {
        case let .kern(dimension):
            return aufschluesselung(anfrage, nach: dimension)
        case let .journal(gruppe):
            let a = anfrage.auswertung()
            return ["# Trading Buddy · \(gruppe.name) · \(Format.zeitraum(a.zeitraum, anfrage.zeitzone))",
                    kopf(anfrage), journaltabelle(anfrage, a.trades, gruppe),
                    "Eigene Angaben aus dem Journal. Gruppen unter 30 Trades nur beschreiben, nicht folgern."]
                .joined(separator: "\n")
        }
    }

    /// Kennzahlen je Gruppe einer Dimension des Rechenkerns.
    public static func aufschluesselung(_ anfrage: Anfrage, nach dimension: Aufteilung) -> String {
        let a = anfrage.auswertung()
        let zone = anfrage.zeitzone
        let gruppen = Kennzahlen.aufschluesseln(a.trades, nach: dimension, zeitzone: zone)
        let zeilen: [[String]] = gruppen.map { g in
            [gruppenname(g.schluessel, dimension), "\(g.kennzahlen.anzahl)", Format.zahl(g.kennzahlen.netto),
             Format.prozent(g.kennzahlen.trefferquote), Format.zahl(g.kennzahlen.profitfaktor),
             Format.r(g.kennzahlen.erwartungswertR)]
        }
        return ["# Trading Buddy · \(dimensionsname(dimension)) · \(Format.zeitraum(a.zeitraum, zone))",
                kopf(anfrage),
                Format.tabelle([dimensionsname(dimension), "Trades", "Netto", "Treffer", "Profitfaktor", "Erw. R"], zeilen),
                "Gruppen unter 30 Trades nur beschreiben, nicht folgern."]
            .joined(separator: "\n")
    }

    /// Einzelne Trades, wahlweise nur die eines Musters (Werkzeug `hole_trades`).
    public static func trades(_ anfrage: Anfrage, auswahl: Tradeauswahl, muster: Fehlermuster?,
                              anzahl: Int) -> String {
        let a = anfrage.auswertung()
        var liste = a.trades
        if let muster {
            let ids = Set(a.befunde.first { $0.muster == muster }?.trades ?? [])
            liste = liste.filter { ids.contains($0.id) }
        }
        switch auswahl {
        case .beste: liste.sort { ($0.netProfit, $0.id) > ($1.netProfit, $1.id) }
        case .schlechteste: liste.sort { ($0.netProfit, $0.id) < ($1.netProfit, $1.id) }
        case .chronologisch: break
        }
        let n = min(max(anzahl, 1), 50)
        let gezeigt = Array(liste.prefix(n))
        var t = ["# Trading Buddy · Trades \(Format.zeitraum(a.zeitraum, anfrage.zeitzone))"
                     + (muster.map { " · \($0.bezeichnung)" } ?? ""),
                 kopf(anfrage),
                 tradetabelle(gezeigt, a, anfrage.zeitzone)]
        let mitJournal = gezeigt.filter { anfrage.journal($0) != nil }
        if !mitJournal.isEmpty {
            t.append("\nJournal (eigene Angaben):")
            t.append(Format.tabelle(["Ticket", "Setup", "Regeltreue", "Zustand", "Marktumfeld", "Grund"],
                                    mitJournal.map { trade in
                                        let j = anfrage.journal(trade)
                                        return [trade.id, Format.kurz(j?.setup, zeichen: 40),
                                                j?.regeltreue.map { $0 ? "ja" : "nein" } ?? "–",
                                                j?.zustand.map { "\($0)/5" } ?? "–", Format.kurz(j?.marktumfeld, zeichen: 40),
                                                Format.kurz(j?.grund)]
                                    }))
        }
        if liste.count > n { t.append("\(liste.count - n) weitere Trades nicht gezeigt.") }
        if liste.isEmpty { t.append("Keine passenden Trades.") }
        return t.joined(separator: "\n")
    }

    static func tradetabelle(_ trades: [Trade], _ a: Auswertung, _ zone: TimeZone) -> String {
        Format.tabelle(["Ticket", "Schluss", "Symbol", "Richtung", "Lots", "Netto", "R", "Haltedauer", "Muster"],
                       trades.map { t in
                           [t.id, Format.datum(t.closeTime, zone), t.symbol, t.side == .buy ? "Kauf" : "Verkauf",
                            Format.zahl(t.lots), Format.zahl(t.netProfit), Format.r(t.rMultiple), Format.dauer(t.holdingTime),
                            a.muster(t).map(\.bezeichnung).joined(separator: ", ")]
                       })
    }

    static func dimensionsname(_ d: Aufteilung) -> String {
        switch d {
        case .symbol: "Symbol"
        case .richtung: "Richtung"
        case .wochentag: "Wochentag"
        case .stunde: "Stunde der Eröffnung"
        case .tradeNummerAmTag: "Trade-Nummer am Tag"
        case .nachVorherigem: "Nach vorherigem Ergebnis"
        case .haltedauer: "Haltedauer"
        }
    }

    static func gruppenname(_ schluessel: String, _ d: Aufteilung) -> String {
        let namen: [String: String] = switch d {
        case .richtung: ["buy": "Kauf", "sell": "Verkauf"]
        case .wochentag: ["1": "Mo", "2": "Di", "3": "Mi", "4": "Do", "5": "Fr", "6": "Sa", "7": "So"]
        case .stunde: [:]
        case .nachVorherigem: ["nachGewinn": "nach Gewinn", "nachVerlust": "nach Verlust",
                               "nachBreakeven": "nach Breakeven", "erster": "erster Trade"]
        case .haltedauer: ["unter5Minuten": "unter 5 Min.", "unter1Stunde": "5 Min. bis 1 Std.",
                           "unter1Tag": "1 Std. bis 1 Tag", "ueber1Tag": "über 1 Tag"]
        case .symbol, .tradeNummerAmTag: [:]
        }
        return d == .stunde ? "\(schluessel) Uhr" : (namen[schluessel] ?? schluessel)
    }
}
