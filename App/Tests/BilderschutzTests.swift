import Foundation
import Testing
@testable import Trading_Buddy

/// G16 (Doc 49): Nach dem Wiederherstellen merkt die App einen Schutzzeitpunkt, damit das Aufräumen keine Screenshots
/// löscht, die die zurückgespielte Datenbank nicht kennt. Geprüft gegen eine eigene `UserDefaults`-Suite.
@Suite @MainActor struct BilderschutzTests {
    @Test func schutzzeitpunktWirdGemerkt() {
        let name = "appt-bilder-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let ablage = UserDefaults(suiteName: name)!
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == nil)
        let zeit = AppTestdaten.zeit(2026, 10, 2, 22, 43)
        Bilderordner.schuetzeBestand(jetzt: zeit, ablage: ablage)
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == zeit)
        let spaeter = zeit.addingTimeInterval(3600)
        Bilderordner.schuetzeBestand(jetzt: spaeter, ablage: ablage)
        #expect(Bilderordner.schutzzeitpunkt(ablage: ablage) == spaeter)
    }

    /// Ohne einen einzigen Verweis räumt die App nichts auf (leere oder neue Datenbank); der echte Ordner bleibt unberührt.
    @Test func ohneVerweiseWirdNichtsGeloescht() {
        #expect(Bilderordner.raeumeAuf(behalten: [], geschuetztBis: nil) == 0)
    }

    #if os(macOS)
    /// G16-Regression in einem eigenen Ordner: Verwaiste Bilder von vor dem Schutzzeitpunkt bleiben, ein verwaistes
    /// neueres wird gelöscht, ein verwiesenes bleibt immer. Ohne Schutzzeitpunkt wird jedes verwaiste Bild gelöscht.
    @Test func aufraeumenLoeschtNurUngeschuetzteVerwaisteBilder() throws {
        let fm = FileManager.default
        let basis = fm.temporaryDirectory.appending(path: "appt-bilder-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: basis) }
        let schutz = AppTestdaten.zeit(2026, 10, 1, 12)
        func lege(_ datei: String, erstellt: Date) throws {
            let url = basis.appending(path: datei)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("bild".utf8).write(to: url)
            try fm.setAttributes([.creationDate: erstellt], ofItemAtPath: url.path)
        }
        func gibt(_ datei: String) -> Bool { fm.fileExists(atPath: basis.appending(path: datei).path) }
        try lege("2026-09/alt.png", erstellt: schutz.addingTimeInterval(-3600))
        try lege("2026-10/neu.png", erstellt: schutz.addingTimeInterval(3600))
        try lege("2026-10/verwiesen.png", erstellt: schutz.addingTimeInterval(3600))
        try lege("2026-10/notiz.txt", erstellt: schutz.addingTimeInterval(3600))
        let behalten: Set<String> = ["2026-10/verwiesen.png"]

        #expect(Bilderordner.raeumeAuf(behalten: behalten, geschuetztBis: schutz, in: basis) == 1)
        #expect(gibt("2026-09/alt.png"))
        #expect(!gibt("2026-10/neu.png"))
        #expect(gibt("2026-10/verwiesen.png"))
        #expect(gibt("2026-10/notiz.txt"))

        #expect(Bilderordner.raeumeAuf(behalten: behalten, geschuetztBis: nil, in: basis) == 1)
        #expect(!gibt("2026-09/alt.png"))
        #expect(gibt("2026-10/verwiesen.png"))
    }

    /// Ohne Verweise bleibt auch ein eigener Ordner unangetastet.
    @Test func ohneVerweiseBleibtEigenerOrdnerUnberuehrt() throws {
        let fm = FileManager.default
        let basis = fm.temporaryDirectory.appending(path: "appt-bilder-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: basis) }
        let url = basis.appending(path: "2026-10/waise.png")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bild".utf8).write(to: url)
        #expect(Bilderordner.raeumeAuf(behalten: [], geschuetztBis: nil, in: basis) == 0)
        #expect(fm.fileExists(atPath: url.path))
    }
    #endif
}
