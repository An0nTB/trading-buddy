import Foundation

/// Basiskennzahlen einer Menge von Trades (R5, Kapitel 08 Abschnitte 2 und 3).
/// Optionale Werte sind `nil`, wenn sie mangels Daten nicht definiert sind.
public struct Kennzahlen: Sendable, Equatable {
    /// Unter dieser Zahl zeigt die App nur Zahlen, keine Schlussfolgerung (R5, 08 Abschnitt 7).
    public static let mindestanzahl = 30

    public var anzahl: Int
    public var gewinner: Int
    public var verlierer: Int
    public var breakeven: Int
    public var netto: Decimal
    public var brutto: Decimal
    public var kosten: Decimal
    /// Kosten ÷ Summe der Brutto-Gewinne.
    public var kostenquote: Decimal?
    public var trefferquote: Decimal?
    public var durchschnittGewinn: Decimal?
    /// Negativ.
    public var durchschnittVerlust: Decimal?
    /// Ø Gewinn ÷ |Ø Verlust|.
    public var payoff: Decimal?
    /// Netto je Trade in Kontowährung.
    public var erwartungswert: Decimal?
    /// Summe Gewinne ÷ |Summe Verluste|.
    public var profitfaktor: Decimal?
    /// Trefferquote, ab der der Payoff gerade reicht: 1 ÷ (1 + Payoff).
    public var breakevenTrefferquote: Decimal?
    /// Mittelwert der R-Multiples aller Trades mit bekanntem Risiko.
    public var erwartungswertR: Decimal?
    public var anzahlMitR: Int
    public var haltedauerGewinner: TimeInterval?
    public var haltedauerVerlierer: TimeInterval?

    public var genugDaten: Bool { anzahl >= Self.mindestanzahl }

    public init(trades: [Trade]) {
        let gewinne = trades.filter { $0.outcome == .win }.map(\.netProfit)
        let verluste = trades.filter { $0.outcome == .loss }.map(\.netProfit)
        let summeGewinne = gewinne.reduce(0, +)
        let summeVerluste = verluste.reduce(0, +)
        let bruttoGewinne = trades.map(\.profit).filter { $0 > 0 }.reduce(0, +)

        anzahl = trades.count
        gewinner = gewinne.count
        verlierer = verluste.count
        breakeven = anzahl - gewinner - verlierer
        netto = trades.map(\.netProfit).reduce(0, +)
        brutto = trades.map(\.profit).reduce(0, +)
        kosten = trades.map(\.costs).reduce(0, +)
        kostenquote = bruttoGewinne > 0 ? -kosten / bruttoGewinne : nil
        trefferquote = anzahl > 0 ? Decimal(gewinner) / Decimal(anzahl) : nil
        durchschnittGewinn = gewinner > 0 ? summeGewinne / Decimal(gewinner) : nil
        durchschnittVerlust = verlierer > 0 ? summeVerluste / Decimal(verlierer) : nil
        if let g = durchschnittGewinn, let v = durchschnittVerlust {
            payoff = g / -v
            breakevenTrefferquote = 1 / (1 + g / -v)
        }
        erwartungswert = anzahl > 0 ? netto / Decimal(anzahl) : nil
        profitfaktor = summeVerluste < 0 ? summeGewinne / -summeVerluste : nil

        let rWerte = trades.compactMap(\.rMultiple)
        anzahlMitR = rWerte.count
        erwartungswertR = rWerte.isEmpty ? nil : rWerte.reduce(0, +) / Decimal(rWerte.count)

        func mittel(_ werte: [TimeInterval]) -> TimeInterval? {
            werte.isEmpty ? nil : werte.reduce(0, +) / Double(werte.count)
        }
        haltedauerGewinner = mittel(trades.filter { $0.outcome == .win }.map(\.holdingTime))
        haltedauerVerlierer = mittel(trades.filter { $0.outcome == .loss }.map(\.holdingTime))
    }

    /// Anteil gelöschter Pending Orders an allen Orders (ausgeführt plus gelöscht).
    public static func stornoquote(ausgefuehrt: Int, geloescht: Int) -> Decimal? {
        let alle = ausgefuehrt + geloescht
        return alle > 0 ? Decimal(geloescht) / Decimal(alle) : nil
    }
}
