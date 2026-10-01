import Foundation

/// Fehler beim Einlesen einer CSV-Datei. Wie beim MT4-Import gilt: lieber abbrechen
/// als still eine Zeile verlieren.
public enum CSVImportFehler: Error, Equatable, Sendable {
    /// Kopfzeile passt zu keinem bekannten Broker-Format.
    case unbekanntesFormat(kopf: [String])
    case fehlendeSpalte(String)
    case ungueltigeZahl(zeile: Int, text: String)
    case ungueltigeZeit(zeile: Int, text: String)
    /// Vorgangsart, deren Bedeutung nicht belegt ist.
    case unbekannteArt(zeile: Int, art: String)
    /// Verkauf ohne passenden Bestand aus früheren Käufen.
    case verkaufOhneBestand(kennung: String, id: String)
}

/// CSV nach RFC 4180: Felder in Anführungszeichen dürfen Trennzeichen,
/// Zeilenumbrüche und verdoppelte Anführungszeichen enthalten.
/// Spalten werden über den Namen im Kopf gelesen, nie über die Position (Regel 2).
public struct CSVTabelle: Sendable {
    public var kopf: [String]
    public var zeilen: [[String]]

    public init(text: String) {
        var rest = Substring(text)
        if rest.hasPrefix("\u{FEFF}") { rest = rest.dropFirst() }
        let ersteZeile = rest.prefix { !$0.isNewline }
        let trenner: Character = ersteZeile.filter { $0 == ";" }.count > ersteZeile.filter { $0 == "," }.count
            ? ";" : ","
        let alle = Self.zerlege(rest, trenner: trenner).filter { !($0.count == 1 && $0[0].isEmpty) }
        kopf = alle.first ?? []
        zeilen = Array(alle.dropFirst())
    }

    /// Index je Spaltenname; fehlende Pflichtspalten brechen ab.
    public func spalten(_ namen: [String]) throws -> [String: Int] {
        var index: [String: Int] = [:]
        for name in namen {
            guard let i = kopf.firstIndex(of: name) else { throw CSVImportFehler.fehlendeSpalte(name) }
            index[name] = i
        }
        return index
    }

    private static func zerlege(_ text: Substring, trenner: Character) -> [[String]] {
        var zeilen: [[String]] = []
        var zeile: [String] = []
        var feld = ""
        var inAnfuehrung = false
        var zeichen = text.makeIterator()
        var vorschau: Character? = zeichen.next()
        while let c = vorschau {
            vorschau = zeichen.next()
            if inAnfuehrung {
                if c == "\"" {
                    if vorschau == "\"" { feld.append("\""); vorschau = zeichen.next() } else { inAnfuehrung = false }
                } else {
                    feld.append(c)
                }
            } else if c == "\"" {
                inAnfuehrung = true
            } else if c == trenner {
                zeile.append(feld)
                feld = ""
            } else if c.isNewline {
                zeile.append(feld)
                zeilen.append(zeile)
                zeile = []
                feld = ""
            } else {
                feld.append(c)
            }
        }
        if !feld.isEmpty || !zeile.isEmpty {
            zeile.append(feld)
            zeilen.append(zeile)
        }
        return zeilen
    }
}

/// Zahlen und Zeiten aus CSV-Feldern.
enum CSVWerte {
    enum Zahlformat { case punkt, komma }

    /// Leeres Feld zählt als 0 (Trade Republic lässt Gebühr und Steuer leer, wenn keine anfällt).
    static func zahl(_ text: String, _ format: Zahlformat, zeile: Int) throws -> Decimal {
        let roh = text.trimmingCharacters(in: .whitespaces)
        if roh.isEmpty { return 0 }
        let normal = format == .komma
            ? roh.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            : roh
        // Minus nur vorn, höchstens ein Dezimalpunkt: „1-2“ oder „1.2.3“ sind keine Zahlen.
        let ziffern = normal.hasPrefix("-") ? normal.dropFirst() : Substring(normal)
        let erlaubt = !ziffern.isEmpty && ziffern.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard erlaubt, ziffern.filter({ $0 == "." }).count <= 1,
              let wert = Decimal(string: normal, locale: Locale(identifier: "en_US_POSIX"))
        else { throw CSVImportFehler.ungueltigeZahl(zeile: zeile, text: text) }
        return wert
    }

    /// „2026-03-02“ und „10:01:15“ (Sekundenbruchteile werden ignoriert) in der Zeitzone der Quelle.
    static func zeit(datum: String, uhrzeit: String, zeitzone: TimeZone, zeile: Int) throws -> Date {
        let d = datum.split(separator: "-").map { Int($0) }
        let u = uhrzeit.prefix(8).split(separator: ":").map { Int($0) }
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        guard d.count == 3, u.count == 3, !d.contains(nil), !u.contains(nil),
              let zeit = kalender.date(from: DateComponents(year: d[0], month: d[1], day: d[2],
                                                            hour: u[0], minute: u[1], second: u[2]))
        else { throw CSVImportFehler.ungueltigeZeit(zeile: zeile, text: "\(datum) \(uhrzeit)") }
        return zeit
    }
}
