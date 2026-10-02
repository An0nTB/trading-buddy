import Foundation

/// Zählt Abrufe je Kalendertag (UTC), damit die Merkliste unter der Gratisgrenze bleibt
/// (Marketaux 100 am Tag). Die App speichert den Stand, damit ein Neustart nicht neu zählt.
public struct Abrufbudget: Codable, Sendable, Equatable {
    public let grenzeJeTag: Int
    public private(set) var tag: String
    public private(set) var verbraucht: Int

    public init(grenzeJeTag: Int, jetzt: Date) {
        self.grenzeJeTag = grenzeJeTag
        self.tag = Self.tagesschluessel(jetzt)
        self.verbraucht = 0
    }

    public func rest(jetzt: Date) -> Int {
        tag == Self.tagesschluessel(jetzt) ? max(grenzeJeTag - verbraucht, 0) : grenzeJeTag
    }

    /// Bucht einen Abruf, wenn noch einer frei ist.
    public mutating func buche(jetzt: Date) -> Bool {
        let heute = Self.tagesschluessel(jetzt)
        if heute != tag {
            tag = heute
            verbraucht = 0
        }
        guard verbraucht < grenzeJeTag else { return false }
        verbraucht += 1
        return true
    }

    static func tagesschluessel(_ datum: Date) -> String {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "UTC")!
        let teile = kalender.dateComponents([.year, .month, .day], from: datum)
        func zweistellig(_ zahl: Int?) -> String { zahl.map { $0 < 10 ? "0\($0)" : "\($0)" } ?? "00" }
        return "\(teile.year ?? 0)-\(zweistellig(teile.month))-\(zweistellig(teile.day))"
    }
}
