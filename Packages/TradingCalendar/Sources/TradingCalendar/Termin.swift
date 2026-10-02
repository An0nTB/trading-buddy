import Foundation

/// Art eines Termins; eine Jahresdatei sagt in `vollstaendig`, welche Arten sie ganz enthält.
public enum Terminart: String, Sendable, Hashable, Codable, CaseIterable {
    case zinsentscheid
    case arbeitsmarkt
    case inflation
    /// Bankfeiertag einer Währung, ganztägig; dünner Handel, viele Broker schließen am 25.12. und 01.01.
    case feiertag
}

/// Ein Wirtschaftstermin in Ortszeit seiner Zeitzone, in JSON etwa
/// `{"id": "fed-2026-10-28", "art": "zinsentscheid", "institution": "fed", "titel": "Fed-Zinsentscheid",
///   "datum": "2026-10-28", "uhrzeit": "14:00", "zeitzone": "America/New_York", "waehrungen": ["USD"]}`.
/// Ohne `uhrzeit` gilt der Termin den ganzen Tag in seiner Zeitzone (BoJ nennt keine feste Uhrzeit).
public struct Termin: Sendable, Hashable, Identifiable {
    public let id: String
    public let art: Terminart
    /// Kürzel der Quelle: fed, ezb, boe, boj, snb, bls; bei Feiertagen die Zentralbank der Währung.
    public let institution: String
    public let titel: String
    /// Beginn; bei Terminen mit Uhrzeit zugleich das Ende.
    public let beginn: Date
    /// Bei ganztägigen Terminen der Beginn des Folgetags in der Zeitzone (ausschließlich).
    public let ende: Date
    public let ganztaegig: Bool
    public let zeitzone: TimeZone
    /// Betroffene Währungen nach ISO 4217, etwa ["USD"].
    public let waehrungen: Set<String>
    /// Termin nur aus Sekundärquelle oder noch nicht bestätigt.
    public let vorlaeufig: Bool
    public let hinweis: String?

    /// Liegt der Termin ganz oder teilweise in [von, bis]?
    public func liegt(zwischen von: Date, und bis: Date) -> Bool {
        ganztaegig ? beginn <= bis && von < ende : von <= beginn && beginn <= bis
    }
}

/// Fehler beim Lesen einer Jahresdatei.
public enum TerminkalenderFehler: Error, Equatable {
    case mitgelieferteDatenFehlen
    case unbekanntesFormat(Int)
    case ungueltigesDatum(id: String, text: String)
    case ungueltigeUhrzeit(id: String, text: String)
    case unbekannteZeitzone(id: String, text: String)
    case falschesJahr(id: String, jahr: Int)
    case doppelteID(String)
}

/// Eine Jahresdatei wie `Termine/termine_2026.json`.
public struct Jahresdatei: Sendable {
    public let jahr: Int
    public let stand: String
    /// Arten, die für dieses Jahr vollständig erfasst sind.
    public let vollstaendig: Set<Terminart>
    public let quellen: [String]
    public let hinweise: [String]
    public let termine: [Termin]

    public static func lade(json: Data) throws -> Jahresdatei {
        let roh = try JSONDecoder().decode(Roh.self, from: json)
        guard roh.format == 1 else { throw TerminkalenderFehler.unbekanntesFormat(roh.format) }
        var ids: Set<String> = []
        var termine: [Termin] = []
        for t in roh.termine {
            guard ids.insert(t.id).inserted else { throw TerminkalenderFehler.doppelteID(t.id) }
            let termin = try t.termin()
            guard t.datum.hasPrefix("\(roh.jahr)-") else { throw TerminkalenderFehler.falschesJahr(id: t.id, jahr: roh.jahr) }
            termine.append(termin)
        }
        return Jahresdatei(jahr: roh.jahr, stand: roh.stand, vollstaendig: Set(roh.vollstaendig),
                           quellen: roh.quellen ?? [], hinweise: roh.hinweise ?? [], termine: termine)
    }

    struct Roh: Decodable {
        let format: Int
        let jahr: Int
        let stand: String
        let vollstaendig: [Terminart]
        let quellen: [String]?
        let hinweise: [String]?
        let termine: [RohTermin]
    }

    struct RohTermin: Decodable {
        let id: String
        let art: Terminart
        let institution: String
        let titel: String
        let datum: String
        let uhrzeit: String?
        let zeitzone: String
        let waehrungen: [String]
        let vorlaeufig: Bool?
        let hinweis: String?

        func termin() throws -> Termin {
            guard let zone = TimeZone(identifier: zeitzone) else {
                throw TerminkalenderFehler.unbekannteZeitzone(id: id, text: zeitzone)
            }
            let teile = datum.split(separator: "-", omittingEmptySubsequences: false)
            guard teile.count == 3, teile[0].count == 4, teile[1].count == 2, teile[2].count == 2,
                  let j = Int(teile[0]), let m = Int(teile[1]), let t = Int(teile[2])
            else { throw TerminkalenderFehler.ungueltigesDatum(id: id, text: datum) }
            var stunde = 0
            var minute = 0
            if let uhrzeit {
                let hm = uhrzeit.split(separator: ":", omittingEmptySubsequences: false)
                guard hm.count == 2, hm[0].count == 2, hm[1].count == 2,
                      let h = Int(hm[0]), let mi = Int(hm[1]), (0...23).contains(h), (0...59).contains(mi)
                else { throw TerminkalenderFehler.ungueltigeUhrzeit(id: id, text: uhrzeit) }
                stunde = h
                minute = mi
            }
            var kalender = Calendar(identifier: .gregorian)
            kalender.timeZone = zone
            // Rückrechnung schließt Tage wie 2026-02-30 aus.
            guard let beginn = kalender.date(from: DateComponents(year: j, month: m, day: t, hour: stunde, minute: minute)),
                  kalender.component(.year, from: beginn) == j, kalender.component(.month, from: beginn) == m,
                  kalender.component(.day, from: beginn) == t,
                  let folgetag = kalender.date(byAdding: .day, value: 1, to: kalender.startOfDay(for: beginn))
            else { throw TerminkalenderFehler.ungueltigesDatum(id: id, text: datum) }
            return Termin(id: id, art: art, institution: institution, titel: titel,
                          beginn: beginn, ende: uhrzeit == nil ? folgetag : beginn, ganztaegig: uhrzeit == nil,
                          zeitzone: zone, waehrungen: Set(waehrungen.map { $0.uppercased() }),
                          vorlaeufig: vorlaeufig ?? false, hinweis: hinweis)
        }
    }
}
