import Foundation

/// Halboffener Zeitraum: `von` gehört dazu, `bis` nicht.
/// Ein Trade zählt zu dem Zeitraum, in dem er geschlossen wurde.
public struct Zeitspanne: Sendable, Equatable {
    public var von: Date
    public var bis: Date

    public init(von: Date, bis: Date) {
        self.von = von
        self.bis = bis
    }

    public func enthaelt(_ zeitpunkt: Date) -> Bool { von <= zeitpunkt && zeitpunkt < bis }

    /// Kalendermonat in der Zeitzone des Nutzers. `nil` bei ungültigem Monat.
    public static func monat(jahr: Int, monat: Int, zeitzone: TimeZone) -> Zeitspanne? {
        guard (1...12).contains(monat) else { return nil }
        let k = kalender(zeitzone)
        guard let von = k.date(from: DateComponents(year: jahr, month: monat, day: 1)),
              let bis = k.date(byAdding: .month, value: 1, to: von) else { return nil }
        return Zeitspanne(von: von, bis: bis)
    }

    /// Kalendermonat, in den `datum` fällt.
    public static func monat(mit datum: Date, zeitzone: TimeZone) -> Zeitspanne {
        let c = kalender(zeitzone).dateComponents([.year, .month], from: datum)
        return monat(jahr: c.year!, monat: c.month!, zeitzone: zeitzone)!
    }

    /// Woche von Montag bis Sonntag, in die `datum` fällt.
    public static func woche(mit datum: Date, zeitzone: TimeZone) -> Zeitspanne {
        var k = Calendar(identifier: .iso8601)
        k.timeZone = zeitzone
        let woche = k.dateInterval(of: .weekOfYear, for: datum)!
        return Zeitspanne(von: woche.start, bis: woche.end)
    }

    /// Kalenderwoche nach ISO 8601 (Montag bis Sonntag, Woche 1 enthält den ersten Donnerstag).
    /// `nil` für Wochen, die es im Jahr nicht gibt (Woche 53 in Jahren mit 52 Wochen).
    public static func kalenderwoche(jahr: Int, woche: Int, zeitzone: TimeZone) -> Zeitspanne? {
        let k = isoKalender(zeitzone)
        // Woche 1 ist die Woche mit dem 4. Januar; von dort in ganzen Wochen weiter.
        guard (1...53).contains(woche),
              let vierter = k.date(from: DateComponents(year: jahr, month: 1, day: 4)),
              let ersteWoche = k.dateInterval(of: .weekOfYear, for: vierter),
              let montag = k.date(byAdding: .day, value: 7 * (woche - 1), to: ersteWoche.start),
              k.component(.yearForWeekOfYear, from: montag) == jahr,
              let bis = k.date(byAdding: .day, value: 7, to: montag) else { return nil }
        return Zeitspanne(von: montag, bis: bis)
    }

    /// Jahr und Nummer der ISO-Kalenderwoche, wenn die Spanne genau eine solche Woche ist, sonst `nil`.
    /// Für Titel und Dateinamen wie „2026-W40“.
    public func kalenderwoche(zeitzone: TimeZone) -> (jahr: Int, woche: Int)? {
        let k = Self.isoKalender(zeitzone)
        let c = k.dateComponents([.yearForWeekOfYear, .weekOfYear], from: von)
        guard let jahr = c.yearForWeekOfYear, let woche = c.weekOfYear,
              Self.kalenderwoche(jahr: jahr, woche: woche, zeitzone: zeitzone) == self else { return nil }
        return (jahr, woche)
    }

    /// Ganze Tage von `vonTag` bis einschließlich `bisTag`.
    /// `nil` bei ungültigem Datum (etwa 30. Februar) oder wenn `bisTag` vor `vonTag` liegt.
    public static func tage(von vonTag: DateComponents, bis bisTag: DateComponents,
                            zeitzone: TimeZone) -> Zeitspanne? {
        let k = kalender(zeitzone)
        guard let von = tag(vonTag, k), let letzter = tag(bisTag, k), letzter >= von,
              let bis = k.date(byAdding: .day, value: 1, to: letzter) else { return nil }
        return Zeitspanne(von: von, bis: bis)
    }

    /// Gleich langer Zeitraum direkt davor: bei ganzen Monaten dieselbe Zahl Monate,
    /// bei ganzen Tagen dieselbe Zahl Tage, sonst dieselbe Dauer.
    public func vorzeitraum(zeitzone: TimeZone) -> Zeitspanne {
        let k = Self.kalender(zeitzone)
        if let monate = k.dateComponents([.month], from: von, to: bis).month, monate > 0,
           k.date(byAdding: .month, value: monate, to: von) == bis,
           let start = k.date(byAdding: .month, value: -monate, to: von) {
            return Zeitspanne(von: start, bis: von)
        }
        if let tage = k.dateComponents([.day], from: von, to: bis).day, tage > 0,
           k.date(byAdding: .day, value: tage, to: von) == bis,
           let start = k.date(byAdding: .day, value: -tage, to: von) {
            return Zeitspanne(von: start, bis: von)
        }
        return Zeitspanne(von: von.addingTimeInterval(-bis.timeIntervalSince(von)), bis: von)
    }

    private static func kalender(_ zeitzone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = zeitzone
        return k
    }

    private static func isoKalender(_ zeitzone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .iso8601)
        k.timeZone = zeitzone
        return k
    }

    /// Tagesbeginn; `nil`, wenn der Kalender das Datum erst umrechnen müsste.
    private static func tag(_ c: DateComponents, _ k: Calendar) -> Date? {
        guard let j = c.year, let m = c.month, let t = c.day,
              let datum = k.date(from: DateComponents(year: j, month: m, day: t)) else { return nil }
        let probe = k.dateComponents([.year, .month, .day], from: datum)
        return probe.year == j && probe.month == m && probe.day == t ? datum : nil
    }
}
