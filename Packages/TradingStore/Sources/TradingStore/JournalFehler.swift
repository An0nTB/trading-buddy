import Foundation
import GRDB

/// Fehler der Journal-Datei selbst, unabhängig vom Inhalt: beschädigt, aus einer neueren App-Version,
/// Datenträger voll oder schreibgeschützt. Die Meldung (`errorDescription`) ist für die App gedacht.
/// Andere Datenbankfehler (etwa verletzte Schlüssel) bleiben `DatabaseError`.
public enum JournalFehler: Error, Equatable, Sendable {
    /// Kein Platz mehr auf dem Datenträger. Die laufende Änderung ist zurückgenommen.
    case platteVoll
    /// Datei oder Ordner ist schreibgeschützt. Lesen geht weiter, Ändern nicht.
    case nurLesbar
    /// Keine lesbare Journal-Datenbank oder die Prüfung (`quick_check`) schlägt fehl. Die Datei bleibt unverändert.
    case beschaedigt(String)
    /// Die Datei kennt Migrationen, die diese App-Version nicht kennt. Die Datei bleibt unverändert.
    case ausNeuererVersion([String])
    /// Die Datei lässt sich nicht öffnen (Ordner fehlt, keine Rechte, gesperrt).
    case keinZugriff(String)
    /// Lese- oder Schreibfehler des Datenträgers.
    case datentraeger(String)

    /// Übersetzt Fehler der Datei; `nil` für alle anderen Datenbankfehler.
    init?(_ fehler: DatabaseError) {
        let grund = fehler.message ?? "\(fehler.resultCode)"
        switch fehler.resultCode {
        case .SQLITE_FULL: self = .platteVoll
        case .SQLITE_READONLY: self = .nurLesbar
        case .SQLITE_CORRUPT, .SQLITE_NOTADB: self = .beschaedigt(grund)
        case .SQLITE_CANTOPEN, .SQLITE_PERM, .SQLITE_AUTH: self = .keinZugriff(grund)
        case .SQLITE_IOERR: self = .datentraeger(grund)
        default: return nil
        }
    }
}

extension JournalFehler: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .platteVoll:
            "Auf dem Datenträger ist kein Platz mehr. Die Änderung wurde nicht gespeichert."
        case .nurLesbar:
            "Das Journal ist schreibgeschützt. Die Änderung wurde nicht gespeichert."
        case .beschaedigt(let grund):
            "Die Journal-Datei ist beschädigt (\(grund)). Sie bleibt unverändert; eine Sicherung lässt sich zurückspielen."
        case .ausNeuererVersion:
            "Das Journal stammt aus einer neueren Version der App. Mit dieser Version lässt es sich nicht öffnen."
        case .keinZugriff(let grund):
            "Die Journal-Datei lässt sich nicht öffnen (\(grund))."
        case .datentraeger(let grund):
            "Lese- oder Schreibfehler des Datenträgers (\(grund))."
        }
    }
}

// Weg aus einer Journal-Datei, die sich nicht öffnen lässt (Doc 11, Entscheidungen 46 bis 48): Die Datei wird
// nie gelöscht, sondern umbenannt; danach entsteht ein neues Journal, auf Wunsch aus der letzten Sicherung.
extension Journal {
    /// Führt `arbeit` aus und meldet Fehler der Datei als `JournalFehler`.
    static func gemeldet<T>(_ arbeit: () throws -> T) throws -> T {
        do {
            return try arbeit()
        } catch let fehler as DatabaseError {
            if let datei = JournalFehler(fehler) { throw datei }
            throw fehler
        }
    }

    /// Benennt die Journal-Datei samt Begleitdateien (`-journal`, `-wal`, `-shm`) in
    /// `<Name>.beschaedigt-JJJJ-MM-TT-HHMMSS` um und gibt den neuen Ort der Datei zurück. Nichts wird gelöscht
    /// oder überschrieben. Nur aufrufen, solange kein `Journal` diese Datei offen hat.
    @discardableResult
    public static func legeBeiseite(pfad: String, jetzt: Date = Date(), zeitzone: TimeZone = .current) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pfad) else {
            throw SpeicherFehler.ungueltigerWert("\((pfad as NSString).lastPathComponent) gibt es nicht")
        }
        let stempel = String(sicherungsname(jetzt, zeitzone: zeitzone).dropFirst(sicherungsPraefix.count)
            .dropLast(sicherungsEndung.count))
        let ziel = pfad + ".beschaedigt-" + stempel
        let endungen = ["", "-journal", "-wal", "-shm"].filter { fm.fileExists(atPath: pfad + $0) }
        if let belegt = endungen.first(where: { fm.fileExists(atPath: ziel + $0) }) {
            throw SpeicherFehler.ungueltigerWert("\((ziel as NSString).lastPathComponent + belegt) gibt es schon")
        }
        for endung in endungen {
            do {
                try fm.moveItem(atPath: pfad + endung, toPath: ziel + endung)
            } catch {
                throw JournalFehler.keinZugriff("Umbenennen fehlgeschlagen: \(error.localizedDescription)")
            }
        }
        return URL(fileURLWithPath: ziel)
    }

    /// Jüngste Sicherung von `sichereInOrdner` in diesem Ordner, die sich zurückspielen lässt, mit ihrer Prüfung.
    public static func letzteBrauchbareSicherung(in ordner: URL) -> (datei: URL, pruefung: Sicherungspruefung)? {
        for datei in (try? sicherungen(in: ordner)) ?? [] {
            let pruefung = pruefeSicherung(datei)
            if pruefung.laesstSichWiederherstellen { return (datei, pruefung) }
        }
        return nil
    }

    /// Neues Journal unter `pfad` aus einer Sicherung. Prüft zuerst die Sicherung; erst wenn sie passt, wird
    /// eine vorhandene Datei unter `pfad` beiseitegelegt (`legeBeiseite`, nie gelöscht).
    public static func oeffneAusSicherung(pfad: String, sicherung: URL, jetzt: Date = Date(),
                                          zeitzone: TimeZone = .current) throws -> (journal: Journal, beiseite: URL?) {
        let pruefung = pruefeSicherung(sicherung)
        guard pruefung.laesstSichWiederherstellen else {
            throw SpeicherFehler.ungueltigerWert(pruefung.zustand == .neuer
                ? "Sicherung stammt aus einer neueren App-Version" : "Sicherung ist beschädigt: \(pruefung.hinweis)")
        }
        let beiseite = FileManager.default.fileExists(atPath: pfad)
            ? try legeBeiseite(pfad: pfad, jetzt: jetzt, zeitzone: zeitzone) : nil
        let journal = try Journal(pfad: pfad)
        try journal.stelleWiederHer(aus: sicherung)
        return (journal, beiseite)
    }
}
