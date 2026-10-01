import Foundation

/// Zahlen für die Anzeige. Beträge immer mit Vorzeichen, damit Gewinn und Verlust
/// nicht nur an der Farbe erkennbar sind (Doc 10, Diagrammregeln).
enum Format {
    static func geld(_ wert: Decimal, _ waehrung: String) -> String {
        (wert > 0 ? "+" : "") + wert.formatted(.currency(code: waehrung))
    }

    static func betrag(_ wert: Decimal, _ waehrung: String) -> String {
        wert.formatted(.currency(code: waehrung))
    }

    static func prozent(_ wert: Decimal?) -> String {
        guard let wert else { return "–" }
        return wert.formatted(.percent.precision(.fractionLength(1)))
    }

    static func zahl(_ wert: Decimal?, stellen: Int = 2) -> String {
        guard let wert else { return "–" }
        return wert.formatted(.number.precision(.fractionLength(stellen)))
    }

    static func r(_ wert: Decimal?) -> String {
        guard let wert else { return "–" }
        return (wert > 0 ? "+" : "") + wert.formatted(.number.precision(.fractionLength(2))) + " R"
    }

    static func dauer(_ sekunden: TimeInterval?) -> String {
        guard let sekunden else { return "–" }
        return Duration.seconds(sekunden)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func double(_ wert: Decimal) -> Double {
        NSDecimalNumber(decimal: wert).doubleValue
    }
}
