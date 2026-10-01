import Foundation

/// Feiertagskalender, den der Nutzer selbst hinzufügt, zum Beispiel für ein anderes Land
/// oder einen Handelsplatz mit eigenen Ruhetagen. Eine Börse kann mehrere davon tragen;
/// ihre Feiertage gelten dann zusätzlich zu den eigenen der Börse.
public struct Feiertagskalender: Sendable, Hashable, Identifiable, Codable {
    public static let unterstuetztesFormat = 1

    public var format: Int
    /// Kurze Kennung, zum Beispiel "ch" oder "jp-tse". Eindeutig innerhalb einer Auswahl.
    public var id: String
    public var name: String
    /// Land nach ISO 3166-1 alpha-2, wenn es passt (zum Beispiel "CH").
    public var land: String?
    public var feiertage: [Feiertag]
    public var verkuerzteTage: [VerkuerzterTag]
    /// Bis zu diesem Tag ist der Kalender gepflegt.
    public var datenGueltigBis: Kalendertag?
    public var stand: Kalendertag
    public var quellen: [Quelle]
    public var hinweise: [String]

    public init(format: Int = Feiertagskalender.unterstuetztesFormat, id: String, name: String, land: String? = nil,
                feiertage: [Feiertag], verkuerzteTage: [VerkuerzterTag] = [], datenGueltigBis: Kalendertag? = nil,
                stand: Kalendertag, quellen: [Quelle] = [], hinweise: [String] = []) throws {
        self.format = format
        self.id = id
        self.name = name
        self.land = land
        self.feiertage = feiertage
        self.verkuerzteTage = verkuerzteTage
        self.datenGueltigBis = datenGueltigBis
        self.stand = stand
        self.quellen = quellen
        self.hinweise = hinweise
        try pruefe()
    }

    private enum CodingKeys: String, CodingKey {
        case format, id, name, land, feiertage, verkuerzteTage, datenGueltigBis, stand, quellen, hinweise
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        land = try c.decodeIfPresent(String.self, forKey: .land)
        feiertage = try c.decodeIfPresent([Feiertag].self, forKey: .feiertage) ?? []
        verkuerzteTage = try c.decodeIfPresent([VerkuerzterTag].self, forKey: .verkuerzteTage) ?? []
        datenGueltigBis = try c.decodeIfPresent(Kalendertag.self, forKey: .datenGueltigBis)
        stand = try c.decode(Kalendertag.self, forKey: .stand)
        quellen = try c.decodeIfPresent([Quelle].self, forKey: .quellen) ?? []
        hinweise = try c.decodeIfPresent([String].self, forKey: .hinweise) ?? []
    }

    /// Liest eine Kalenderdatei und prüft sie.
    public static func lade(json: Data) throws -> Feiertagskalender {
        let kalender = try JSONDecoder().decode(Feiertagskalender.self, from: json)
        try kalender.pruefe()
        return kalender
    }

    public func pruefe() throws {
        guard format == Feiertagskalender.unterstuetztesFormat else {
            throw BoersenuhrFehler.unbekanntesFormat(id: id, format: format)
        }
    }
}

extension Boerse {
    /// Kopie, in der die Feiertage und verkürzten Tage der Kalender zusätzlich gelten.
    /// Fällt ein Tag in mehreren Quellen auf, gewinnt der Feiertag vor dem verkürzten Tag
    /// und beim verkürzten Tag der früheste Schluss. `datenGueltigBis` wird der früheste
    /// gepflegte Tag aller Quellen, damit die Uhr warnt, sobald einer davon ausläuft.
    public func mitKalendern(_ kalender: [Feiertagskalender]) -> Boerse {
        guard !kalender.isEmpty, !durchgehend else { return self }
        var kopie = self
        var feiertagsdaten = Set(feiertage.map(\.datum))
        for k in kalender {
            for tag in k.feiertage where feiertagsdaten.insert(tag.datum).inserted {
                kopie.feiertage.append(Feiertag(datum: tag.datum, name: "\(tag.name) (\(k.name))"))
            }
        }
        var kurz: [Kalendertag: VerkuerzterTag] = [:]
        for tag in verkuerzteTage + kalender.flatMap(\.verkuerzteTage) {
            if let alt = kurz[tag.datum], alt.ende <= tag.ende { continue }
            kurz[tag.datum] = tag
        }
        kopie.verkuerzteTage = kurz.values.filter { !feiertagsdaten.contains($0.datum) }.sorted { $0.datum < $1.datum }
        kopie.feiertage.sort { $0.datum < $1.datum }
        let grenzen = ([datenGueltigBis] + kalender.map(\.datenGueltigBis)).compactMap { $0 }
        kopie.datenGueltigBis = grenzen.min()
        return kopie
    }
}
