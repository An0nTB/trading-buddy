import Foundation
import TradingStore

/// Weg aus einer Journal-Datei, die sich beim Start nicht öffnen lässt (AP9 #225, Doc 11 Entscheidungen 46 bis 48).
/// Die alte Datei wird nie gelöscht, nur umbenannt; danach entsteht ein neues Journal, auf Wunsch aus der letzten
/// Sicherung. Pfad und Sicherungsordner kommen als Parameter, damit App-Tests mit einem temporären Ordner arbeiten.
enum Startwiederherstellung {
    /// Die jüngste Sicherung, die sich zurückspielen lässt, mit ihrer Prüfung.
    struct Angebot: Equatable, Sendable {
        var datei: URL
        var pruefung: Sicherungspruefung
    }

    /// Ergebnis: das neue Journal und wo die alte Datei jetzt liegt (`nil`, wenn es keine gab).
    struct Ergebnis {
        var journal: Journal
        var beiseite: URL?
    }

    /// Fehler, bei denen die App statt der Seiten den Weg aus der Datei anbietet. Bei fehlenden Rechten oder
    /// Datenträgerfehlern hilft Umbenennen nicht; dort bleibt es bei der Fehlermeldung.
    static func bietetAusweg(_ fehler: JournalFehler) -> Bool {
        switch fehler {
        case .beschaedigt, .ausNeuererVersion: true
        case .platteVoll, .nurLesbar, .keinZugriff, .datentraeger: false
        }
    }

    /// Sucht im Sicherungsordner die jüngste brauchbare Sicherung. Öffnet den Ordner über seinen Bookmark-Zugriff.
    static func angebot(in ordner: URL?) -> Angebot? {
        guard let ordner else { return nil }
        let zugriff = ordner.startAccessingSecurityScopedResource()
        defer { if zugriff { ordner.stopAccessingSecurityScopedResource() } }
        return Journal.letzteBrauchbareSicherung(in: ordner).map { Angebot(datei: $0.datei, pruefung: $0.pruefung) }
    }

    /// Legt die alte Datei beiseite und spielt die Sicherung in ein neues Journal unter `pfad` ein.
    static func ausSicherung(pfad: String, angebot: Angebot, ordner: URL?, jetzt: Date = Date()) throws -> Ergebnis {
        let zugriff = ordner?.startAccessingSecurityScopedResource() ?? false
        let dateiZugriff = angebot.datei.startAccessingSecurityScopedResource()
        defer {
            if zugriff { ordner?.stopAccessingSecurityScopedResource() }
            if dateiZugriff { angebot.datei.stopAccessingSecurityScopedResource() }
        }
        let (journal, beiseite) = try Journal.oeffneAusSicherung(pfad: pfad, sicherung: angebot.datei, jetzt: jetzt)
        return Ergebnis(journal: journal, beiseite: beiseite)
    }

    /// Legt die alte Datei beiseite und beginnt mit einem leeren Journal.
    static func neuBeginnen(pfad: String, jetzt: Date = Date()) throws -> Ergebnis {
        let beiseite = FileManager.default.fileExists(atPath: pfad) ? try Journal.legeBeiseite(pfad: pfad, jetzt: jetzt) : nil
        return Ergebnis(journal: try Journal(pfad: pfad), beiseite: beiseite)
    }
}
