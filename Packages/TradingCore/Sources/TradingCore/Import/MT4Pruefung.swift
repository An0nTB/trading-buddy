import Foundation

/// Eine Stelle, an der die gelesenen Zeilen nicht zu den Summen im Auszug passen.
public struct Abweichung: Sendable, Equatable, CustomStringConvertible {
    public var pruefung: String
    public var erwartet: Decimal
    public var gefunden: Decimal

    public var description: String { "\(pruefung): erwartet \(erwartet), gefunden \(gefunden)" }
}

extension MT4Statement {
    /// Rechnet den Auszug gegen seine eigenen Summen nach. Leer heißt: Jede Zeile
    /// wurde gelesen und alle Summen stimmen auf den Cent.
    public func pruefe() -> [Abweichung] {
        var ergebnis: [Abweichung] = []
        func vergleiche(_ name: String, _ erwartet: Decimal, _ gefunden: Decimal) {
            if erwartet != gefunden {
                ergebnis.append(Abweichung(pruefung: name, erwartet: erwartet, gefunden: gefunden))
            }
        }
        func summe<T>(_ liste: [T], _ wert: (T) -> Decimal) -> Decimal {
            liste.reduce(Decimal(0)) { $0 + wert($1) }
        }

        vergleiche("Kommission geschlossen", closedTotals.commission, summe(closedPositions) { $0.commission })
        vergleiche("Swap geschlossen", closedTotals.swap, summe(closedPositions) { $0.swap })
        vergleiche("Kursergebnis geschlossen", closedTotals.profit, summe(closedPositions) { $0.profit })
        vergleiche("Closed Trade P/L", closedTradePL, closedTotals.net)
        vergleiche("Closed Trade P/L Übersicht", summary.closedTradePL, closedTradePL)

        vergleiche("Kommission offen", openTotals.commission, summe(openPositions) { $0.commission })
        vergleiche("Swap offen", openTotals.swap, summe(openPositions) { $0.swap })
        vergleiche("Kursergebnis offen", openTotals.profit, summe(openPositions) { $0.profit })
        vergleiche("Floating P/L", floatingPL, openTotals.net)
        vergleiche("Floating P/L Übersicht", summary.floatingPL, floatingPL)

        if let vortag = summary.previousBalance {
            vergleiche("Kontostand", summary.balance, vortag + summary.closedTradePL + summary.depositWithdrawal)
        }
        vergleiche("Equity", summary.equity, summary.balance + summary.floatingPL)
        return ergebnis
    }
}
