import Foundation
import Testing
@testable import Trading_Buddy

/// Eigene Werte im Kurschart (Tim 05.10.2026): Eingabe prüfen, speichern, entfernen, Liste zusammenführen.
@Suite @MainActor struct ChartwerteTests {
    private func dienst(_ name: String) -> Kursdienst {
        Kursdienst(speicher: UserDefaults(suiteName: name)!,
                   schluesselbund: Schluesselbund(ablage: SpeicherSchluesselablage()),
                   abruf: { _ in Issue.record("Abruf ohne Erwartung"); return (500, Data()) },
                   verlaufsdatei: FileManager.default.temporaryDirectory
                       .appendingPathComponent("appt-verlaeufe-\(UUID().uuidString).json"))
    }

    @Test func eingabeWirdGeprueft() {
        #expect(Chartwerteingabe.pruefe(" btc/eur ", alpacaSchluessel: false) == .wert("BTC/EUR"))
        #expect(Chartwerteingabe.pruefe("ETHUSD", alpacaSchluessel: false) == .wert("ETH/USD"))
        #expect(Chartwerteingabe.pruefe("btc", alpacaSchluessel: false) == .wert("BTC/EUR"))
        #expect(Chartwerteingabe.pruefe("aapl", alpacaSchluessel: true) == .wert("AAPL.US"))
        #expect(Chartwerteingabe.pruefe("AAPL.US", alpacaSchluessel: true) == .wert("AAPL.US"))
        for ohneQuelle in ["", "   ", "EURUSD", "de40", "Nvidia Zölle"] {
            guard case .fehler = Chartwerteingabe.pruefe(ohneQuelle, alpacaSchluessel: true) else {
                Issue.record("„\(ohneQuelle)“ hätte abgelehnt werden müssen")
                continue
            }
        }
        // Ohne Alpaca-Schlüssel keine US-Aktie, sondern der Hinweis auf die Einstellungen.
        guard case .fehler(let text) = Chartwerteingabe.pruefe("AAPL", alpacaSchluessel: false) else {
            Issue.record("AAPL ohne Schlüssel angenommen")
            return
        }
        #expect(!text.isEmpty)
    }

    @Test func eigeneWerteWerdenGespeichertUndEntfernt() {
        let name = "appt-chartwerte-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let erster = dienst(name)
        #expect(erster.fuegeChartwertHinzu("btc/eur") == .wert("BTC/EUR"))
        #expect(erster.fuegeChartwertHinzu("BTCEUR") == .wert("BTC/EUR"))
        #expect(erster.fuegeChartwertHinzu("sol") == .wert("SOL/EUR"))
        // Ohne Schlüssel im Fake-Schlüsselbund wird AAPL abgelehnt und nicht gespeichert.
        if case .wert = erster.fuegeChartwertHinzu("AAPL") { Issue.record("AAPL ohne Schlüssel gespeichert") }
        #expect(erster.chartwerte == ["BTC/EUR", "SOL/EUR"])

        let zweiter = dienst(name)
        #expect(zweiter.chartwerte == ["BTC/EUR", "SOL/EUR"])
        zweiter.entferneChartwert("BTC/EUR")
        #expect(zweiter.chartwerte == ["SOL/EUR"])
        #expect(dienst(name).chartwerte == ["SOL/EUR"])
    }

    @Test func listeFuehrtJournalEigeneUndMerklisteZusammen() {
        let merkliste = Chartwerteingabe.ausMerkliste(["BTC", "AAPL", "Nvidia", "ETH/EUR"], alpacaSchluessel: false)
        #expect(merkliste == ["BTC/EUR", "ETH/EUR"])
        let liste = Chartwerteingabe.liste(journal: ["BTC/EUR", "AAPL.US"], eigene: ["SOL/EUR", "BTC/EUR"],
                                           merkliste: merkliste)
        #expect(liste == ["BTC/EUR", "AAPL.US", "SOL/EUR", "ETH/EUR"])
    }
}
