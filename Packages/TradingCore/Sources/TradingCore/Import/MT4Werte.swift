import Foundation

/// Fehler beim Einlesen eines MetaTrader-Auszugs. Der Import bricht lieber ab,
/// als still eine Zeile zu verlieren: Bei Geld zählt jede Zeile.
public enum MT4ImportFehler: Error, Equatable, Sendable {
    /// Weder „Daily Confirmation“ noch „Monthly Statement“ im Titel.
    case keinMT4Auszug
    /// Zeile mit Ticket, deren Aufbau unbekannt ist (zum Beispiel Ein- oder Auszahlung).
    case unbekannteZeile(abschnitt: String, ticket: String, zellen: [String])
    case ungueltigeZahl(String)
    case ungueltigeZeit(String)
    case unbekannteAuftragsart(String)
    case fehlenderWert(String)
}

/// Umwandlung der Texte aus dem Auszug in Zahlen und Zeitpunkte.
enum MT4Werte {
    /// Geldbetrag oder Kurs. Akzeptiert Punkt als Dezimaltrenner und Leerzeichen
    /// als Tausendertrenner („10 000.00“), sonst nichts.
    static func zahl(_ text: String) throws -> Decimal {
        let roh = text.filter { !$0.isWhitespace }
        let erlaubt = roh.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }
        guard !roh.isEmpty, erlaubt, roh.filter({ $0 == "." }).count <= 1,
              let wert = Decimal(string: roh, locale: Locale(identifier: "en_US_POSIX"))
        else { throw MT4ImportFehler.ungueltigeZahl(text) }
        return wert
    }

    /// Stop oder Ziel: MetaTrader schreibt 0, wenn keiner gesetzt war.
    static func optionaleZahl(_ text: String) throws -> Decimal? {
        let wert = try zahl(text)
        return wert == 0 ? nil : wert
    }

    /// „2025.05.13 08:51:24“ in Serverzeit, Ergebnis als absoluter Zeitpunkt.
    static func zeit(_ text: String, zeitzone: TimeZone) throws -> Date {
        let teile = text.split(whereSeparator: { $0 == "." || $0 == " " || $0 == ":" }).map { Int($0) }
        guard teile.count == 6, teile.allSatisfy({ $0 != nil }) else {
            throw MT4ImportFehler.ungueltigeZeit(text)
        }
        let z = teile.map { $0! }
        return try datum(jahr: z[0], monat: z[1], tag: z[2], stunde: z[3], minute: z[4], sekunde: z[5],
                         zeitzone: zeitzone, text: text)
    }

    /// Kopfzeile „2025 May 14, 23:59“ (Monat englisch, kurz oder lang).
    static func berichtszeit(_ text: String, zeitzone: TimeZone) throws -> Date {
        let teile = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ":" })
        let monate = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard teile.count == 5,
              let jahr = Int(teile[0]),
              let monat = monate.firstIndex(of: teile[1].prefix(3).lowercased()),
              let tag = Int(teile[2]), let stunde = Int(teile[3]), let minute = Int(teile[4])
        else { throw MT4ImportFehler.ungueltigeZeit(text) }
        return try datum(jahr: jahr, monat: monat + 1, tag: tag, stunde: stunde, minute: minute, sekunde: 0,
                         zeitzone: zeitzone, text: text)
    }

    private static func datum(jahr: Int, monat: Int, tag: Int, stunde: Int, minute: Int, sekunde: Int,
                              zeitzone: TimeZone, text: String) throws -> Date {
        guard (1...12).contains(monat), (1...31).contains(tag), (0...23).contains(stunde),
              (0...59).contains(minute), (0...59).contains(sekunde)
        else { throw MT4ImportFehler.ungueltigeZeit(text) }
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let teile = DateComponents(year: jahr, month: monat, day: tag, hour: stunde, minute: minute, second: sekunde)
        guard let datum = kalender.date(from: teile),
              kalender.component(.day, from: datum) == tag
        else { throw MT4ImportFehler.ungueltigeZeit(text) }
        return datum
    }

    static func auftragsart(_ text: String) throws -> OrderType {
        guard let art = OrderType(rawValue: text.lowercased()) else {
            throw MT4ImportFehler.unbekannteAuftragsart(text)
        }
        return art
    }
}
