#if os(macOS)
import Foundation
import Testing
import TradingCore
import TradingStore
@testable import Trading_Buddy

/// Import-Ordner (Doc 45): wann die App still importiert und wann sie nachfragt, gegen ein Journal im
/// Arbeitsspeicher und einen Ordner unter `temporaryDirectory`.
@Suite @MainActor struct ImportordnerTests {
    private typealias T = AppTestdaten

    private func entscheide(_ text: String, _ name: String, _ konten: [Konto]) -> Importordnerregel.Entscheidung {
        Importordnerregel.entscheide(daten: Data(text.utf8), dateiname: name, konten: konten, zeitzone: { _ in nil })
    }

    /// Konten wie nach einem Import von Hand: Scalable „Depot“, dazu `kraken` Kraken-Konten.
    private func konten(kraken: Int) throws -> [Konto] {
        let journal = try Journal.imSpeicher()
        _ = try journal.importiereCSV(datei: Data(T.scalable.utf8), dateiname: "appt-scalable.csv",
                                      kontonummer: "DE0012345678", kontowaehrung: "EUR", zeitzone: T.berlin)
        for nr in 0..<kraken {
            _ = try journal.importiereCSV(datei: Data(T.kraken(kennung: "K\(nr)").utf8), dateiname: "kraken-\(nr).csv",
                                          kontonummer: "Spot \(nr)", kontowaehrung: "USD", zeitzone: .gmt)
        }
        return try journal.konten()
    }

    @Test func csvMitGenauEinemKontoGehtStill() throws {
        let alle = try konten(kraken: 1)
        let depot = try #require(alle.first { $0.broker == "Scalable Capital" })
        #expect(entscheide(T.scalable, "scalable.csv", alle) == .csv(.scalable, depot))
        let spot = try #require(alle.first { $0.broker == "Kraken" })
        #expect(entscheide(T.kraken(kennung: "neu"), "kraken.csv", alle) == .csv(.kraken, spot))
    }

    @Test func csvOhneOderMitMehrerenKontenFragtNach() throws {
        if case .rueckfrage = entscheide(T.scalable, "scalable.csv", []) {} else { Issue.record("ohne Konto still") }
        let zwei = try konten(kraken: 2)
        #expect(zwei.count == 3)
        if case .rueckfrage = entscheide(T.kraken(kennung: "neu"), "kraken.csv", zwei) {} else {
            Issue.record("zwei Konten still")
        }
    }

    @Test func unbekanntesFormatFragtNach() {
        if case .rueckfrage = entscheide("Hallo Welt", "notiz.txt", []) {} else { Issue.record("Text still") }
        if case .rueckfrage = entscheide("kein Excel", "liste.xlsx", []) {} else { Issue.record("xlsx still") }
    }

    @Test func nurPassendeEndungenKommenInFrage() {
        #expect(Importordnerregel.kommtInFrage("auszug.CSV"))
        #expect(Importordnerregel.kommtInFrage("Statement.htm"))
        #expect(!Importordnerregel.kommtInFrage("auszug.csv.download"))
        #expect(!Importordnerregel.kommtInFrage(".auszug.csv"))
        #expect(!Importordnerregel.kommtInFrage("~$kontohistorie.xlsx"))
        #expect(!Importordnerregel.kommtInFrage("bild.png"))
    }

    /// Ganzer Lauf: bekannte Datei erledigt, Kraken ohne Konto in der Liste, nach Anlage des Kontos
    /// importiert die App eine neue Kraken-Datei still und vergisst die erledigten nicht.
    @Test func ordnerLaufImportiertStillUndFragtNach() throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        _ = try m.importiereCSV(daten: Data(T.scalable.utf8), dateiname: "appt-scalable.csv", kontonummer: "DE0012345678",
                                kontoname: "Depot", waehrung: "EUR", zeitzone: T.berlin)
        try Data(T.scalable.utf8).write(to: ordner.appending(path: "scalable.csv"))
        try Data(T.kraken(kennung: "A").utf8).write(to: ordner.appending(path: "kraken-a.csv"))
        let spaeter = Date.now.addingTimeInterval(60)

        let beobachtung = Importordner(speicher: speicher)
        beobachtung.pruefeTestweise(ordner, modell: m, jetzt: spaeter)
        #expect(beobachtung.rueckfragen.map(\.dateiname) == ["kraken-a.csv"])
        #expect(m.importe.count == 1)

        // Kraken-Konto einmal von Hand, dann kommt eine weitere Kraken-Datei.
        _ = try m.importiereCSV(daten: Data(T.kraken(kennung: "A").utf8), dateiname: "kraken-a.csv",
                                kontonummer: "Spot", kontoname: "Spot", waehrung: "USD", zeitzone: .gmt)
        try Data(T.kraken(kennung: "B").utf8).write(to: ordner.appending(path: "kraken-b.csv"))
        beobachtung.pruefe(jetzt: spaeter)
        #expect(beobachtung.rueckfragen.isEmpty)
        #expect(m.importe.count == 3)
        #expect(beobachtung.zuletzt.first?.dateiname == "kraken-b.csv")
        #expect(m.konten.count == 2)

        // Zweiter Lauf ändert nichts.
        beobachtung.pruefe(jetzt: spaeter)
        #expect(m.importe.count == 3)
        #expect(beobachtung.zuletzt.count == 1)
    }

    @Test func ignorierteDateiKommtNichtWieder() throws {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "importordner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ordner) }
        let speicher = try #require(UserDefaults(suiteName: "importordner-\(UUID().uuidString)"))
        let m = AppModell(journal: try Journal.imSpeicher(), nebenwirkungen: false)
        try Data("Hallo".utf8).write(to: ordner.appending(path: "notiz.txt"))
        let beobachtung = Importordner(speicher: speicher)
        beobachtung.pruefeTestweise(ordner, modell: m, jetzt: Date.now.addingTimeInterval(60))
        let rueckfrage = try #require(beobachtung.rueckfragen.first)
        beobachtung.ignoriere(rueckfrage)
        beobachtung.pruefe(jetzt: Date.now.addingTimeInterval(60))
        #expect(beobachtung.rueckfragen.isEmpty)
    }
}
#endif
