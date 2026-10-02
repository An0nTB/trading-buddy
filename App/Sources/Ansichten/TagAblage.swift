import Foundation
import TradingCore

// Ablage der Tagesseite (P7). Die Speicherung in TradingStore kommt mit Migration v8 von AP9
// (Doc 11, Nachtrag 02.10.2026). Bis dahin arbeitet die Seite gegen dieses Protokoll; die
// flüchtige Ablage hält alles nur im Arbeitsspeicher und verhält sich sonst wie die Speicherung:
// eine Notiz je Tag, Notizen und verpasste Trades für alle Konten (Entscheidung 31 in Doc 11).

/// Was die Tagesseite lesen und schreiben muss. Namen wie in der Speicher-API von AP9 (Doc 11).
@MainActor
protocol TagAblage: AnyObject {
    /// `false`, solange Einträge beim Beenden verloren gehen.
    var dauerhaft: Bool { get }

    func tagesnotiz(_ tag: Journaltag) throws -> Tagesnotiz?
    /// Beide Tage einschließlich.
    func tagesnotizen(von: Journaltag, bis: Journaltag) throws -> [Tagesnotiz]
    /// Gibt die gespeicherte Fassung zurück, `nil`, wenn die Notiz leer war und entfernt wurde.
    func speichereTagesnotiz(_ notiz: Tagesnotiz, jetzt: Date) throws -> Tagesnotiz?

    /// `von <= zeit < bis`, nach Zeit sortiert.
    func verpassteTrades(von: Date, bis: Date) throws -> [VerpassterTrade]
    /// Legt an oder ersetzt über `id`.
    func speichereVerpasstenTrade(_ verpasst: VerpassterTrade) throws
    func loescheVerpasstenTrade(id: String) throws

    func bilder(tag: Journaltag) throws -> [Bildverweis]
    func speichereBild(_ bild: Bildverweis) throws
    func loescheBild(datei: String) throws
}

/// Ablage im Arbeitsspeicher, bis AP9 die Tabellen liefert. Regeln wie in Doc 11, Entscheidung 32:
/// `planErstellt` bleibt beim Ändern, ein geleerter Plan verliert den Zeitpunkt, ein neu geschriebener
/// Plan bekommt den neuen.
@MainActor
final class FluechtigeTagAblage: TagAblage {
    /// Eine Ablage für die ganze App, damit Einträge einen Seitenwechsel überstehen.
    static let gemeinsam = FluechtigeTagAblage()

    private var notizen: [Journaltag: Tagesnotiz] = [:]
    private var verpasst: [String: VerpassterTrade] = [:]
    private var bildliste: [Bildverweis] = []

    var dauerhaft: Bool { false }

    func tagesnotiz(_ tag: Journaltag) throws -> Tagesnotiz? { notizen[tag] }

    func tagesnotizen(von: Journaltag, bis: Journaltag) throws -> [Tagesnotiz] {
        notizen.values.filter { $0.tag >= von && $0.tag <= bis }.sorted { $0.tag < $1.tag }
    }

    func speichereTagesnotiz(_ notiz: Tagesnotiz, jetzt: Date) throws -> Tagesnotiz? {
        let alt = notizen[notiz.tag]
        var neu = notiz
        neu.plan = notiz.plan.trimmingCharacters(in: .whitespacesAndNewlines)
        neu.rueckblick = notiz.rueckblick.trimmingCharacters(in: .whitespacesAndNewlines)
        if let verfassung = neu.verfassung, !(1...5).contains(verfassung) { neu.verfassung = nil }
        if neu.plan.isEmpty && neu.rueckblick.isEmpty && neu.verfassung == nil {
            notizen[notiz.tag] = nil
            return nil
        }
        if neu.plan.isEmpty {
            neu.planErstellt = nil
        } else if let frueher = alt?.planErstellt, !(alt?.plan.isEmpty ?? true) {
            neu.planErstellt = frueher
        } else {
            neu.planErstellt = jetzt
        }
        neu.erstellt = alt?.erstellt ?? jetzt
        neu.geaendert = jetzt
        notizen[notiz.tag] = neu
        return neu
    }

    func verpassteTrades(von: Date, bis: Date) throws -> [VerpassterTrade] {
        verpasst.values.filter { $0.zeit >= von && $0.zeit < bis }.sorted { ($0.zeit, $0.id) < ($1.zeit, $1.id) }
    }

    func speichereVerpasstenTrade(_ eintrag: VerpassterTrade) throws {
        verpasst[eintrag.id] = eintrag
    }

    func loescheVerpasstenTrade(id: String) throws {
        verpasst[id] = nil
        bildliste.removeAll { $0.bezug == .verpassterTrade(id) }
    }

    func bilder(tag: Journaltag) throws -> [Bildverweis] {
        bildliste.filter { $0.bezug == .tag(tag) }.sorted { ($0.erstellt, $0.datei) < ($1.erstellt, $1.datei) }
    }

    func speichereBild(_ bild: Bildverweis) throws {
        guard Bildverweis.istGueltig(bild.datei) else { throw Bildfehler.ungueltigerPfad }
        bildliste.removeAll { $0.datei == bild.datei }
        bildliste.append(bild)
    }

    func loescheBild(datei: String) throws {
        bildliste.removeAll { $0.datei == datei }
    }
}

extension Journaltag {
    /// Der Tag `tage` Tage später (negativ: früher), über den Kalender der Zeitzone, damit
    /// Tage mit Zeitumstellung nicht verrutschen.
    func verschoben(um tage: Int, zeitzone: TimeZone) -> Journaltag {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = zeitzone
        let beginn = beginn(in: zeitzone)
        guard let ziel = kalender.date(byAdding: .day, value: tage, to: beginn) else { return self }
        return Journaltag(ziel, zeitzone: zeitzone)
    }

    /// Beginn dieses und Beginn des nächsten Tages, für Abfragen `von <= zeit < bis`.
    func spanne(in zeitzone: TimeZone) -> (von: Date, bis: Date) {
        (beginn(in: zeitzone), verschoben(um: 1, zeitzone: zeitzone).beginn(in: zeitzone))
    }
}
