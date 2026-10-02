import Foundation
import TradingCore

/// Kursanalyse eines Werts für „Frag Henry“ (Doc 38, Paket A3): Kennzahlen aus den Tageskerzen der App
/// (`Kursanalyse` im Rechenkern) und die eigenen Trades im Wert. Nur beschreibend, keine Prognose.
extension Ausgabe {
    /// Werkzeug `hole_kursanalyse`. `monate` 1 bis 12 begrenzt Kerzen und eigene Trades, vom letzten Kerzentag
    /// an gerechnet, ohne Kerzen vom Export an.
    public static func kursanalyse(_ export: JournalExport, symbol: String, monate: Int = 12) -> String {
        let zone = export.nutzerZeitzone
        let monate = min(max(monate, 1), 12)
        let wunsch = symbolschluessel(symbol)
        let reihen = export.kursverlauf ?? []
        let vorhanden: String = reihen.prefix(20).map(\.symbol).joined(separator: ", ")
        guard !wunsch.isEmpty else {
            return "SYMBOL FEHLT: `symbol` angeben" + (reihen.isEmpty ? "." : ", z. B. eines von: \(vorhanden).")
        }
        let reihe = reihen.first { symbolschluessel($0.symbol) == wunsch }
        let name = Format.kurz(reihe?.symbol ?? symbol, zeichen: 30)
        var t = ["# Henry · Kursanalyse \(name) (\(monate) \(monate == 1 ? "Monat" : "Monate"))",
                 "Export vom \(Format.datum(export.erstellt, zone)), Zeitzone \(export.zeitzone). Nur beschreibend: "
                     + "Kennzahlen vergangener Kurse, keine Prognose, kein Signal."]

        if let reihe, let analyse = analyse(reihe, monate: monate) {
            t.append("Kurse: Tageskerzen von \(Format.kurz(reihe.quelle, zeichen: 20)) in \(reihe.waehrung), "
                + "abgerufen \(Format.datum(reihe.stand, zone)), \(analyse.anzahlKerzen) abgeschlossene Tage bis "
                + "\(analyse.letzterTag) (UTC-Kalendertage).")
            t.append("\n## Kennzahlen")
            t.append(Format.tabelle(["Kennzahl", "Wert"], kennzahlzeilen(analyse, reihe.waehrung)))
            t.append("Veränderung: letzter Schluss gegen den Schluss vor 7, 30, 91 und 365 Kalendertagen; fehlt, wenn "
                + "die Reihe kürzer ist. Schwankung: Standardabweichung der Tagesrenditen mal Wurzel aus "
                + "\(analyse.handelstageJeJahr) Handelstagen. Abstände über die letzten 365 Tage.")
        } else if reihe != nil {
            t.append("Für \(name) liegen keine abgeschlossenen Tageskerzen vor.")
        } else {
            let liste = reihen.isEmpty ? "Die App hat noch keine Kurse geladen." : "Kursverläufe gibt es für: \(vorhanden)."
            t.append("Kein Kursverlauf in der App für \(Format.kurz(symbol, zeichen: 30)). \(liste) "
                + "Die Antwort stützt sich dann nur auf eigene Trades und Nachrichten.")
        }

        // Gleicher Rückblick wie die Kerzen; ohne Kerzen vom Export an.
        let bezug = reihe?.kerzen.last.map { $0.tag.beginn(in: TimeZone(secondsFromGMT: 0)!).addingTimeInterval(86_400) }
        t.append(contentsOf: eigeneTrades(export, wunsch: wunsch, monate: monate, bis: bezug ?? export.erstellt))
        t.append("\nNachrichten zum Wert: hole_nachrichten mit begriff=\(name) (nur, wenn in der App eingeschaltet).")
        t.append("\n" + Rezept.kursanalyseText)
        if export.personaTon { t.append(Rezept.personaRegel) }
        return t.joined(separator: "\n")
    }

    /// Kursanalyse über die letzten `monate` Monate der Reihe; eine laufende Kerze bleibt dabei.
    /// Gezählt wird ab dem letzten abgeschlossenen Tag wie in `Kursanalyse`, dazu 7 Tage Vorlauf: Die Veränderung
    /// braucht eine Kerze am oder bis 7 Tage vor dem Zieltag (Wochenende, Feiertag). Ohne Vorlauf fehlte sie mit
    /// laufender Kerze (Krypto) immer und bei Aktien, wenn der Zieltag kein Handelstag war (Befund G3, Doc 49).
    static func analyse(_ reihe: JournalExport.Kursreihe, monate: Int) -> Kursanalyse? {
        guard let letzter = (reihe.kerzen.last { !$0.laufend } ?? reihe.kerzen.last)?.tag else { return nil }
        let utc = TimeZone(secondsFromGMT: 0)!
        let ab = Journaltag(kalender(utc).date(byAdding: .day, value: -(monate * 365 / 12 + 7),
                                               to: letzter.beginn(in: utc))!, zeitzone: utc)
        return Kursanalyse(kerzen: reihe.kerzen.filter { $0.tag >= ab })
    }

    static func kennzahlzeilen(_ a: Kursanalyse, _ waehrung: String) -> [[String]] {
        var zeilen: [[String]] = [["Letzter Schluss (\(a.letzterTag))", "\(kurs(a.letzterSchluss)) \(waehrung)"]]
        if let aktuell = a.aktuellerKurs {
            zeilen.append(["Aktueller Kurs (laufender Tag, kein Schluss)", "\(kurs(aktuell)) \(waehrung)"])
        }
        let spannen: [(Kursanalyse.Spanne, String)] = [(.woche, "1 Woche"), (.monat, "1 Monat"),
                                                       (.quartal, "3 Monate"), (.jahr, "12 Monate")]
        for (spanne, text) in spannen {
            zeilen.append(["Veränderung \(text)", Format.prozent(a.veraenderung[spanne])])
        }
        zeilen.append(["Schwankung aufs Jahr", Format.prozent(a.schwankungJahr)])
        zeilen.append(["Durchschnittliche Tagesspanne (ATR 14)",
                       a.atr14.map { "\(kurs($0)) \(waehrung) (\(Format.prozent(a.atr14Anteil)) vom Kurs)" }
                           ?? "– (unter 15 Tagen)"])
        zeilen.append(["Abstand zum 52-Wochen-Hoch", Format.prozent(a.abstandHoch52W)])
        zeilen.append(["Abstand zum 52-Wochen-Tief", Format.prozent(a.abstandTief52W)])
        zeilen.append(["Größter Rückgang vom Hoch im Zeitraum", Format.prozent(a.groessterRueckgang)])
        return zeilen
    }

    /// Eigene Trades im Wert je Konto und Währung, geschlossen in den `monate` Monaten vor `bis` oder danach.
    static func eigeneTrades(_ export: JournalExport, wunsch: String, monate: Int, bis: Date) -> [String] {
        let seit = kalender(export.nutzerZeitzone).date(byAdding: .month, value: -monate, to: bis)!
        let zone = export.nutzerZeitzone
        var zeilen: [[String]] = []
        for konto in export.konten {
            let passend = konto.trades.filter { symbolschluessel($0.symbol) == wunsch && $0.closeTime >= seit }
            let jeWaehrung = Dictionary(grouping: passend) { $0.waehrung(kontowaehrung: konto.waehrung) }
            for waehrung in jeWaehrung.keys.sorted() {
                let k = Kennzahlen(trades: jeWaehrung[waehrung]!)
                zeilen.append([export.kurzname(konto), waehrung, "\(k.anzahl)", Format.zahl(k.netto),
                               Format.prozent(k.trefferquote), Format.r(k.erwartungswertR)])
            }
        }
        guard !zeilen.isEmpty else {
            return ["\n## Eigene Trades in diesem Wert",
                    "Keine geschlossenen Trades seit \(Format.datum(seit, zone, mitZeit: false))."]
        }
        return ["\n## Eigene Trades in diesem Wert (geschlossen seit \(Format.datum(seit, zone, mitZeit: false)))",
                Format.tabelle(["Konto", "Währung", "Trades", "Netto", "Treffer", "Erw. R"], zeilen),
                "Je Konto und Währung getrennt; Beträge verschiedener Währungen nicht zusammenrechnen. "
                    + "Einzelne Trades über hole_trades mit dem Konto."]
    }

    static func kalender(_ zone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = zone
        return k
    }

    /// Kurse unter 1 (etwa kleine Kryptowerte) mit mehr Stellen.
    static func kurs(_ wert: Decimal) -> String {
        Format.zahl(wert, stellen: abs(wert) < 1 ? 6 : 2)
    }

    /// Vergleichsschlüssel für Symbole: Groß, ohne Trennzeichen („BTC/USD“ gleich „btcusd“).
    static func symbolschluessel(_ symbol: String) -> String {
        String(symbol.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
