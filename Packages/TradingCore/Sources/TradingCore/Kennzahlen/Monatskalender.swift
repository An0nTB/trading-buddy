import Foundation

/// Ergebnis je Kalendertag eines Monats für den Ergebnis-Kalender der App (Tim 05.10.2026): Netto nach Schlusstag,
/// Summen je Woche und Monat, Gewinn- und Verlusttage. Rechnet in der Währung der übergebenen Trades; die Umrechnung
/// in die Anzeigewährung macht der Aufrufer. Wochen beginnen am Montag.
public struct Monatskalender: Sendable, Equatable {
    /// Ein Kalendertag des Monats mit seinen geschlossenen Trades.
    public struct Tag: Sendable, Equatable, Identifiable {
        /// Beginn des Tages im Kalender des Aufrufers.
        public let beginn: Date
        /// Tag im Monat, 1 bis 31.
        public let tag: Int
        public let netto: Decimal
        public let anzahl: Int
        /// IDs der Trades mit diesem Schlusstag.
        public let trades: [String]

        public var id: Date { beginn }
    }

    /// Eine Kalenderwoche von Montag bis Sonntag; Tage außerhalb des Monats sind `nil`.
    public struct Woche: Sendable, Equatable {
        public let tage: [Tag?]

        public var netto: Decimal { tage.compactMap { $0 }.reduce(0) { $0 + $1.netto } }
        public var anzahl: Int { tage.compactMap { $0 }.reduce(0) { $0 + $1.anzahl } }
    }

    public let jahr: Int
    public let monat: Int
    public let wochen: [Woche]

    /// Alle Tage des Monats in Reihenfolge.
    public var tage: [Tag] { wochen.flatMap { $0.tage.compactMap { $0 } } }
    public var netto: Decimal { tage.reduce(0) { $0 + $1.netto } }
    public var anzahl: Int { tage.reduce(0) { $0 + $1.anzahl } }
    /// Tage mit Trades und positivem Netto.
    public var gewinnTage: Int { tage.filter { $0.anzahl > 0 && $0.netto > 0 }.count }
    /// Tage mit Trades und negativem Netto.
    public var verlustTage: Int { tage.filter { $0.anzahl > 0 && $0.netto < 0 }.count }
    /// Tag mit dem höchsten Netto unter den Gewinntagen; `nil` ohne Gewinntag.
    public var besterTag: Tag? { tage.filter { $0.anzahl > 0 && $0.netto > 0 }.max { $0.netto < $1.netto } }
    /// Tag mit dem niedrigsten Netto unter den Verlusttagen; `nil` ohne Verlusttag.
    public var schlechtesterTag: Tag? { tage.filter { $0.anzahl > 0 && $0.netto < 0 }.min { $0.netto < $1.netto } }
    /// Größter Betrag eines Tages, für die Farbstärke der Zellen; 0 ohne Trades.
    public var groessterBetrag: Decimal { tage.map { abs($0.netto) }.max() ?? 0 }

    /// Ordnet jeden Trade seinem Schlusstag im Kalender zu (`Trade.schlusstag`, auch für Buchungen nur mit Datum)
    /// und baut daraus die Wochen des Monats. Trades anderer Monate zählen nicht.
    public init(trades: [Trade], jahr: Int, monat: Int, kalender: Calendar) {
        self.jahr = jahr
        self.monat = monat
        var montags = kalender
        montags.firstWeekday = 2
        guard let erster = montags.date(from: DateComponents(year: jahr, month: monat, day: 1)),
              let tageImMonat = montags.range(of: .day, in: .month, for: erster)?.count else {
            wochen = []
            return
        }
        var jeTag: [Date: [Trade]] = [:]
        for trade in trades {
            jeTag[trade.schlusstag(montags), default: []].append(trade)
        }
        var tage: [Tag] = []
        for nummer in 1...tageImMonat {
            guard let beginn = montags.date(from: DateComponents(year: jahr, month: monat, day: nummer)) else { continue }
            let liste = (jeTag[montags.startOfDay(for: beginn)] ?? []).sorted { ($0.closeTime, $0.id) < ($1.closeTime, $1.id) }
            tage.append(Tag(beginn: beginn, tag: nummer, netto: liste.reduce(0) { $0 + $1.netProfit },
                            anzahl: liste.count, trades: liste.map(\.id)))
        }
        // Leere Zellen vor dem 1.: Montag = 0, Sonntag = 6.
        let wochentag = montags.component(.weekday, from: erster)
        let versatz = (wochentag + 5) % 7
        var zellen: [Tag?] = Array(repeating: nil, count: versatz) + tage.map { Optional($0) }
        while zellen.count % 7 != 0 { zellen.append(nil) }
        wochen = stride(from: 0, to: zellen.count, by: 7).map { Woche(tage: Array(zellen[$0..<$0 + 7])) }
    }
}
