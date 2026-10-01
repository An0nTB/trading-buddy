import Foundation
import TradingCore

/// Zahlen und Zeiten für die Anzeige. Beträge immer mit Vorzeichen, damit Gewinn und Verlust
/// nicht nur an der Farbe erkennbar sind (Doc 10, Diagrammregeln). Zeiten in der Zeitzone des Nutzers.
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

    /// Kurse mit so vielen Nachkommastellen, wie der Broker liefert (höchstens fünf).
    static func kurs(_ wert: Decimal) -> String {
        wert.formatted(.number.precision(.fractionLength(0...5)))
    }

    static func lots(_ wert: Decimal) -> String {
        wert.formatted(.number.precision(.fractionLength(1...2)))
    }

    static func dauer(_ sekunden: TimeInterval?) -> String {
        guard let sekunden else { return "–" }
        return Duration.seconds(sekunden)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// Tag und Uhrzeit, z. B. „02.06., 18:02“.
    static func zeit(_ datum: Date) -> String {
        datum.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute())
    }

    static func uhrzeit(_ datum: Date) -> String {
        datum.formatted(.dateTime.hour().minute())
    }

    /// Datum mit Jahr, z. B. „02.06.2025“.
    static func datum(_ datum: Date) -> String {
        datum.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }

    /// Monat mit Jahr, z. B. „Juni 2025“.
    static func monat(_ datum: Date) -> String {
        datum.formatted(.dateTime.month(.wide).year())
    }

    static func richtung(_ side: Side) -> String {
        side == .buy ? String(localized: "Long") : String(localized: "Short")
    }

    static func double(_ wert: Decimal) -> Double {
        NSDecimalNumber(decimal: wert).doubleValue
    }
}
