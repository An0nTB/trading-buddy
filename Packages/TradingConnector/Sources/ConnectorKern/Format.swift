import Foundation
import TradingCore

/// Zahlen und Zeiten auf Deutsch, knapp gehalten (spart Tokens).
enum Format {
    static let deutsch = Locale(identifier: "de_DE")

    static func zahl(_ wert: Decimal, stellen: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = deutsch
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = stellen
        f.maximumFractionDigits = stellen
        return f.string(from: NSDecimalNumber(decimal: wert.gerundet(stellen))) ?? "\(wert)"
    }

    static func zahl(_ wert: Decimal?, stellen: Int = 2) -> String {
        wert.map { zahl($0, stellen: stellen) } ?? "–"
    }

    static func prozent(_ anteil: Decimal?) -> String {
        anteil.map { zahl($0 * 100, stellen: 1) + " %" } ?? "–"
    }

    static func r(_ wert: Decimal?) -> String {
        wert.map { zahl($0) + " R" } ?? "–"
    }

    static func dauer(_ sekunden: TimeInterval?) -> String {
        guard let s = sekunden else { return "–" }
        return switch s {
        case ..<3600: "\(Int((s / 60).rounded())) Min."
        case ..<86400: zahl(Decimal(s / 3600), stellen: 1) + " Std."
        default: zahl(Decimal(s / 86400), stellen: 1) + " Tage"
        }
    }

    static func datum(_ zeitpunkt: Date, _ zeitzone: TimeZone, mitZeit: Bool = true) -> String {
        formatiert(zeitpunkt, zeitzone, mitZeit ? "dd.MM.yyyy HH:mm" : "dd.MM.yyyy")
    }

    /// Kurzer Wochentag, z. B. „Mo.“.
    static func wochentag(_ zeitpunkt: Date, _ zeitzone: TimeZone) -> String {
        formatiert(zeitpunkt, zeitzone, "EE")
    }

    /// Ganzer Monat als „Mai 2025“, sonst „12.05.2025 bis 18.05.2025“ (beide Tage einschließlich).
    static func zeitraum(_ z: Zeitspanne, _ zeitzone: TimeZone) -> String {
        if Zeitspanne.monat(mit: z.von, zeitzone: zeitzone) == z {
            return formatiert(z.von, zeitzone, "LLLL yyyy")
        }
        return "\(datum(z.von, zeitzone, mitZeit: false)) bis "
            + datum(z.bis.addingTimeInterval(-1), zeitzone, mitZeit: false)
    }

    private static func formatiert(_ zeitpunkt: Date, _ zeitzone: TimeZone, _ muster: String) -> String {
        let f = DateFormatter()
        f.locale = deutsch
        f.timeZone = zeitzone
        f.dateFormat = muster
        return f.string(from: zeitpunkt)
    }

    /// Freitext für Tabellen: einzeilig, ohne Tabellenzeichen, höchstens `zeichen` lang.
    static func kurz(_ text: String?, zeichen: Int = 120) -> String {
        // Alle Zeilenumbrüche (auch \r, \r\n, U+2028) und Leerraum zu einem Leerzeichen, damit die Tabellenzeile hält.
        let einzeilig = (text ?? "").replacingOccurrences(of: "|", with: "/")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !einzeilig.isEmpty else { return "–" }
        return einzeilig.count > zeichen ? String(einzeilig.prefix(zeichen)) + "…" : einzeilig
    }

    /// Markdown-Tabelle; kompakter als Fließtext und für Claude eindeutig.
    static func tabelle(_ kopf: [String], _ zeilen: [[String]]) -> String {
        let alle = [kopf, kopf.map { _ in "---" }] + zeilen
        return alle.map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
    }
}
