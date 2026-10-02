import Foundation
import GRDB

/// Ergebnis der Prüfung einer Sicherungsdatei (oder der laufenden Datenbank nach dem Wiederherstellen).
public struct Sicherungspruefung: Sendable, Equatable {
    public enum Zustand: String, Sendable, Equatable {
        /// Gleicher Aufbau wie diese App-Version.
        case aktuell
        /// Älterer Aufbau; beim Wiederherstellen laufen die fehlenden Migrationen nach.
        case aelter
        /// Aus einer neueren App-Version; diese Version kann sie nicht wiederherstellen.
        case neuer
        /// Keine lesbare Journal-Datenbank oder die Integritätsprüfung schlägt fehl.
        case beschaedigt
    }

    public var zustand: Zustand
    /// Kurzer Grund bei `neuer` und `beschaedigt`, sonst leer.
    public var hinweis: String
    /// Migrationen, die in der Datei gelaufen sind (in der Reihenfolge dieser App, unbekannte am Ende).
    public var migrationen: [String]
    /// Migrationen dieser App, die in der Datei noch fehlen.
    public var fehlendeMigrationen: [String]
    /// Migrationen in der Datei, die diese App nicht kennt.
    public var unbekannteMigrationen: [String]
    public var konten: Int
    public var ausfuehrungen: Int
    public var geschlossenePositionen: Int
    /// Zeitpunkt des letzten Imports in der Datei, falls es einen gibt.
    public var letzterImport: Date?

    /// `aktuell` und `aelter` lassen sich wiederherstellen.
    public var laesstSichWiederherstellen: Bool { zustand == .aktuell || zustand == .aelter }

    static func beschaedigt(_ grund: String) -> Sicherungspruefung {
        Sicherungspruefung(zustand: .beschaedigt, hinweis: grund, migrationen: [], fehlendeMigrationen: [],
                           unbekannteMigrationen: [], konten: 0, ausfuehrungen: 0, geschlossenePositionen: 0,
                           letzterImport: nil)
    }
}

// Datensicherung (Doc 46): konsistente Kopie im laufenden Betrieb über die SQLite-Backup-Schnittstelle,
// Prüfung einer Kopie, Wiederherstellen in die offene Datenbank samt Migration älterer Stände.
// Zeitplan, Ordnerwahl und Knöpfe baut die App. Bilder liegen nicht in der Datenbank und sind nicht enthalten.
extension Journal {
    /// Dateiname-Anfang der Sicherungen von `sichereInOrdner`.
    public static let sicherungsPraefix = "Journal-Sicherung-"
    static let sicherungsEndung = ".sqlite"

    /// Schreibt eine konsistente Kopie der Datenbank nach `ziel` und prüft sie. Eine vorhandene Datei an
    /// `ziel` wird erst ersetzt, wenn die Kopie vollständig ist. Schreiben in die Datenbank während der
    /// Sicherung ist erlaubt; ob es in der Kopie landet, ist offen.
    @discardableResult
    public func sichere(nach ziel: URL) throws -> Sicherungspruefung {
        let fm = FileManager.default
        let teil = ziel.deletingLastPathComponent()
            .appendingPathComponent(".\(ziel.lastPathComponent).\(UUID().uuidString).teil")
        defer { try? fm.removeItem(at: teil) }
        let kopie = try DatabaseQueue(path: teil.path)
        try db.backup(to: kopie)
        try kopie.close()
        let pruefung = Self.pruefeSicherung(teil)
        guard pruefung.zustand == .aktuell else {
            throw SpeicherFehler.ungueltigerWert("Sicherung fehlerhaft: \(pruefung.hinweis)")
        }
        // rename ersetzt eine vorhandene Datei in einem Schritt (gleicher Ordner, POSIX).
        guard rename(teil.path, ziel.path) == 0 else {
            throw SpeicherFehler.ungueltigerWert("Sicherung nicht abgelegt (Fehler \(errno))")
        }
        return pruefung
    }

    /// Sichert in den Ordner unter `Journal-Sicherung-JJJJ-MM-TT-HHMMSS.sqlite` (Ortszeit `zeitzone`) und
    /// entfernt danach die ältesten Sicherungen dieses Musters, bis höchstens `behalte` übrig sind. Andere
    /// Dateien im Ordner bleiben unberührt. Gibt die neue Datei zurück.
    @discardableResult
    public func sichereInOrdner(_ ordner: URL, jetzt: Date = Date(), zeitzone: TimeZone = .current,
                                behalte: Int = 14) throws -> URL {
        guard behalte >= 1 else { throw SpeicherFehler.ungueltigerWert("Mindestens eine Sicherung behalten") }
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let ziel = ordner.appendingPathComponent(Self.sicherungsname(jetzt, zeitzone: zeitzone))
        try sichere(nach: ziel)
        for alt in try Self.sicherungen(in: ordner).dropFirst(behalte) {
            try FileManager.default.removeItem(at: alt)
        }
        return ziel
    }

    /// Sicherungen von `sichereInOrdner` in diesem Ordner, neueste zuerst. Fehlt der Ordner: leer.
    public static func sicherungen(in ordner: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: ordner.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)
            .filter { istSicherungsname($0.lastPathComponent) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Prüft eine Sicherungsdatei, ohne sie zu ändern: SQLite-Integrität, Fremdschlüssel, Migrationsstand
    /// gegenüber dieser App-Version und ein paar Zahlen für die Anzeige.
    public static func pruefeSicherung(_ datei: URL) -> Sicherungspruefung {
        guard FileManager.default.fileExists(atPath: datei.path) else { return .beschaedigt("Datei fehlt") }
        var konfiguration = Configuration()
        konfiguration.readonly = true
        do {
            let quelle = try DatabaseQueue(path: datei.path, configuration: konfiguration)
            defer { try? quelle.close() }
            return try quelle.read { db in try pruefe(db) }
        } catch let fehler as DatabaseError {
            return .beschaedigt(fehler.message ?? "\(fehler.resultCode)")
        } catch {
            return .beschaedigt("\(error)")
        }
    }

    /// Ersetzt den gesamten Inhalt dieser Datenbank durch die Sicherung und bringt ihn auf den Aufbau dieser
    /// App-Version. Abgelehnt werden beschädigte Sicherungen und solche aus einer neueren App-Version; die
    /// Datenbank bleibt dann unverändert. Gibt die Prüfung des Ergebnisses zurück.
    ///
    /// Vorher sichern ist Sache der App (`sichereInOrdner`), damit sich der Schritt zurücknehmen lässt.
    @discardableResult
    public func stelleWiederHer(aus datei: URL) throws -> Sicherungspruefung {
        let vorher = Self.pruefeSicherung(datei)
        guard vorher.laesstSichWiederherstellen else {
            throw SpeicherFehler.ungueltigerWert(vorher.zustand == .neuer
                ? "Sicherung stammt aus einer neueren App-Version" : "Sicherung ist beschädigt: \(vorher.hinweis)")
        }
        var konfiguration = Configuration()
        konfiguration.readonly = true
        let quelle = try DatabaseQueue(path: datei.path, configuration: konfiguration)
        try quelle.backup(to: db)
        try quelle.close()
        try Schema.migrator.migrate(db)
        return try db.read { try Self.pruefe($0) }
    }

    static func pruefe(_ db: Database) throws -> Sicherungspruefung {
        let integritaet = try String.fetchAll(db, sql: "PRAGMA integrity_check")
        guard integritaet == ["ok"] else {
            return .beschaedigt("Integritätsprüfung: \(integritaet.prefix(3).joined(separator: "; "))")
        }
        guard try db.tableExists("grdb_migrations"), try db.tableExists("konto") else {
            return .beschaedigt("Keine Journal-Datenbank")
        }
        if let verstoss = try Row.fetchOne(db, sql: "PRAGMA foreign_key_check") {
            return .beschaedigt("Fremdschlüssel verletzt in \(verstoss[0] as String? ?? "?")")
        }
        let gelaufen = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        let bekannt = Schema.migrator.migrations
        let unbekannt = gelaufen.filter { !bekannt.contains($0) }
        let fehlend = bekannt.filter { !gelaufen.contains($0) }
        func anzahl(_ tabelle: String) throws -> Int {
            try db.tableExists(tabelle) ? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tabelle)") ?? 0 : 0
        }
        let letzter = try db.tableExists("importlauf")
            ? Date.fetchOne(db, sql: "SELECT MAX(importiertAm) FROM importlauf") : nil
        let zustand: Sicherungspruefung.Zustand = !unbekannt.isEmpty ? .neuer : fehlend.isEmpty ? .aktuell : .aelter
        return Sicherungspruefung(
            zustand: zustand,
            hinweis: unbekannt.isEmpty ? "" : "Unbekannte Migrationen: \(unbekannt.joined(separator: ", "))",
            migrationen: bekannt.filter { gelaufen.contains($0) } + unbekannt,
            fehlendeMigrationen: fehlend, unbekannteMigrationen: unbekannt,
            konten: try anzahl("konto"), ausfuehrungen: try anzahl("ausfuehrung"),
            geschlossenePositionen: try anzahl("geschlossenePosition"), letzterImport: letzter)
    }

    static func sicherungsname(_ zeit: Date, zeitzone: TimeZone) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = zeitzone
        format.dateFormat = "yyyy-MM-dd-HHmmss"
        return sicherungsPraefix + format.string(from: zeit) + sicherungsEndung
    }

    static func istSicherungsname(_ name: String) -> Bool {
        guard name.hasPrefix(sicherungsPraefix), name.hasSuffix(sicherungsEndung) else { return false }
        let mitte = name.dropFirst(sicherungsPraefix.count).dropLast(sicherungsEndung.count)
        return mitte.count == 17 && mitte.allSatisfy { $0.isNumber || $0 == "-" }
    }
}
