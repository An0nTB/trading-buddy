import Foundation
import TradingCore

/// Texte, die die Werkzeuge an Claude zurückgeben. Knapp und mit Stichprobe,
/// damit Claude nichts nachrechnen oder schätzen muss.
public enum Ausgabe {
    /// Monats- oder Wochenauswertung mit Vergleich und Rezept (Werkzeug `hole_auswertung`).
    public static func auswertung(_ anfrage: Anfrage) -> String {
        let a = anfrage.auswertung()
        let zone = anfrage.zeitzone
        let k = a.kennzahlen, v = a.kennzahlenVorzeitraum
        let titel = Format.zeitraum(a.zeitraum, zone), vorTitel = Format.zeitraum(a.vorzeitraum, zone)
        var t = ["# Trading Buddy · Auswertung \(titel)", kopf(anfrage, vergleich: vorTitel)]
        if let hinweis = anfrage.vorgabe { t.append(hinweis) }

        t.append("\n## Ergebnis")
        let ergebnis: [[String]] = [
            ["Trades (Gewinner/Verlierer)", "\(k.anzahl) (\(k.gewinner)/\(k.verlierer))", "\(v.anzahl) (\(v.gewinner)/\(v.verlierer))"],
            ["Netto", Format.zahl(k.netto), Format.zahl(v.netto)],
            ["Trefferquote", Format.prozent(k.trefferquote), Format.prozent(v.trefferquote)],
            ["Ø Gewinn / Ø Verlust", "\(Format.zahl(k.durchschnittGewinn)) / \(Format.zahl(k.durchschnittVerlust))",
             "\(Format.zahl(v.durchschnittGewinn)) / \(Format.zahl(v.durchschnittVerlust))"],
            ["Payoff", Format.zahl(k.payoff), Format.zahl(v.payoff)],
            ["Profitfaktor", Format.zahl(k.profitfaktor), Format.zahl(v.profitfaktor)],
            ["Erwartungswert je Trade", Format.zahl(k.erwartungswert), Format.zahl(v.erwartungswert)],
            ["Erwartungswert in R (Trades mit R)", "\(Format.r(k.erwartungswertR)) (\(k.anzahlMitR))",
             "\(Format.r(v.erwartungswertR)) (\(v.anzahlMitR))"],
            ["Haltedauer Gewinner / Verlierer", "\(Format.dauer(k.haltedauerGewinner)) / \(Format.dauer(k.haltedauerVerlierer))",
             "\(Format.dauer(v.haltedauerGewinner)) / \(Format.dauer(v.haltedauerVerlierer))"],
        ]
        t.append(Format.tabelle(["Kennzahl", titel, vorTitel], ergebnis))
        t.append("Max. Drawdown \(Format.zahl(a.kapitalverlauf.maxDrawdown)), längste Serien "
            + "\(a.kapitalverlauf.laengsteGewinnserie) Gewinne und \(a.kapitalverlauf.laengsteVerlustserie) Verluste.")

        let kommission = a.trades.map(\.commission).reduce(0, +), swap = a.trades.map(\.swap).reduce(0, +)
        t.append("\n## Kosten")
        t.append("Kursergebnis \(Format.zahl(k.brutto)), Kosten \(Format.zahl(k.kosten)) (Kommission "
            + "\(Format.zahl(kommission)), Swap \(Format.zahl(swap))), das sind \(Format.prozent(k.kostenquote)) "
            + "der Bruttogewinne. Stornoquote \(Format.prozent(a.stornoquote)) (\(a.geloeschteOrders) Orders gelöscht, "
            + "\(k.anzahl) ausgeführt).")

        let symbole = Kennzahlen.aufschluesseln(a.trades, nach: .symbol, zeitzone: zone)
            .sorted { ($0.kennzahlen.netto, $0.schluessel) > ($1.kennzahlen.netto, $1.schluessel) }
        t.append("\n## Nach Symbol (statt Setups)")
        t.append(Format.tabelle(["Symbol", "Trades", "Netto", "Treffer", "Erw. R"], symbole.prefix(10).map {
            [$0.schluessel, "\($0.kennzahlen.anzahl)", Format.zahl($0.kennzahlen.netto),
             Format.prozent($0.kennzahlen.trefferquote), Format.r($0.kennzahlen.erwartungswertR)]
        }))
        if symbole.count > 10 { t.append("Weitere \(symbole.count - 10) Symbole über hole_aufschluesselung.") }

        t.append("\n## Fehlermuster (Regeln im Rechenkern, Schwellen vorläufig)")
        t.append(contentsOf: a.befunde.map { befund(a, $0) })
        let ohneTreffer = Fehlermuster.allCases.filter { m in !a.befunde.contains { $0.muster == m } }
        if !ohneTreffer.isEmpty { t.append("Ohne Treffer: \(ohneTreffer.map(\.bezeichnung).joined(separator: ", ")).") }

        t.append("\n## Auffällige Trades")
        let beste = a.beste(3)
        let schlechteste = a.schlechteste(3).reversed().filter { !beste.contains($0) }
        t.append(tradetabelle(beste + schlechteste, a, zone))

        t.append("\n## Datenlage")
        t.append(k.genugDaten ? "- \(k.anzahl) Trades: ab 30 belastbar, Gruppen darunter nur beschreiben."
                              : "- Nur \(k.anzahl) Trades (unter 30): nur beschreiben, nicht folgern.")
        t.append("- R nur für Trades mit Stop. MetaTrader exportiert den letzten Stop; nachgezogene Stops verfälschen R.")
        t.append("- Setups, Notizen, Regeltreue und Ziele früherer Reviews speichert die App noch nicht.")
        t.append("\n" + Rezept.text)
        return t.joined(separator: "\n")
    }

    static func kopf(_ anfrage: Anfrage, vergleich: String? = nil) -> String {
        "Konto \(anfrage.konto.kurzname), Beträge in \(anfrage.konto.waehrung). "
            + (vergleich.map { "Vergleich: \($0). " } ?? "")
            + "Zeitzone \(anfrage.export.zeitzone). Export vom \(Format.datum(anfrage.export.erstellt, anfrage.zeitzone))."
    }

    private static func befund(_ a: Auswertung, _ b: Befund) -> String {
        var zeile = "- \(b.muster.bezeichnung): "
        if b.trades.isEmpty {
            zeile += "Wert \(Format.zahl(b.wert))"
        } else {
            zeile += "\(b.trades.count) Trades, netto \(Format.zahl(b.netto)), Summe \(Format.r(b.summeR))"
            if let w = b.wert { zeile += ", Wert \(Format.zahl(w))" }
        }
        zeile += ". Stichprobe \(b.stichprobe)\(b.genugDaten ? "" : " (unter 30)"). Regel: \(b.muster.regeltext)."
        if let ohne = a.ohne(b) {
            zeile += " Ohne diese Trades: netto \(Format.zahl(ohne.netto)), Erwartungswert \(Format.r(ohne.erwartungswertR))."
        }
        return zeile
    }
}
