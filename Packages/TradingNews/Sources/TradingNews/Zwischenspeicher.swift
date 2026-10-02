import Foundation

/// Hält zuletzt geladene Meldungen als JSON-Datei, damit die Seite nach dem Start sofort etwas zeigt.
/// Wegwerfbar und deshalb nicht in der Journal-Datenbank (Absprache mit AP9, 02.10.2026).
/// Nur Überschrift, Anriss, Quelle, Zeit und Link, 14 Tage Aufbewahrung (Lizenz, R6).
public struct Zwischenspeicher: Sendable {
    public static let aufbewahrung: TimeInterval = 14 * 24 * 3600

    public let datei: URL

    /// - Parameter datei: z. B. im Ordner Application Support der App.
    public init(datei: URL) {
        self.datei = datei
    }

    private struct Inhalt: Codable {
        var version = 1
        var meldungen: [Meldung]
    }

    /// Fehlt die Datei oder ist sie unlesbar, beginnt der Speicher leer.
    public func lies(jetzt: Date) -> [Meldung] {
        guard let daten = try? Data(contentsOf: datei),
              let inhalt = try? Self.decoder().decode(Inhalt.self, from: daten) else { return [] }
        return aktuell(inhalt.meldungen, jetzt: jetzt)
    }

    /// Ergänzt den Bestand um neue Meldungen, entfernt Doppelte und alles älter als 14 Tage.
    @discardableResult
    public func ergaenze(_ neue: [Meldung], jetzt: Date) throws -> [Meldung] {
        let alle = aktuell(Doppelte.entferne(neue + lies(jetzt: jetzt)), jetzt: jetzt)
        let ordner = datei.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try Self.encoder().encode(Inhalt(meldungen: alle)).write(to: datei, options: .atomic)
        return alle
    }

    private func aktuell(_ meldungen: [Meldung], jetzt: Date) -> [Meldung] {
        meldungen.filter { jetzt.timeIntervalSince($0.zeit) <= Self.aufbewahrung }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
