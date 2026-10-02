import Foundation
import Security
import Testing
import TradingQuotes
@testable import Trading_Buddy

/// Schlüsselbund mit dem Fake `SpeicherSchluesselablage` (Paket A7): nichts erreicht den echten Schlüsselbund.
@Suite @MainActor struct SchluesselbundTests {
    @Test func alpacaSchluesselHinUndZurueck() async throws {
        let ablage = SpeicherSchluesselablage()
        let bund = Schluesselbund(ablage: ablage)
        #expect(try bund.lies() == nil)
        #expect(!bund.vorhanden())
        try bund.speichere(AlpacaSchluessel(schluesselID: "ID-1", geheimnis: "G-1"))
        try bund.speichere(AlpacaSchluessel(schluesselID: "ID-2", geheimnis: "G-2"))
        let gelesen = try await bund.alpacaSchluessel()
        #expect(gelesen == AlpacaSchluessel(schluesselID: "ID-2", geheimnis: "G-2"))
        #expect(ablage.eintraege.count == 1)
        try bund.loesche()
        try bund.loesche()
        #expect(!bund.vorhanden())
    }

    @Test func textschluesselGetrenntVomAlpacaSchluessel() throws {
        let bund = Schluesselbund(ablage: SpeicherSchluesselablage())
        try bund.speichereText("token-1", dienst: Schluesselbund.dienstMarketaux)
        #expect(try bund.liesText(dienst: Schluesselbund.dienstMarketaux) == "token-1")
        #expect(bund.textVorhanden(dienst: Schluesselbund.dienstMarketaux))
        #expect(!bund.vorhanden())
        try bund.loescheText(dienst: Schluesselbund.dienstMarketaux)
        #expect(!bund.textVorhanden(dienst: Schluesselbund.dienstMarketaux))
    }

    @Test func fehlerDerAblageKommtAlsSchluesselbundFehler() throws {
        let ablage = SpeicherSchluesselablage()
        let bund = Schluesselbund(ablage: ablage)
        try bund.speichere(AlpacaSchluessel(schluesselID: "ID", geheimnis: "G"))
        ablage.setzeFehler(errSecAuthFailed)
        #expect(throws: Schluesselbund.Fehler.self) { try bund.lies() }
        #expect(throws: Schluesselbund.Fehler.self) { try bund.speichere(AlpacaSchluessel(schluesselID: "X", geheimnis: "Y")) }
        #expect(!bund.vorhanden())
        ablage.setzeFehler(nil)
        #expect(try bund.lies()?.schluesselID == "ID")
    }

    /// Kursdienst mit Fake-Schlüssel, Fake-Abruf und eigener Datei: Ohne eingeschaltete Kurse kein Abruf.
    @Test func kursdienstOhneKurseRuftNichtsAb() async throws {
        let speicher = try #require(UserDefaults(suiteName: "SchluesselbundTests-\(UUID().uuidString)"))
        let datei = FileManager.default.temporaryDirectory.appendingPathComponent("verlaeufe-\(UUID().uuidString).json")
        let dienst = Kursdienst(speicher: speicher, schluesselbund: Schluesselbund(ablage: SpeicherSchluesselablage()),
                                abruf: { _ in Issue.record("Abruf ohne eingeschaltete Kurse"); return (500, Data()) },
                                verlaufsdatei: datei)
        #expect(!dienst.aktiv)
        await dienst.ladeVerlaeufe(fuer: ["BTC/EUR"])
        #expect(dienst.verlaeufe.geladen == nil)
        let ergebnis = await dienst.ladeMinutenkerzen(fuer: [])
        #expect(ergebnis == Minutenabruf())
    }
}
