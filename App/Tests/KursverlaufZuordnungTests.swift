import Foundation
import Testing
import TradingQuotes
@testable import Trading_Buddy

private let krakenAntwort = #"{"error":[],"result":{"BTC/EUR":[[1799884800,"1","2","0.5","1.5","1","9",4]]}}"#
private let m1Jetzt = Date(timeIntervalSince1970: 1_800_000_000)

/// Codex M1 (04.10.2026): Nach geänderter Kurszuordnung fallen alte Tageskerzen weg, und eine Antwort,
/// die während des Wechsels noch unterwegs war, wird nicht übernommen.
@Suite @MainActor struct KursverlaufZuordnungTests {
    /// Hält den Dienst für den Abruf-Fake, der mitten im Abruf die Zuordnung wechselt.
    @MainActor final class Kasten {
        var dienst: Kursdienst?
    }

    private func dienst(_ name: String, aktiv: Bool, abruf: @escaping Abruf) -> Kursdienst {
        let speicher = UserDefaults(suiteName: name)!
        speicher.set(aktiv, forKey: Kursdienst.schluesselAktiv)
        return Kursdienst(speicher: speicher, schluesselbund: Schluesselbund(ablage: SpeicherSchluesselablage()),
                          abruf: abruf,
                          verlaufsdatei: FileManager.default.temporaryDirectory
                              .appendingPathComponent("appt-verlaeufe-\(UUID().uuidString).json"))
    }

    @Test func antwortDerAltenZuordnungWirdVerworfen() async {
        let name = "appt-m1-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let kasten = Kasten()
        let d = dienst(name, aktiv: true) { _ in
            await MainActor.run {
                kasten.dienst?.setzeZuordnung(Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/USD"))
            }
            return (200, Data(krakenAntwort.utf8))
        }
        kasten.dienst = d
        d.setzeZuordnung(Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/EUR"))
        await d.ladeVerlaeufe(fuer: ["BTC"], jetzt: m1Jetzt)
        #expect(d.verlaeufe.verlaeufe["BTC"] == nil)
        #expect(d.verlaeufe.fehler["BTC"] == nil)
    }

    @Test func antwortOhneWechselWirdUebernommenUndBeiWechselVerworfen() async {
        let name = "appt-m1-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let d = dienst(name, aktiv: true) { _ in (200, Data(krakenAntwort.utf8)) }
        d.setzeZuordnung(Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/EUR"))
        await d.ladeVerlaeufe(fuer: ["BTC"], jetzt: m1Jetzt)
        #expect(d.verlaeufe.verlaeufe["BTC"]?.quellSymbol == "BTC/EUR")
        d.setzeZuordnung(Kurszuordnung(journalSymbol: "BTC", quelle: "kraken", quellSymbol: "BTC/USD"))
        #expect(d.verlaeufe.verlaeufe["BTC"] == nil)
    }
}
