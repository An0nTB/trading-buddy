import Foundation

/// Kalendertag ohne Uhrzeit und ohne Zeitzone, in JSON als "2026-12-24".
/// Feiertage und verkürzte Tage gelten immer für den Tag in der Ortszeit der Börse.
public struct Kalendertag: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let jahr: Int
    public let monat: Int
    public let tag: Int

    public init(jahr: Int, monat: Int, tag: Int) throws {
        guard (1...12).contains(monat), (1...31).contains(tag),
              let datum = Kalendertag.utc.date(from: DateComponents(year: jahr, month: monat, day: tag)),
              Kalendertag.utc.component(.day, from: datum) == tag
        else { throw BoersenuhrFehler.ungueltigesDatum(String(format: "%04d-%02d-%02d", jahr, monat, tag)) }
        self.jahr = jahr
        self.monat = monat
        self.tag = tag
    }

    /// Liest "JJJJ-MM-TT".
    public init(_ text: String) throws {
        let teile = text.split(separator: "-", omittingEmptySubsequences: false)
        guard teile.count == 3, teile[0].count == 4, teile[1].count == 2, teile[2].count == 2,
              let jahr = Int(teile[0]), let monat = Int(teile[1]), let tag = Int(teile[2])
        else { throw BoersenuhrFehler.ungueltigesDatum(text) }
        try self.init(jahr: jahr, monat: monat, tag: tag)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do { try self.init(text) } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Datum „\(text)“ ist nicht JJJJ-MM-TT")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String { String(format: "%04d-%02d-%02d", jahr, monat, tag) }

    public static func < (a: Kalendertag, b: Kalendertag) -> Bool {
        (a.jahr, a.monat, a.tag) < (b.jahr, b.monat, b.tag)
    }

    /// Der Tag, auf den `zeitpunkt` in der Zeitzone `zone` fällt.
    public init(_ zeitpunkt: Date, in zone: TimeZone) {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zone
        let teile = kalender.dateComponents([.year, .month, .day], from: zeitpunkt)
        jahr = teile.year!
        monat = teile.month!
        tag = teile.day!
    }

    /// Tag plus `tage` Kalendertage (negativ für zurück).
    public func plus(tage: Int) -> Kalendertag {
        let neu = Kalendertag.utc.date(byAdding: .day, value: tage, to: mittag)!
        return Kalendertag(neu, in: Kalendertag.utc.timeZone)
    }

    public var wochentag: Wochentag {
        Wochentag(kalenderWochentag: Kalendertag.utc.component(.weekday, from: mittag))
    }

    private var mittag: Date {
        Kalendertag.utc.date(from: DateComponents(year: jahr, month: monat, day: tag, hour: 12))!
    }

    static let utc: Calendar = {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(secondsFromGMT: 0)!
        return kalender
    }()
}

/// Uhrzeit in Ortszeit der Börse, in JSON als "09:00".
public struct Uhrzeit: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let stunde: Int
    public let minute: Int

    public init(stunde: Int, minute: Int) throws {
        guard (0...23).contains(stunde), (0...59).contains(minute) else {
            throw BoersenuhrFehler.ungueltigeUhrzeit(String(format: "%02d:%02d", stunde, minute))
        }
        self.stunde = stunde
        self.minute = minute
    }

    /// Liest "HH:MM".
    public init(_ text: String) throws {
        let teile = text.split(separator: ":", omittingEmptySubsequences: false)
        guard teile.count == 2, teile[0].count == 2, teile[1].count == 2,
              let stunde = Int(teile[0]), let minute = Int(teile[1])
        else { throw BoersenuhrFehler.ungueltigeUhrzeit(text) }
        try self.init(stunde: stunde, minute: minute)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do { try self.init(text) } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Uhrzeit „\(text)“ ist nicht HH:MM")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String { String(format: "%02d:%02d", stunde, minute) }

    public static func < (a: Uhrzeit, b: Uhrzeit) -> Bool {
        (a.stunde, a.minute) < (b.stunde, b.minute)
    }
}

/// Wochentag, in JSON als deutsche Abkürzung "Mo" bis "So".
public enum Wochentag: String, Sendable, Hashable, Codable, CaseIterable {
    case montag = "Mo", dienstag = "Di", mittwoch = "Mi", donnerstag = "Do"
    case freitag = "Fr", samstag = "Sa", sonntag = "So"

    /// `Calendar`-Zählung: 1 = Sonntag, 2 = Montag … 7 = Samstag.
    init(kalenderWochentag: Int) {
        let reihe: [Wochentag] = [.sonntag, .montag, .dienstag, .mittwoch, .donnerstag, .freitag, .samstag]
        self = reihe[kalenderWochentag - 1]
    }
}

/// Fehler beim Laden oder Prüfen einer Börsendatei.
public enum BoersenuhrFehler: Error, Equatable, Sendable {
    case ungueltigesDatum(String)
    case ungueltigeUhrzeit(String)
    /// Die Datei hat eine Formatnummer, die diese Version nicht kennt.
    case unbekanntesFormat(id: String, format: Int)
    case unbekannteZeitzone(id: String, zeitzone: String)
    /// Keine Handelszeiten, aber auch nicht durchgehend geöffnet.
    case keineHandelszeiten(id: String)
    /// Ende liegt nicht nach dem Beginn, oder Tage fehlen.
    case ungueltigeHandelszeit(id: String, grund: String)
    /// Zwei Börsen mit derselben Kennung.
    case doppelteBoerse(id: String)
    /// Der Ordner mit den mitgelieferten Börsendateien fehlt im Paket.
    case mitgelieferteDatenFehlen
}
