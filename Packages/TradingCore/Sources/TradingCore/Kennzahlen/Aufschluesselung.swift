import Foundation

/// Merkmal, nach dem die Kennzahlen aufgeteilt werden (R5, Kapitel 08 Abschnitt 8).
/// Heißt nicht `Dimension`, weil Foundation diesen Namen schon für Maßeinheiten belegt.
public enum Aufteilung: String, Sendable, CaseIterable {
    case symbol
    case richtung
    /// ISO-Wochentag der Eröffnung, 1 = Montag.
    case wochentag
    /// Stunde der Eröffnung, 0 bis 23.
    case stunde
    /// Wievielter Trade des Tages (nach Eröffnung).
    case tradeNummerAmTag
    /// Ergebnis des zeitlich vorherigen Trades (nach Schlusszeit).
    case nachVorherigem
    case haltedauer
}

/// Klassen der Haltedauer, grob nach Handelsstil.
public enum Haltedauerklasse: String, Sendable, CaseIterable {
    case unter5Minuten
    case unter1Stunde
    case unter1Tag
    case ueber1Tag

    public init(_ dauer: TimeInterval) {
        switch dauer {
        case ..<300: self = .unter5Minuten
        case ..<3600: self = .unter1Stunde
        case ..<86400: self = .unter1Tag
        default: self = .ueber1Tag
        }
    }
}

public struct Gruppe: Sendable, Equatable {
    /// Schlüssel als Text: Symbol, „buy“/„sell“, Wochentag „1“–„7“, Stunde „0“–„23“,
    /// Trade-Nummer, „nachGewinn“/„nachVerlust“/„nachBreakeven“/„erster“ oder Haltedauerklasse.
    /// Trades ohne Uhrzeit (`Trade.nurDatum`) stehen bei Stunde, Haltedauer und Trade-Nummer unter `ohneUhrzeit`.
    public var schluessel: String

    public static let ohneUhrzeit = "ohneUhrzeit"
    public var kennzahlen: Kennzahlen
}

extension Kennzahlen {
    /// Kennzahlen je Gruppe, sortiert nach Schlüssel (Zahlen numerisch).
    /// - Parameter zeitzone: Zeitzone für Wochentag, Stunde und Tagesgrenze, in der Regel die des Nutzers.
    public static func aufschluesseln(_ trades: [Trade], nach dimension: Aufteilung,
                                      zeitzone: TimeZone) -> [Gruppe] {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let schluessel = schluesselJeTrade(trades, dimension: dimension, kalender: kalender)
        let gruppen = Dictionary(grouping: trades.indices) { schluessel[$0] }
        return gruppen
            .map { Gruppe(schluessel: $0.key, kennzahlen: Kennzahlen(trades: $0.value.map { trades[$0] })) }
            .sorted { a, b in
                if let x = Int(a.schluessel), let y = Int(b.schluessel) { return x < y }
                return a.schluessel < b.schluessel
            }
    }

    private static func schluesselJeTrade(_ trades: [Trade], dimension: Aufteilung,
                                          kalender: Calendar) -> [String] {
        switch dimension {
        case .symbol:
            return trades.map(\.symbol)
        case .richtung:
            return trades.map(\.side.rawValue)
        case .wochentag:
            // Calendar zählt Sonntag als 1; umgerechnet auf ISO mit Montag = 1.
            return trades.map { String((kalender.component(.weekday, from: $0.openTime) + 5) % 7 + 1) }
        case .stunde:
            return trades.map { $0.nurDatum ? Gruppe.ohneUhrzeit : String(kalender.component(.hour, from: $0.openTime)) }
        case .haltedauer:
            return trades.map { $0.nurDatum ? Gruppe.ohneUhrzeit : Haltedauerklasse($0.holdingTime).rawValue }
        case .tradeNummerAmTag:
            var ergebnis = Array(repeating: "", count: trades.count)
            var zaehler: [Date: Int] = [:]
            for i in trades.indices.sorted(by: { (trades[$0].openTime, trades[$0].id) < (trades[$1].openTime, trades[$1].id) }) {
                // Ohne Uhrzeit ist die Reihenfolge am Tag unbekannt; solche Trades zählen nicht mit.
                guard !trades[i].nurDatum else { ergebnis[i] = Gruppe.ohneUhrzeit; continue }
                let tag = kalender.startOfDay(for: trades[i].openTime)
                zaehler[tag, default: 0] += 1
                ergebnis[i] = String(zaehler[tag]!)
            }
            return ergebnis
        case .nachVorherigem:
            var ergebnis = Array(repeating: "", count: trades.count)
            var vorher: Trade.Outcome?
            for i in trades.indices.sorted(by: { (trades[$0].closeTime, trades[$0].id) < (trades[$1].closeTime, trades[$1].id) }) {
                switch vorher {
                case nil: ergebnis[i] = "erster"
                case .win: ergebnis[i] = "nachGewinn"
                case .loss: ergebnis[i] = "nachVerlust"
                case .breakeven: ergebnis[i] = "nachBreakeven"
                }
                vorher = trades[i].outcome
            }
            return ergebnis
        }
    }
}
