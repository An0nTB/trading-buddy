import Foundation

/// Eine Börse mit Handelszeiten und Feiertagen, so wie sie in der JSON-Datei steht.
/// Alle Zeiten sind Ortszeit der Börse mit IANA-Zonenname (R1 Abschnitt 6): Sommerzeit
/// rechnet `TimeZone` je Datum selbst, feste UTC-Abstände stehen nirgends in den Daten.
public struct Boerse: Sendable, Hashable, Identifiable, Codable {
    /// Formatnummer der Datei. Steigt, wenn sich der Aufbau so ändert, dass alte Leser ihn falsch verstünden.
    public static let unterstuetztesFormat = 1

    public var format: Int
    /// Kurze Kennung, zum Beispiel "xetra". Eindeutig innerhalb der Uhr.
    public var id: String
    public var name: String
    /// Market Identifier Code nach ISO 10383, wenn es einen gibt (Forex und Krypto haben keinen).
    public var mic: String?
    /// IANA-Zonenname, zum Beispiel "Europe/Berlin".
    public var zeitzone: String
    /// Rund um die Uhr an allen Tagen geöffnet (Krypto). Handelszeiten und Feiertage gelten dann nicht.
    public var durchgehend: Bool
    public var handelszeiten: [Handelszeit]
    /// Tage ohne Handel. Es entfällt jede Sitzung, die an diesem Tag (Ortszeit) beginnt.
    public var feiertage: [Feiertag]
    /// Tage mit früherem Schluss. Gilt für die Sitzung, die an diesem Tag (Ortszeit) endet.
    public var verkuerzteTage: [VerkuerzterTag]
    /// Bis zu diesem Tag sind Feiertage gepflegt. Danach rechnet die Uhr nur mit den Wochenzeiten.
    public var datenGueltigBis: Kalendertag?
    /// Tag der letzten Pflege der Datei.
    public var stand: Kalendertag
    public var quellen: [Quelle]
    /// Annahmen und Besonderheiten in Klartext.
    public var hinweise: [String]

    public init(format: Int = Boerse.unterstuetztesFormat, id: String, name: String, mic: String? = nil,
                zeitzone: String, durchgehend: Bool = false, handelszeiten: [Handelszeit] = [],
                feiertage: [Feiertag] = [], verkuerzteTage: [VerkuerzterTag] = [],
                datenGueltigBis: Kalendertag? = nil, stand: Kalendertag, quellen: [Quelle] = [],
                hinweise: [String] = []) throws {
        self.format = format
        self.id = id
        self.name = name
        self.mic = mic
        self.zeitzone = zeitzone
        self.durchgehend = durchgehend
        self.handelszeiten = handelszeiten
        self.feiertage = feiertage
        self.verkuerzteTage = verkuerzteTage
        self.datenGueltigBis = datenGueltigBis
        self.stand = stand
        self.quellen = quellen
        self.hinweise = hinweise
        try pruefe()
    }

    private enum CodingKeys: String, CodingKey {
        case format, id, name, mic, zeitzone, durchgehend, handelszeiten, feiertage, verkuerzteTage
        case datenGueltigBis, stand, quellen, hinweise
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mic = try c.decodeIfPresent(String.self, forKey: .mic)
        zeitzone = try c.decode(String.self, forKey: .zeitzone)
        durchgehend = try c.decodeIfPresent(Bool.self, forKey: .durchgehend) ?? false
        handelszeiten = try c.decodeIfPresent([Handelszeit].self, forKey: .handelszeiten) ?? []
        feiertage = try c.decodeIfPresent([Feiertag].self, forKey: .feiertage) ?? []
        verkuerzteTage = try c.decodeIfPresent([VerkuerzterTag].self, forKey: .verkuerzteTage) ?? []
        datenGueltigBis = try c.decodeIfPresent(Kalendertag.self, forKey: .datenGueltigBis)
        stand = try c.decode(Kalendertag.self, forKey: .stand)
        quellen = try c.decodeIfPresent([Quelle].self, forKey: .quellen) ?? []
        hinweise = try c.decodeIfPresent([String].self, forKey: .hinweise) ?? []
    }

    /// Liest eine Börsendatei und prüft sie.
    public static func lade(json: Data) throws -> Boerse {
        let boerse = try JSONDecoder().decode(Boerse.self, from: json)
        try boerse.pruefe()
        return boerse
    }

    /// Prüft, was der JSON-Decoder allein nicht sieht: Format, Zeitzone, sinnvolle Handelszeiten.
    public func pruefe() throws {
        guard format == Boerse.unterstuetztesFormat else {
            throw BoersenuhrFehler.unbekanntesFormat(id: id, format: format)
        }
        guard TimeZone(identifier: zeitzone) != nil else {
            throw BoersenuhrFehler.unbekannteZeitzone(id: id, zeitzone: zeitzone)
        }
        if durchgehend { return }
        guard !handelszeiten.isEmpty else { throw BoersenuhrFehler.keineHandelszeiten(id: id) }
        for zeit in handelszeiten {
            if zeit.tage.isEmpty {
                throw BoersenuhrFehler.ungueltigeHandelszeit(id: id, grund: "keine Tage angegeben")
            }
            if zeit.endeNachTagen < 0 || zeit.endeNachTagen > 6 {
                throw BoersenuhrFehler.ungueltigeHandelszeit(id: id, grund: "endeNachTagen muss 0 bis 6 sein")
            }
            if zeit.endeNachTagen == 0 && zeit.ende <= zeit.beginn {
                throw BoersenuhrFehler.ungueltigeHandelszeit(id: id, grund: "Ende \(zeit.ende) nicht nach Beginn \(zeit.beginn)")
            }
        }
    }

    /// Die Zeitzone der Börse. `pruefe()` stellt sicher, dass es sie gibt.
    public var timeZone: TimeZone { TimeZone(identifier: zeitzone)! }
}

/// Regelmäßige Handelszeit, zum Beispiel Montag bis Freitag 09:00 bis 17:30.
/// Sitzungen über Mitternacht: `endeNachTagen` sagt, wie viele Tage nach dem Beginn sie enden
/// (Forex: Beginn Sonntag 17:00, Ende am Folgetag 17:00, also 1).
public struct Handelszeit: Sendable, Hashable, Codable {
    /// Tage, an denen eine Sitzung beginnt.
    public var tage: [Wochentag]
    public var beginn: Uhrzeit
    public var ende: Uhrzeit
    public var endeNachTagen: Int

    public init(tage: [Wochentag], beginn: Uhrzeit, ende: Uhrzeit, endeNachTagen: Int = 0) {
        self.tage = tage
        self.beginn = beginn
        self.ende = ende
        self.endeNachTagen = endeNachTagen
    }

    private enum CodingKeys: String, CodingKey { case tage, beginn, ende, endeNachTagen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tage = try c.decode([Wochentag].self, forKey: .tage)
        beginn = try c.decode(Uhrzeit.self, forKey: .beginn)
        ende = try c.decode(Uhrzeit.self, forKey: .ende)
        endeNachTagen = try c.decodeIfPresent(Int.self, forKey: .endeNachTagen) ?? 0
    }
}

public struct Feiertag: Sendable, Hashable, Codable {
    public var datum: Kalendertag
    public var name: String

    public init(datum: Kalendertag, name: String) {
        self.datum = datum
        self.name = name
    }
}

public struct VerkuerzterTag: Sendable, Hashable, Codable {
    public var datum: Kalendertag
    /// Früherer Schluss in Ortszeit.
    public var ende: Uhrzeit
    public var name: String

    public init(datum: Kalendertag, ende: Uhrzeit, name: String) {
        self.datum = datum
        self.ende = ende
        self.name = name
    }
}

/// Woher die Angaben stammen.
public struct Quelle: Sendable, Hashable, Codable {
    public var titel: String
    public var url: String
    /// Tag des Abrufs, "JJJJ-MM-TT".
    public var abgerufen: Kalendertag

    public init(titel: String, url: String, abgerufen: Kalendertag) {
        self.titel = titel
        self.url = url
        self.abgerufen = abgerufen
    }
}
