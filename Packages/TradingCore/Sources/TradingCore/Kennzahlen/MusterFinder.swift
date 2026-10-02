import Foundation

/// Eine Gruppe aus einer Aufschlüsselung, die sich deutlich vom Rest unterscheidet
/// (Doc 18, Funktion F5). Beschreibt nur vergangene Trades, keine Prognose.
public struct Muster: Sendable, Equatable {
    public var aufteilung: Aufteilung
    /// Schlüssel wie in `Gruppe.schluessel`.
    public var schluessel: String
    /// Kennzahlen der Gruppe; `kennzahlen.anzahl` ist die Stichprobe.
    public var kennzahlen: Kennzahlen
    /// Trades außerhalb der Gruppe, Vergleichsstichprobe.
    public var anzahlRest: Int
    /// Netto je Trade in der Gruppe.
    public var erwartungswert: Decimal
    /// Netto je Trade außerhalb der Gruppe.
    public var erwartungswertRest: Decimal
    /// Erwartungswert der Gruppe minus Erwartungswert des Rests, in Kontowährung je Trade.
    /// Positiv: Die Gruppe lief besser als der Rest.
    public var effekt: Decimal

    public var anzahl: Int { kennzahlen.anzahl }
}

public enum MusterFinder {
    /// Alle Gruppen der gewählten Aufschlüsselungen, sortiert nach Größe des Effekts (Betrag, absteigend).
    ///
    /// Aufgenommen wird eine Gruppe nur, wenn sie selbst und der Rest je mindestens
    /// `mindestanzahl` Trades haben; darunter zeigt die App nur Zahlen, keine Schlussfolgerung
    /// (R5, 08 Abschnitt 7). Bei gleichem Effekt entscheidet die Reihenfolge von
    /// `Aufteilung.allCases`, dann der Schlüssel.
    ///
    /// Achtung Mehrfachvergleich: Wer viele Gruppen durchsucht, findet auch zufällige Unterschiede.
    /// Deshalb gehört zu jedem Muster die Zufallsprüfung (`Muster.zufallsanteil`).
    /// Bei Aufteilungen mit genau zwei Gruppen (z. B. Richtung) erscheinen beide mit
    /// gleichem Betrag und umgekehrtem Vorzeichen.
    public static func finde(_ trades: [Trade], zeitzone: TimeZone,
                             aufteilungen: [Aufteilung] = Aufteilung.allCases,
                             mindestanzahl: Int = Kennzahlen.mindestanzahl) -> [Muster] {
        let gesamtAnzahl = trades.count
        let gesamtNetto: Decimal = trades.map(\.netProfit).reduce(0, +)
        var ergebnis: [Muster] = []
        for aufteilung in aufteilungen {
            let gruppen = Kennzahlen.aufschluesseln(trades, nach: aufteilung, zeitzone: zeitzone)
            // „Ohne Uhrzeit“ beschreibt den Export, nicht das Verhalten; daraus entsteht kein Muster.
            for gruppe in gruppen where gruppe.schluessel != Gruppe.ohneUhrzeit {
                let anzahl = gruppe.kennzahlen.anzahl
                let anzahlRest = gesamtAnzahl - anzahl
                guard anzahl >= mindestanzahl, anzahlRest >= mindestanzahl else { continue }
                let netto = gruppe.kennzahlen.netto
                let erwartung = netto / Decimal(anzahl)
                let erwartungRest = (gesamtNetto - netto) / Decimal(anzahlRest)
                ergebnis.append(Muster(aufteilung: aufteilung, schluessel: gruppe.schluessel,
                                       kennzahlen: gruppe.kennzahlen, anzahlRest: anzahlRest,
                                       erwartungswert: erwartung, erwartungswertRest: erwartungRest,
                                       effekt: erwartung - erwartungRest))
            }
        }
        let reihenfolge = Aufteilung.allCases
        return ergebnis.sorted { a, b in
            let betragA = abs(a.effekt)
            let betragB = abs(b.effekt)
            if betragA != betragB { return betragA > betragB }
            let ia = reihenfolge.firstIndex(of: a.aufteilung) ?? 0
            let ib = reihenfolge.firstIndex(of: b.aufteilung) ?? 0
            if ia != ib { return ia < ib }
            return a.schluessel < b.schluessel
        }
    }
}
