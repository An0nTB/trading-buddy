import Foundation
import GRDB

// Geprüfte Kopie der Journal-Datei vor einer Migration (App-Update beim Tester, Doc 11, Entscheidung 51).
// Ohne neuen JournalFehler-Fall: Die App unterscheidet die Fälle vollständig (`switch`), ein neuer Fall bräche
// ihren Build. Eine misslungene Kopie kommt als Datei- oder Datenträgerfehler.

/// Wo und mit welchem Zeitstempel `Journal(pfad:)` vor einer Migration kopiert.
struct KopieVorMigration {
    var pfad: String
    var jetzt: Date
    var zeitzone: TimeZone
}

extension Journal {
    /// So viele Kopien vor einer Migration bleiben neben der Journal-Datei liegen.
    static let kopienVorMigrationBehalten = 3

    /// Name der Kopie: `<Name ohne .sqlite>.vor-<vN>-JJJJ-MM-TT-HHMMSS.sqlite`, `vN` aus der ersten fehlenden
    /// Migration („v10 …“ ergibt `v10`).
    static func kopiename(_ pfad: String, vor migration: String, jetzt: Date, zeitzone: TimeZone) -> String {
        let zeit = sicherungsname(jetzt, zeitzone: zeitzone).dropFirst(sicherungsPraefix.count)
            .dropLast(sicherungsEndung.count)
        let stand = migration.split(separator: " ").first.map { $0.filter { $0.isLetter || $0.isNumber } } ?? ""
        let vor = stand.isEmpty ? "" : "\(stand)-"
        return "\(kopiebasis(pfad))\(vor)\(zeit)\(sicherungsEndung)"
    }

    /// Gemeinsamer Anfang aller Kopien zu dieser Datei, etwa `journal.vor-`.
    static func kopiebasis(_ pfad: String) -> String {
        let name = (pfad as NSString).lastPathComponent
        let ohne = name.hasSuffix(sicherungsEndung) ? String(name.dropLast(sicherungsEndung.count)) : name
        return ohne + ".vor-"
    }

    /// Die letzten 17 Zeichen vor `.sqlite`: `JJJJ-MM-TT-HHMMSS`.
    private static func stempel(_ name: String) -> Substring {
        name.dropLast(sicherungsEndung.count).suffix(17)
    }

    /// Kopien vor einer Migration neben `pfad`, neueste zuerst (nach dem Zeitstempel am Ende des Namens).
    public static func kopienVorMigration(pfad: String) -> [URL] {
        let ordner = URL(fileURLWithPath: pfad).deletingLastPathComponent()
        let basis = kopiebasis(pfad)
        let namen = (try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []
        return namen
            .filter { name in
                guard name.hasPrefix(basis), name.hasSuffix(sicherungsEndung) else { return false }
                let teil = stempel(name)
                return teil.count == 17 && teil.allSatisfy { $0.isNumber || $0 == "-" }
            }
            .sorted { stempel($0) > stempel($1) }
            .map { ordner.appendingPathComponent($0) }
    }

    /// Legt die Kopie an, prüft sie (Stand älter als diese App-Version) und räumt ältere Kopien auf.
    /// Jeder Fehler kommt als `JournalFehler`; die Journal-Datei bleibt dann unverändert.
    func sichereVorMigration(_ kopie: KopieVorMigration, vor migration: String) throws {
        let ziel = URL(fileURLWithPath: kopie.pfad).deletingLastPathComponent()
            .appendingPathComponent(Self.kopiename(kopie.pfad, vor: migration, jetzt: kopie.jetzt,
                                                   zeitzone: kopie.zeitzone))
        do {
            try kopiere(nach: ziel, erwartet: .aelter)
        } catch let fehler as JournalFehler {
            throw fehler
        } catch SpeicherFehler.ungueltigerWert(let grund) {
            throw JournalFehler.datentraeger("Sicherung vor der Aktualisierung: \(grund)")
        } catch {
            throw JournalFehler.datentraeger("Sicherung vor der Aktualisierung: \(error.localizedDescription)")
        }
        for alt in Self.kopienVorMigration(pfad: kopie.pfad).dropFirst(Self.kopienVorMigrationBehalten) {
            try? FileManager.default.removeItem(at: alt)
        }
    }
}
