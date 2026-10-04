#if os(macOS)
import Foundation
import Testing
@testable import Trading_Buddy

/// Codex-Vollreview (Schwere hoch): Eine Sicherung, in der Bilder fehlen, darf nicht als vollständig gelten. Geprüft
/// gegen eigene Ordner im temporären Verzeichnis, nie gegen den Bilderordner des Nutzers.
@Suite struct SicherungBilderTests {
    private func ordner() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "appt-bildsicherung-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func schreibe(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func vollstaendigerSpiegelGiltAlsGesichert() throws {
        let spiegel = try ordner()
        defer { try? FileManager.default.removeItem(at: spiegel) }
        try schreibe("a", spiegel.appending(path: "2026-10/a.png"))
        let lauf = Sicherungsdienst.bewerte(sicherung: "s.sqlite", kopiert: .init(neu: 1),
                                            verweise: ["2026-10/a.png"], spiegel: spiegel)
        #expect(lauf.erfolgreich)
        #expect(!lauf.unvollstaendig)
    }

    @Test func fehlendesBildMachtDieSicherungUnvollstaendig() throws {
        let spiegel = try ordner()
        defer { try? FileManager.default.removeItem(at: spiegel) }
        try schreibe("a", spiegel.appending(path: "2026-10/a.png"))
        let verweise: Set<String> = ["2026-10/a.png", "2026-10/b.png", "2026-09/c.jpg"]
        #expect(Sicherungsdienst.fehlendImSpiegel(verweise, spiegel: spiegel) == 2)
        let lauf = Sicherungsdienst.bewerte(sicherung: "s.sqlite", kopiert: .init(neu: 1),
                                            verweise: verweise, spiegel: spiegel)
        #expect(lauf.erfolgreich)
        #expect(lauf.unvollstaendig)
        #expect(lauf.text.contains("2"))
    }

    @Test func unlesbareVerweiseMachenDieSicherungUnvollstaendig() throws {
        let spiegel = try ordner()
        defer { try? FileManager.default.removeItem(at: spiegel) }
        let lauf = Sicherungsdienst.bewerte(sicherung: "s.sqlite", kopiert: .init(), verweise: nil, spiegel: spiegel)
        #expect(lauf.unvollstaendig)
    }

    @Test func gescheiterteKopieWirdGezaehlt() throws {
        let basis = try ordner()
        defer { try? FileManager.default.removeItem(at: basis) }
        let quelle = basis.appending(path: "quelle", directoryHint: .isDirectory)
        try schreibe("a", quelle.appending(path: "2026-10/a.png"))
        // Das Ziel ist eine Datei, kein Ordner: Der Monatsordner darin lässt sich nicht anlegen.
        let ziel = basis.appending(path: "ziel")
        try schreibe("x", ziel)
        let ergebnis = Sicherungsdienst.kopiere(von: quelle, nach: ziel)
        #expect(ergebnis == .init(neu: 0, fehlgeschlagen: 1))
        let lauf = Sicherungsdienst.bewerte(sicherung: "s.sqlite", kopiert: ergebnis,
                                            verweise: ["2026-10/a.png"], spiegel: ziel)
        #expect(lauf.unvollstaendig)
    }
}
#endif
