import Foundation
import TradingCore

/// Bilderordner der App: `Application Support/Trading Buddy/Bilder`, in der Sandbox im Container.
/// Screenshots werden hierher kopiert; Speicher und Export kennen nur den relativen Pfad
/// (`Bildverweis`, Doc 24). Unterordner je Monat, Dateiname zufällig, damit nichts überschrieben wird.
enum Bilderordner {
    static func ordner() throws -> URL {
        let ordner = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trading Buddy", isDirectory: true)
            .appendingPathComponent("Bilder", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner
    }

    /// Volle Adresse eines Verweises; `nil`, wenn der Pfad ungültig ist oder aus dem Ordner führt.
    static func url(fuer datei: String) -> URL? {
        guard Bildverweis.istGueltig(datei), let ordner = try? ordner() else { return nil }
        let ziel = ordner.appendingPathComponent(datei).standardizedFileURL
        let basis = ordner.standardizedFileURL.path + "/"
        return ziel.path.hasPrefix(basis) ? ziel : nil
    }

    /// Kopiert ein Bild in den Ordner und gibt den relativen Pfad zurück, z. B. „2026-10/3F2A….png“.
    /// Die Quelle bleibt unverändert; Bilder aus „Datei wählen“ brauchen den Zugriff auf die Quelle.
    static func uebernimm(_ quelle: URL, jetzt: Date = Date(), zeitzone: TimeZone = .current) throws -> String {
        let endung = quelle.pathExtension.lowercased()
        guard Bildverweis.endungen.contains(endung) else { throw Bildfehler.keinBild(quelle.lastPathComponent) }
        let zugriff = quelle.startAccessingSecurityScopedResource()
        defer { if zugriff { quelle.stopAccessingSecurityScopedResource() } }

        let datei = relativerPfad(endung: endung, jetzt: jetzt, zeitzone: zeitzone)
        guard let ziel = url(fuer: datei) else { throw Bildfehler.ungueltigerPfad }
        do {
            try FileManager.default.createDirectory(at: ziel.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: quelle, to: ziel)
        } catch {
            throw Bildfehler.kopieren(quelle.lastPathComponent)
        }
        return datei
    }

    /// Entfernt die Datei; fehlt sie schon, ist das kein Fehler.
    static func loesche(_ datei: String) {
        guard let url = url(fuer: datei) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func relativerPfad(endung: String, jetzt: Date, zeitzone: TimeZone) -> String {
        let tag = Journaltag(jetzt, zeitzone: zeitzone).description
        return "\(tag.prefix(7))/\(UUID().uuidString).\(endung)"
    }
}

enum Bildfehler: LocalizedError {
    case keinBild(String)
    case kopieren(String)
    case ungueltigerPfad

    var errorDescription: String? {
        switch self {
        case .keinBild(let name):
            String(localized: "„\(name)“ ist kein unterstütztes Bild. Möglich sind PNG, JPEG und HEIC.")
        case .kopieren(let name):
            String(localized: "„\(name)“ ließ sich nicht in den Bilderordner kopieren.")
        case .ungueltigerPfad:
            String(localized: "Der Bildpfad zeigt aus dem Bilderordner heraus und wird nicht gespeichert.")
        }
    }
}
