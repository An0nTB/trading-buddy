#if os(macOS)
import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Regression zum Gegencheck G19 (Doc 49): Der Import-Ordner liest, prüft und speichert abseits des Hauptthreads,
/// liest Rückfragen zu unveränderten Dateien nicht bei jedem Anstoß neu und lässt keine zwei Läufe gleichzeitig zu.
/// Ergänzung zu `ImportordnerTests`; arbeitet nur in eigenen Ordnern und Einstellungs-Suiten.
@Suite @MainActor struct ImportordnerHintergrundTests {
    private typealias T = AppTestdaten

    /// Kraken-Export „A“ plus zwei neue Zeilen „B“: überschneidet sich mit „A“ und geht daher still (G21).
    private static var krakenFolgeexport: String {
        let neu = T.kraken(kennung: "B").split(separator: "\n").dropFirst().joined(separator: "\n")
        return T.kraken(kennung: "A") + neu + "\n"
    }

    private struct Umgebung {
        let ordner: URL
        let suite = "appt-importordner-\(UUID().uuidString)"
        var speicher: UserDefaults { UserDefaults(suiteName: suite)! }

        init() throws {
            ordner = FileManager.default.temporaryDirectory.appending(path: "appt-importordner-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        }

        func aufraeumen() {
            try? FileManager.default.removeItem(at: ordner)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    private func modellMitKraken() throws -> AppModell {
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "appt-kraken-a.csv",
                                kontonummer: "Spot", kontoname: "Spot", waehrung: "USD", zeitzone: .gmt)
        return m
    }

    private func kandidat(_ url: URL, signatur: String) throws -> Importordner.Kandidat {
        let groesse = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return Importordner.Kandidat(url: url, name: url.lastPathComponent, signatur: signatur, groesse: groesse)
    }

    /// `verarbeite` ist nicht an den Hauptthread gebunden: Der Aufruf aus einer abgekoppelten Aufgabe übersetzt
    /// nur so. Folgeexport wird gespeichert, eine unlesbare Textdatei wird zur Rückfrage.
    @Test func verarbeitungLaeuftAbseitsDesHauptthreads() async throws {
        let umgebung = try Umgebung()
        defer { umgebung.aufraeumen() }
        let m = try modellMitKraken()
        let journal = try #require(m.journal)
        let export = umgebung.ordner.appending(path: "kraken-b.csv")
        let notiz = umgebung.ordner.appending(path: "notiz.txt")
        try Data(Self.krakenFolgeexport.utf8).write(to: export)
        try Data("Hallo".utf8).write(to: notiz)
        let liste = [try kandidat(export, signatur: "export"), try kandidat(notiz, signatur: "notiz")]
        let konten = m.konten
        let bekannt = Set(m.importe.map(\.lauf.dateiHash))

        let ausgaenge = await Task.detached(priority: .utility) {
            Importordner.verarbeite(liste, journal: journal, konten: konten, zonen: [:], bekannteHashes: bekannt)
        }.value
        #expect(ausgaenge.count == 2)
        for ausgang in ausgaenge {
            switch ausgang {
            case .erledigt(let signatur, _, let hash, _, let gespeichert):
                #expect(signatur == "export")
                #expect(gespeichert)
                #expect(!bekannt.contains(hash))
            case .rueckfrage(let rueckfrage):
                #expect(rueckfrage.id == "notiz")
            }
        }
        m.laden()
        #expect(m.importe.count == 2)
    }

    /// Bekannter Hash im selben Lauf: zweite Kopie derselben Datei gilt als erledigt, ohne zweite Speicherung.
    @Test func gleicheDateiImSelbenLaufNurEinmalGespeichert() throws {
        let umgebung = try Umgebung()
        defer { umgebung.aufraeumen() }
        let m = try modellMitKraken()
        let journal = try #require(m.journal)
        let eins = umgebung.ordner.appending(path: "kraken-b.csv")
        let zwei = umgebung.ordner.appending(path: "kraken-b-kopie.csv")
        try Data(Self.krakenFolgeexport.utf8).write(to: eins)
        try Data(Self.krakenFolgeexport.utf8).write(to: zwei)
        let ausgaenge = Importordner.verarbeite([try kandidat(eins, signatur: "1"), try kandidat(zwei, signatur: "2")],
                                                journal: journal, konten: m.konten, zonen: [:],
                                                bekannteHashes: Set(m.importe.map(\.lauf.dateiHash)))
        let gespeichert = ausgaenge.map { ausgang -> Bool in
            if case .erledigt(_, _, _, _, let neu) = ausgang { return neu }
            return false
        }
        #expect(gespeichert == [true, false])
        m.laden()
        #expect(m.importe.count == 2)
    }

    /// Rückfrage zu einer unveränderten Datei liest die App erst nach einer Journaländerung neu: Die Datei wird
    /// nach dem ersten Lauf unlesbar gemacht (Name, Größe, Änderungszeit bleiben), der Grund bleibt bis dahin gleich.
    @Test func rueckfrageWirdNurNachJournalaenderungNeuGelesen() async throws {
        let umgebung = try Umgebung()
        defer { umgebung.aufraeumen() }
        let notiz = umgebung.ordner.appending(path: "notiz.txt")
        try Data("Hallo".utf8).write(to: notiz)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: notiz.path) }
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        let spaeter = Date.now.addingTimeInterval(60)
        let beobachtung = Importordner(speicher: umgebung.speicher)

        await beobachtung.pruefeTestweise(umgebung.ordner, modell: m, jetzt: spaeter)
        let erste = try #require(beobachtung.rueckfragen.first)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: notiz.path)

        await beobachtung.pruefe(jetzt: spaeter)
        #expect(beobachtung.rueckfragen == [erste])

        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "appt-kraken-a.csv",
                                kontonummer: "Spot", kontoname: "Spot", waehrung: "USD", zeitzone: .gmt)
        await beobachtung.pruefe(jetzt: spaeter)
        let neu = try #require(beobachtung.rueckfragen.first)
        #expect(neu.id == erste.id)
        #expect(neu.grund != erste.grund)
    }

    /// Zwei Anstöße kurz hintereinander: ein Import, eine Meldung, keine zweite „schon importiert“-Zeile.
    @Test func zweiAnstoesseFuehrenZuEinemImport() async throws {
        let umgebung = try Umgebung()
        defer { umgebung.aufraeumen() }
        try Data(Self.krakenFolgeexport.utf8).write(to: umgebung.ordner.appending(path: "kraken-b.csv"))
        let m = try modellMitKraken()
        let spaeter = Date.now.addingTimeInterval(60)
        let beobachtung = Importordner(speicher: umgebung.speicher)

        let erster = Task { await beobachtung.pruefeTestweise(umgebung.ordner, modell: m, jetzt: spaeter) }
        let zweiter = Task { await beobachtung.pruefe(jetzt: spaeter) }
        await erster.value
        await zweiter.value
        #expect(m.importe.count == 2)
        #expect(beobachtung.zuletzt.count == 1)
        #expect(beobachtung.rueckfragen.isEmpty)
    }
}
#endif
