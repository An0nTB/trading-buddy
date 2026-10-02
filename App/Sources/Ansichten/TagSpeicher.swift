import Foundation
import TradingCore
import TradingStore

/// Ablage der Tagesseite im Journal (Migration v8, AP9 #69, Doc 11 Nachtrag v8). Reicht die Aufrufe
/// durch und übersetzt `SpeicherFehler` in Klartext, weil er keine eigene Beschreibung mitbringt.
@MainActor
final class JournalTagAblage: TagAblage {
    private let journal: Journal

    init(_ journal: Journal) {
        self.journal = journal
    }

    var dauerhaft: Bool { true }

    func tagesnotiz(_ tag: Journaltag) throws -> Tagesnotiz? {
        try klartext { try journal.tagesnotiz(tag) }
    }

    func tagesnotizen(von: Journaltag, bis: Journaltag) throws -> [Tagesnotiz] {
        try klartext { try journal.tagesnotizen(von: von, bis: bis) }
    }

    func speichereTagesnotiz(_ notiz: Tagesnotiz, jetzt: Date) throws -> Tagesnotiz? {
        try klartext { try journal.speichereTagesnotiz(notiz, jetzt: jetzt) }
    }

    func verpassteTrades(von: Date, bis: Date) throws -> [VerpassterTrade] {
        try klartext { try journal.verpassteTrades(von: von, bis: bis) }
    }

    func speichereVerpasstenTrade(_ verpasst: VerpassterTrade) throws {
        try klartext { try journal.speichereVerpasstenTrade(verpasst) }
    }

    func loescheVerpasstenTrade(id: String) throws {
        // Die Speicherung entfernt die Verweise mit; die Dateien dazu räumt die App weg.
        let dateien = (try? journal.bilder(verpassterTrade: id).map(\.datei)) ?? []
        try klartext { try journal.loescheVerpasstenTrade(id: id) }
        dateien.forEach(Bilderordner.loesche)
    }

    func bilder(tag: Journaltag) throws -> [Bildverweis] {
        try klartext { try journal.bilder(tag: tag) }
    }

    func speichereBild(_ bild: Bildverweis) throws {
        try klartext { try journal.speichereBild(bild) }
    }

    func loescheBild(datei: String) throws {
        try klartext { try journal.loescheBild(datei: datei) }
    }

    private func klartext<T>(_ aufruf: () throws -> T) throws -> T {
        do {
            return try aufruf()
        } catch let fehler as SpeicherFehler {
            throw TagSpeicherFehler(fehler)
        }
    }
}

/// `SpeicherFehler` als Text für die Fehlermeldung der Tagesseite.
struct TagSpeicherFehler: LocalizedError {
    let fehler: SpeicherFehler

    init(_ fehler: SpeicherFehler) {
        self.fehler = fehler
    }

    var errorDescription: String? {
        switch fehler {
        case .ungueltigerWert(let grund):
            grund
        case .unbekannterWert(let wert):
            String(localized: "In der Datenbank steht ein unbekannter Wert: \(wert)")
        default:
            String(localized: "Speichern fehlgeschlagen.")
        }
    }
}
