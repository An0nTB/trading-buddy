import Foundation

/// Kalendertag ohne Uhrzeit und ohne Zeitzone, z. B. 2026-10-02. Für Tagesnotizen und Bildverweise,
/// damit ein Tag gleich bleibt, wenn der Nutzer die Zeitzone wechselt. Codable als Text „JJJJ-MM-TT“.
/// Eigener Name, weil TradingClock schon `Kalendertag` hat und die App beide Pakete einbindet.
public struct Journaltag: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let jahr: Int
    public let monat: Int
    public let tag: Int

    /// `nil` für Tage, die es nicht gibt (30. Februar).
    public init?(jahr: Int, monat: Int, tag: Int) {
        let k = Self.gregorianisch(TimeZone(secondsFromGMT: 0)!)
        guard let datum = k.date(from: DateComponents(year: jahr, month: monat, day: tag)) else { return nil }
        let zurueck = k.dateComponents([.year, .month, .day], from: datum)
        guard zurueck.year == jahr, zurueck.month == monat, zurueck.day == tag else { return nil }
        self.jahr = jahr
        self.monat = monat
        self.tag = tag
    }

    /// Kalendertag eines Zeitpunkts in der Zeitzone des Nutzers.
    public init(_ zeit: Date, zeitzone: TimeZone) {
        let teile = Self.gregorianisch(zeitzone).dateComponents([.year, .month, .day], from: zeit)
        jahr = teile.year!
        monat = teile.month!
        tag = teile.day!
    }

    /// Liest „JJJJ-MM-TT“; alles andere ergibt `nil`.
    public init?(_ text: String) {
        let teile = text.split(separator: "-", omittingEmptySubsequences: false)
        guard teile.count == 3, teile[0].count == 4, teile[1].count == 2, teile[2].count == 2,
              let j = Int(teile[0]), let m = Int(teile[1]), let t = Int(teile[2]) else { return nil }
        self.init(jahr: j, monat: m, tag: t)
    }

    public var description: String {
        func stellen(_ zahl: Int, _ n: Int) -> String {
            let text = String(zahl)
            return String(repeating: "0", count: max(0, n - text.count)) + text
        }
        return "\(stellen(jahr, 4))-\(stellen(monat, 2))-\(stellen(tag, 2))"
    }

    /// Beginn des Tages in der Zeitzone, auch an Tagen mit Zeitumstellung.
    public func beginn(in zeitzone: TimeZone) -> Date {
        Self.gregorianisch(zeitzone).date(from: DateComponents(year: jahr, month: monat, day: tag))!
    }

    public static func < (a: Journaltag, b: Journaltag) -> Bool {
        (a.jahr, a.monat, a.tag) < (b.jahr, b.monat, b.tag)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let tag = Journaltag(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Kein Journaltag: \(text)"))
        }
        self = tag
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    static func gregorianisch(_ zeitzone: TimeZone) -> Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = zeitzone
        return k
    }
}

/// Notiz zu einem Handelstag: Plan vor dem Handel und Rückblick danach (Doc 18 F4).
public struct Tagesnotiz: Sendable, Equatable {
    public var tag: Journaltag
    /// Plan vor dem Handel: Marktlage, Szenarien, was heute nicht passieren soll.
    public var plan: String
    /// Wann der Plan zuerst gespeichert wurde. Spätere Änderungen verschieben den Zeitpunkt nicht,
    /// sonst zählt ein nachträglich korrigierter Plan nicht mehr als „vor dem Handel“.
    public var planErstellt: Date?
    public var rueckblick: String
    /// Eigene Verfassung von 1 (schlecht) bis 5 (sehr gut); freiwillig.
    public var verfassung: Int?
    public var erstellt: Date
    public var geaendert: Date

    public init(tag: Journaltag, plan: String = "", planErstellt: Date? = nil, rueckblick: String = "",
                verfassung: Int? = nil, erstellt: Date, geaendert: Date? = nil) {
        self.tag = tag
        self.plan = plan
        self.planErstellt = planErstellt
        self.rueckblick = rueckblick
        self.verfassung = verfassung
        self.erstellt = erstellt
        self.geaendert = geaendert ?? erstellt
    }

    /// Plan mit Inhalt, der vor `zeit` gespeichert war.
    public func hatPlan(vor zeit: Date) -> Bool {
        guard let erstellt = planErstellt else { return false }
        return !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && erstellt <= zeit
    }
}

/// Verweis auf ein Bild (Screenshot) im Bilderordner der App. Die Bilddaten selbst liegen nie im Speicher
/// oder im Export, nur der relative Pfad.
public struct Bildverweis: Sendable, Hashable {
    public enum Bezug: Sendable, Hashable {
        case trade(String)
        case tag(Journaltag)
        case verpassterTrade(String)
    }

    /// Pfad relativ zum Bilderordner, z. B. „2026-10/3F2A9C.png“.
    public var datei: String
    public var bezug: Bezug
    public var beschriftung: String
    public var erstellt: Date

    public init(datei: String, bezug: Bezug, beschriftung: String = "", erstellt: Date) {
        self.datei = datei
        self.bezug = bezug
        self.beschriftung = beschriftung
        self.erstellt = erstellt
    }

    public static let endungen: Set<String> = ["png", "jpg", "jpeg", "heic"]

    /// Nur relative Pfade ohne „..“ und mit Bildendung, damit ein Verweis nie aus dem Bilderordner führt.
    public static func istGueltig(_ datei: String) -> Bool {
        guard !datei.isEmpty, !datei.hasPrefix("/"), !datei.hasPrefix("~"), !datei.contains("\\"),
              !datei.contains("\0") else { return false }
        let teile = datei.split(separator: "/", omittingEmptySubsequences: false)
        guard teile.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let letzter = teile.last, let punkt = letzter.lastIndex(of: ".") else { return false }
        return endungen.contains(letzter[letzter.index(after: punkt)...].lowercased())
    }
}

/// Trade, der dem eigenen Setup entsprach, aber nicht eingegangen wurde, mit Grund (Doc 18 F4).
public struct VerpassterTrade: Sendable, Equatable, Identifiable {
    public enum Grund: String, Sendable, Codable, CaseIterable {
        /// Gezögert, Angst vor dem Verlust.
        case zoegern
        /// Zu spät gesehen, Einstieg verpasst.
        case zuSpaet
        /// Eine eigene Handelsregel hat ihn verboten; gewollt verpasst.
        case regelSperre
        /// Nicht am Rechner.
        case nichtAmPlatz
        /// Setup nicht sicher erkannt.
        case unsicheresSetup
        case sonstiges
    }

    public var id: String
    public var zeit: Date
    public var symbol: String
    public var seite: Side
    /// Setup-Name aus dem Playbook; freiwillig.
    public var setup: String?
    public var grund: Grund
    public var notiz: String
    /// Geschätztes Ergebnis in R (Vielfache des geplanten Risikos); freiwillig.
    public var ergebnisR: Decimal?

    public init(id: String = UUID().uuidString, zeit: Date, symbol: String, seite: Side, setup: String? = nil,
                grund: Grund, notiz: String = "", ergebnisR: Decimal? = nil) {
        self.id = id
        self.zeit = zeit
        self.symbol = symbol
        self.seite = seite
        self.setup = setup
        self.grund = grund
        self.notiz = notiz
        self.ergebnisR = ergebnisR
    }
}
