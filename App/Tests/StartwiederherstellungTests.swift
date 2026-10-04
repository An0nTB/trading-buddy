import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Start mit beschädigter Journal-Datei (AP9 #225): statt der Seiten den Ausweg anbieten, Sicherung zurückspielen
/// oder neu beginnen. Die alte Datei bleibt in beiden Fällen erhalten. Arbeitet in einem temporären Ordner.
@Suite @MainActor struct StartwiederherstellungTests {
    private typealias T = AppTestdaten

    private func ordner() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "appt-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Legt ein Journal mit einem Konto an, sichert es optional und zerstört danach alles nach der ersten Seite.
    private func beschaedigtesJournal(in dir: URL, sicherung: URL?) throws -> (pfad: String, inhalt: Data) {
        let pfad = dir.appending(path: "journal.sqlite").path
        do {
            let journal = try Journal(pfad: pfad)
            let m = AppModell(journal: journal, nebenwirkungen: false)
            _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                    kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR",
                                    zeitzone: T.berlin)
            if let sicherung { try journal.sichereInOrdner(sicherung, jetzt: T.zeit(2026, 10, 3, 3), zeitzone: .gmt) }
        }
        var inhalt = try Data(contentsOf: URL(fileURLWithPath: pfad))
        #expect(inhalt.count > 8_192)
        inhalt.replaceSubrange(4_096..<inhalt.count, with: Data(repeating: 0, count: inhalt.count - 4_096))
        try inhalt.write(to: URL(fileURLWithPath: pfad))
        return (pfad, inhalt)
    }

    @Test func beschaedigteDateiBietetSicherungAn() throws {
        let dir = try ordner()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sicherungen = dir.appending(path: "Sicherung")
        let (pfad, inhalt) = try beschaedigtesJournal(in: dir, sicherung: sicherungen)

        let m = AppModell(testpfad: pfad)
        #expect(m.journal == nil)
        #expect(m.fehler == nil)
        guard case .beschaedigt? = m.startfehler else {
            Issue.record("Kein Startfehler .beschaedigt: \(String(describing: m.startfehler))")
            return
        }

        let angebot = try #require(Startwiederherstellung.angebot(in: sicherungen))
        #expect(angebot.pruefung.konten == 1)
        try m.startAusSicherung(angebot, ordner: sicherungen)
        #expect(m.startfehler == nil)
        #expect(m.journal != nil)
        #expect(m.konten.count == 1)
        #expect(!m.alleTrades.isEmpty)
        let meldung = try #require(m.startmeldung)
        let weg = try #require(meldung.beiseite)
        #expect(try Data(contentsOf: weg) == inhalt)
        #expect(meldung.text.contains(weg.path))
    }

    @Test func ohneSicherungNeuBeginnen() throws {
        let dir = try ordner()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (pfad, inhalt) = try beschaedigtesJournal(in: dir, sicherung: nil)

        let m = AppModell(testpfad: pfad)
        #expect(m.startfehler != nil)
        #expect(Startwiederherstellung.angebot(in: dir.appending(path: "Sicherung")) == nil)
        #expect(Startwiederherstellung.angebot(in: nil) == nil)

        try m.startNeu()
        #expect(m.startfehler == nil)
        #expect(m.journal != nil)
        #expect(m.konten.isEmpty)
        let weg = try #require(m.startmeldung?.beiseite)
        #expect(try Data(contentsOf: weg) == inhalt)
        // Danach normal weiterarbeiten: Import landet im neuen Journal.
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                kontonummer: "DE0012345678", kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        #expect(m.konten.count == 1)
    }

    @Test func nurBeschaedigtUndNeuereVersionBekommenAusweg() {
        #expect(Startwiederherstellung.bietetAusweg(.beschaedigt("x")))
        #expect(Startwiederherstellung.bietetAusweg(.ausNeuererVersion(["y"])))
        #expect(!Startwiederherstellung.bietetAusweg(.platteVoll))
        #expect(!Startwiederherstellung.bietetAusweg(.nurLesbar))
        #expect(!Startwiederherstellung.bietetAusweg(.keinZugriff("z")))
    }
}
