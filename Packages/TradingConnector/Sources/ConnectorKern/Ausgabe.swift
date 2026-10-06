import Foundation
import TradingCore

/// Texte, die die Werkzeuge an Claude zurückgeben. Knapp und mit Stichprobe,
/// damit Claude nichts nachrechnen oder schätzen muss.
public enum Ausgabe {
    /// Monats-, Wochen- oder Spannenauswertung mit Vergleich und Rezept (Werkzeug `hole_auswertung`), gerechnet über
    /// `Zeitraumbericht` wie die Berichte der App.
    public static func auswertung(_ anfrage: Anfrage) -> String {
        let b = anfrage.bericht()
        let a = b.auswertung
        let zone = anfrage.zeitzone
        let k = a.kennzahlen, v = a.kennzahlenVorzeitraum
        let titel = Format.zeitraum(a.zeitraum, zone), vorTitel = Format.zeitraum(a.vorzeitraum, zone)
        var t = ["# Henry · Auswertung \(titel)", kopf(anfrage, vergleich: vorTitel)]
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
        t.append(contentsOf: anfrage.tagesabschnitt(b))

        let kommission = a.trades.map(\.commission).reduce(0, +), swap = a.trades.map(\.swap).reduce(0, +)
        let steuern = a.trades.map(\.taxes).reduce(0, +)
        t.append("\n## Kosten")
        var bloecke = "Kommission \(Format.zahl(kommission)), Swap \(Format.zahl(swap))"
        if steuern != 0 { bloecke += ", Steuern \(Format.zahl(steuern))" }
        t.append("Kursergebnis \(Format.zahl(k.brutto)), Kosten \(Format.zahl(k.kosten)) (\(bloecke)), "
            + "das sind \(Format.prozent(k.kostenquote)) der Bruttogewinne. Stornoquote \(Format.prozent(a.stornoquote)) (\(a.geloeschteOrders) Orders gelöscht, "
            + "\(k.anzahl) ausgeführt).")
        if steuern != 0 {
            t.append("Steuern sind Abzüge und Erstattungen laut Broker-Export, keine Steuerberechnung.")
        }
        t.append(contentsOf: anfrage.steuerabschnitt(b))

        let symbole = Kennzahlen.aufschluesseln(a.trades, nach: .symbol, zeitzone: zone)
            .sorted { ($0.kennzahlen.netto, $0.schluessel) > ($1.kennzahlen.netto, $1.schluessel) }
        let abdeckung = anfrage.journalabdeckung(a.trades)
        if abdeckung.setup > 0 {
            t.append("\n## Nach Setup (eigene Angabe im Journal)")
            t.append(journaltabelle(anfrage, a.trades, .setup))
        }
        t.append("\n## Nach Symbol")
        t.append(Format.tabelle(["Symbol", "Trades", "Netto", "Treffer", "Erw. R"], symbole.prefix(10).map {
            [$0.schluessel, "\($0.kennzahlen.anzahl)", Format.zahl($0.kennzahlen.netto),
             Format.prozent($0.kennzahlen.trefferquote), Format.r($0.kennzahlen.erwartungswertR)]
        }))
        if symbole.count > 10 { t.append("Weitere \(symbole.count - 10) Symbole über hole_aufschluesselung.") }
        t.append(contentsOf: anfrage.produktartabschnitt(a.trades))

        t.append("\n## Fehlermuster (Regeln im Rechenkern, Schwellen vorläufig)")
        t.append(contentsOf: a.befunde.map { befund(a, $0) })
        // Überhandeln ohne Grenze (unter 10 Tagen mit Trades) ist nicht geprüft, nicht „ohne Treffer“.
        let tage = Fehlermuster.tradesJeTag(a.trades, zeitzone: zone).count
        let ungeprueft = !a.trades.isEmpty && Fehlermuster.ueberhandelnGrenze(a.trades, zeitzone: zone) == nil
        let ohneTreffer = Fehlermuster.allCases.filter { m in
            !a.befunde.contains { $0.muster == m } && !(m == .ueberhandeln && ungeprueft)
        }
        if !ohneTreffer.isEmpty { t.append("Ohne Treffer: \(ohneTreffer.map(\.bezeichnung).joined(separator: ", ")).") }
        if ungeprueft {
            t.append("Nicht geprüft: Überhandeln, erst ab \(Fehlermuster.Schwellen().ueberhandelnMindestTage) Tagen mit "
                + "Trades (hier \(tage)).")
        }

        if abdeckung.regeltreue > 0 || abdeckung.zustand > 0 {
            t.append("\n## Regeltreue und Zustand (eigene Angaben im Journal)")
            if abdeckung.regeltreue > 0 { t.append(journaltabelle(anfrage, a.trades, .regeltreue)) }
            if abdeckung.zustand > 0 { t.append(journaltabelle(anfrage, a.trades, .zustand)) }
        }

        let regeln = anfrage.regelabschnitt(a.trades, propFirm: anfrage.propFirmzeile(b))
        t.append(contentsOf: regeln)
        let muster = anfrage.musterabschnitt(a.trades, vorgegeben: b.muster)
        t.append(contentsOf: muster)
        t.append(contentsOf: anfrage.ausstiegsabschnitt(a.trades))

        t.append("\n## Auffällige Trades")
        let beste = a.beste(3)
        let schlechteste = a.schlechteste(3).reversed().filter { !beste.contains($0) }
        t.append(tradetabelle(beste + schlechteste, a, zone))

        t.append(contentsOf: anfrage.notizabschnitt(a.trades))

        let ziele = anfrage.zieleZumZeitraum()
        if !ziele.ziele.isEmpty {
            t.append("\n## Ziel aus dem letzten Review (eingetragen in der App)")
            if ziele.davor { t.append("Kein Ziel für diesen Zeitraum; das letzte davor:") }
            t.append(contentsOf: ziele.ziele.prefix(5).map(anfrage.zielzeile))
        }

        t.append("\n## Datenlage")
        t.append(k.genugDaten ? "- \(k.anzahl) Trades: ab 30 belastbar, Gruppen darunter nur beschreiben."
                              : "- Nur \(k.anzahl) Trades (unter 30): nur beschreiben, nicht folgern.")
        t.append("- R nur für Trades mit Stop. Ein im Journal nachgetragener Stop beim Einstieg gilt; sonst der Stop "
            + "aus dem Export, bei MetaTrader der letzte Stand (nachgezogene Stops verfälschen R).")
        if let angenommen = rAngenommen(k) { t.append(angenommen) }
        let nurDatum = a.trades.filter(\.nurDatum).count
        if nurDatum > 0 {
            t.append("- \(nurDatum) von \(k.anzahl) Trades nur mit Datum gebucht (Trade Republic, Scalable): Uhrzeit und "
                + "Haltedauer unbekannt, bei Stunde und Haltedauer unter „ohne Uhrzeit“, daraus kein Muster.")
        }
        t.append("- Journal ausgefüllt im Zeitraum: Setup \(abdeckung.setup), Regeltreue \(abdeckung.regeltreue), "
            + "Zustand \(abdeckung.zustand), Grund \(abdeckung.grund) von \(k.anzahl) Trades. "
            + "Gründe einzelner Trades über hole_trades.")
        if regeln.isEmpty { t.append("- Handelsregeln: keine in der App eingetragen.") }
        if muster.isEmpty {
            t.append("- Muster: keine Gruppe mit je 30 Trades in Gruppe und Rest, also frühestens ab 60 Trades im Zeitraum.")
        }
        t.append(anfrage.notizlage(a.trades))
        if let ausstieg = anfrage.ausstiegslage(a.trades) { t.append(ausstieg) }
        if anfrage.konto.waehrung != anfrage.kontowaehrung, !anfrage.kontowaehrung.isEmpty {
            t.append("- Ziele früherer Reviews: gelten in der Kontowährung \(anfrage.kontowaehrung) und stehen nur in "
                + "der Abfrage ohne waehrung.")
        } else if anfrage.konto.ziele.isEmpty {
            t.append("- Ziele früherer Reviews: keine in der App eingetragen.")
        } else {
            t.append("- Istwerte der Ziele rechnet der Rechenkern im Zeitraum des Ziels. Der Status ist eigene Angabe "
                + "oder wird nach Fristende ohne Abhaken automatisch „verfehlt“; maßgeblich ist der Istwert.")
        }
        t.append("\n" + Rezept.text)
        if anfrage.export.personaTon { t.append(Rezept.personaRegel) }
        return t.joined(separator: "\n")
    }

    /// Hinweis auf R aus dem geplanten Risiko (Doc 02 Nr. 64); `nil`, wenn kein Trade so rechnet.
    static func rAngenommen(_ k: Kennzahlen) -> String? {
        guard k.anzahlRAngenommen > 0 else { return nil }
        return "- Davon \(k.anzahlRAngenommen) von \(k.anzahlMitR) Trades mit R ohne Stop: R aus dem geplanten Risiko "
            + "(in der App eingetragen, je Trade, Setup oder Konto), also angenommen. Im Review so nennen."
    }

    static func kopf(_ anfrage: Anfrage, vergleich: String? = nil) -> String {
        var text = "Konto \(anfrage.kontoname), Beträge in \(anfrage.konto.waehrung). " + waehrungshinweis(anfrage)
            + anzeigehinweis(anfrage)
        if let vergleich { text += "Vergleich: \(vergleich). " }
        text += "Zeitzone \(anfrage.export.zeitzone). Export vom \(Format.datum(anfrage.export.erstellt, anfrage.zeitzone)). "
        return text + gespeichert(anfrage.konto, anfrage.zeitzone)
    }

    /// Hinweis auf Trades in anderen Währungen; leer, wenn das Konto nur eine Währung hat.
    static func waehrungshinweis(_ anfrage: Anfrage) -> String {
        var text = ""
        if anfrage.konto.waehrung != anfrage.kontowaehrung {
            text += "Kontowährung ist \(anfrage.kontowaehrung); Ziele und Betragsgrenzen der Handelsregeln gelten dort "
                + "und fehlen hier. "
        }
        // USDT in einem USD-Konto zählt ohne Kurs eins zu eins (wie in der App), alles andere über den EZB-Kurs.
        let gleich = anfrage.umgerechnet.filter {
            Referenzkurse.gleichgesetzt[$0.key.uppercased()] == anfrage.kontowaehrung.uppercased()
        }
        let ezb = anfrage.umgerechnet.filter { gleich[$0.key] == nil }
        if !ezb.isEmpty {
            let teile = ezb.keys.sorted().map { "\($0) \(ezb[$0]!)" }
            text += "Umgerechnet in \(anfrage.kontowaehrung) mit dem EZB-Referenzkurs am Schlusstag (Näherung, wie in der "
                + "App): \(teile.joined(separator: ", ")) Trades; Kurse und Stops bleiben in ihrer Währung. "
        }
        if !gleich.isEmpty {
            let teile = gleich.keys.sorted().map { "\($0) \(gleich[$0]!)" }
            text += "Wie \(anfrage.kontowaehrung) gezählt (gleichgesetzt wie in der App, ohne Umrechnung): "
                + "\(teile.joined(separator: ", ")) Trades. "
        }
        guard !anfrage.andereWaehrungen.isEmpty else { return text }
        let teile = anfrage.andereWaehrungen.keys.sorted().map { w in
            let trades = anfrage.andereWaehrungen[w]!
            let imZeitraum = trades.filter { anfrage.zeitraum.enthaelt($0.closeTime) }.count
            return "\(w): \(trades.count) Trades, davon \(imZeitraum) im Zeitraum"
        }
        let grund = ezb.isEmpty ? "Nur Trades in \(anfrage.konto.waehrung). Nicht in diesen Summen"
            : "Ohne EZB-Kurs am Schlusstag nicht umgerechnet und nicht in diesen Summen"
        return text + "\(grund) (eigene Abfrage mit waehrung): " + teile.joined(separator: "; ")
            + ". Beträge verschiedener Währungen nie zusammenrechnen. "
    }

    /// Alle gespeicherten Trades des Kontos, damit Claude Zeitraum und Gesamtbestand nicht verwechselt.
    static func gespeichert(_ konto: JournalExport.Kontodaten, _ zone: TimeZone) -> String {
        let zeiten = konto.trades.map(\.closeTime)
        guard let erster = zeiten.min(), let letzter = zeiten.max() else { return "Gespeichert: keine Trades." }
        return "Gespeichert insgesamt (alle Zeiträume): \(konto.trades.count) Trades, geschlossen "
            + "\(Format.datum(erster, zone, mitZeit: false)) bis \(Format.datum(letzter, zone, mitZeit: false))."
    }

    /// Kennzahlen je Journalgruppe als Tabelle.
    static func journaltabelle(_ anfrage: Anfrage, _ trades: [Trade], _ gruppe: Journalgruppe) -> String {
        Format.tabelle([gruppe.name, "Trades", "Netto", "Treffer", "Profitfaktor", "Erw. R"],
                       anfrage.gruppen(trades, nach: gruppe).map { g in
                           [Format.kurz(g.name, zeichen: 40), "\(g.kennzahlen.anzahl)", Format.zahl(g.kennzahlen.netto),
                            Format.prozent(g.kennzahlen.trefferquote), Format.zahl(g.kennzahlen.profitfaktor),
                            Format.r(g.kennzahlen.erwartungswertR)]
                       })
    }

    private static func befund(_ a: Auswertung, _ b: Befund) -> String {
        var zeile = "- \(b.muster.bezeichnung): "
        if b.trades.isEmpty {
            zeile += "Wert \(Format.zahl(b.wert))"
        } else {
            zeile += "\(b.trades.count) Trades, netto \(Format.zahl(b.netto)), Summe \(Format.r(b.summeR))"
            // Bei Überhandeln ist der Wert die Grenze: betroffen sind die Positionen mit höherer Nummer am Tag.
            if let w = b.wert {
                zeile += b.muster == .ueberhandeln ? ", betroffen ab Position \(Format.zahl(w + 1, stellen: 0)) eines Tages"
                                                   : ", Wert \(Format.zahl(w))"
            }
        }
        zeile += ". Stichprobe \(b.stichprobe)\(b.genugDaten ? "" : " (unter 30)"). Regel: \(b.muster.regeltext)."
        if let ohne = a.ohne(b) {
            zeile += " Ohne diese Trades: netto \(Format.zahl(ohne.netto)), Erwartungswert \(Format.r(ohne.erwartungswertR))."
        }
        return zeile
    }
}
