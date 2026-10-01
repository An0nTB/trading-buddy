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

    /// Tagesbeginn; `nil`, wenn der Kalender das Datum erst umrechnen müsste.
    private static func tag(_ c: DateComponents, _ k: Calendar) -> Date? {
        guard let j = c.year, let m = c.month, let t = c.day,
              let datum = k.date(from: DateComponents(year: j, month: m, day: t)) else { return nil }
        let probe = k.dateComponents([.year, .month, .day], from: datum)
        return probe.year == j && probe.month == m && probe.day == t ? datum : nil
    }
}
