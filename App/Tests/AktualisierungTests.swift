import Foundation
import Testing
@testable import Trading_Buddy

/// Update-Hinweis für Beta-Tester (Doc 51): Versionsvergleich, Tagesabstand, Antwort der GitHub-API und wann der
/// Hinweis kommt. Eigene Einstellungen je Test (`UserDefaults(suiteName:)`), Abruf als Attrappe, kein Netz.
@Suite @MainActor struct AktualisierungTests {
    private typealias V = Aktualisierung.Veroeffentlichung

    private func einstellungen() -> UserDefaults {
        let name = "appt-aktualisierung-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func version(_ tag: String) -> V {
        V(tag: tag, seite: URL(string: "https://github.com/An0nTB/trading-buddy/releases/tag/\(tag)")!)
    }

    /// Zählt die Abrufe, damit Tests sehen, ob überhaupt gefragt wurde.
    private final class Zaehler: @unchecked Sendable {
        var anzahl = 0
    }

    @Test func versionsteile() {
        #expect(Aktualisierung.versionsteile("v0.9.1") == [0, 9, 1])
        #expect(Aktualisierung.versionsteile("1.2") == [1, 2])
        #expect(Aktualisierung.versionsteile("0.9.1-beta") == nil)
        #expect(Aktualisierung.versionsteile("") == nil)
        #expect(Aktualisierung.versionsteile("1..2") == nil)
    }

    @Test func vergleich() {
        #expect(Aktualisierung.istNeuer("v0.9.0", als: "0.1.0"))
        #expect(Aktualisierung.istNeuer("0.10.0", als: "0.9.9"))
        #expect(Aktualisierung.istNeuer("1.0.1", als: "1.0"))
        #expect(!Aktualisierung.istNeuer("1.0", als: "1.0.0"))
        #expect(!Aktualisierung.istNeuer("0.8.0", als: "0.9.0"))
        #expect(!Aktualisierung.istNeuer("nightly", als: "0.1.0"))
    }

    @Test func faelligNachEinemTag() {
        let jetzt = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Aktualisierung.faellig(letzte: nil, jetzt: jetzt))
        #expect(!Aktualisierung.faellig(letzte: jetzt.addingTimeInterval(-3_600), jetzt: jetzt))
        #expect(Aktualisierung.faellig(letzte: jetzt.addingTimeInterval(-86_400), jetzt: jetzt))
        #expect(Aktualisierung.faellig(letzte: jetzt.addingTimeInterval(3_600), jetzt: jetzt))
    }

    @Test func antwortDerAPI() throws {
        let json = #"{"tag_name":"v0.9.1","html_url":"https://github.com/An0nTB/trading-buddy/releases/tag/v0.9.1","draft":false,"prerelease":false,"name":"Henry 0.9.1"}"#
        let neu = try Aktualisierung.lies(Data(json.utf8))
        #expect(neu.tag == "v0.9.1")
        #expect(neu.version == "0.9.1")
        #expect(neu.seite.absoluteString.hasSuffix("/releases/tag/v0.9.1"))
    }

    @Test func hinweisEinmalJeVersion() async {
        let d = einstellungen()
        let neu = version("v0.9.0")
        let dienst = Aktualisierungsdienst(einstellungen: d, eigeneVersion: "0.1.0") { neu }
        let jetzt = Date(timeIntervalSince1970: 1_800_000_000)
        await dienst.pruefe(jetzt: jetzt)
        #expect(dienst.hinweis == neu)
        dienst.gemeldet()
        #expect(dienst.hinweis == nil)
        // Am nächsten Tag dieselbe Version: kein zweiter Hinweis.
        await dienst.pruefe(jetzt: jetzt.addingTimeInterval(90_000))
        #expect(dienst.hinweis == nil)
        #expect(dienst.gibtNeuere)
    }

    @Test func keinHinweisOhneNeuereVersion() async {
        let dienst = Aktualisierungsdienst(einstellungen: einstellungen(), eigeneVersion: "0.9.0") { [v = version("v0.9.0")] in v }
        await dienst.pruefe()
        #expect(dienst.hinweis == nil)
        #expect(!dienst.gibtNeuere)
        #expect(dienst.letztePruefung != nil)
    }

    @Test func ausgeschaltetUndNichtFaellig() async {
        let d = einstellungen()
        let zaehler = Zaehler()
        let neu = version("v2.0.0")
        let dienst = Aktualisierungsdienst(einstellungen: d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            return neu
        }
        d.set(false, forKey: Aktualisierung.schalterSchluessel)
        await dienst.pruefe()
        #expect(zaehler.anzahl == 0)
        d.set(true, forKey: Aktualisierung.schalterSchluessel)
        let jetzt = Date(timeIntervalSince1970: 1_800_000_000)
        await dienst.pruefe(jetzt: jetzt)
        await dienst.pruefe(jetzt: jetzt.addingTimeInterval(60))
        #expect(zaehler.anzahl == 1)
        // „Jetzt prüfen“ fragt trotzdem, zeigt aber keinen Hinweis.
        dienst.gemeldet()
        await dienst.pruefe(erzwungen: true, jetzt: jetzt.addingTimeInterval(120))
        #expect(zaehler.anzahl == 2)
        #expect(dienst.hinweis == nil)
    }

    @Test func fehlerBehaeltLetztePruefung() async {
        let d = einstellungen()
        let dienst = Aktualisierungsdienst(einstellungen: d, eigeneVersion: "0.1.0") { throw URLError(.notConnectedToInternet) }
        await dienst.pruefe()
        #expect(dienst.fehler != nil)
        #expect(dienst.letztePruefung == nil)
        #expect(d.object(forKey: Aktualisierung.letztePruefungSchluessel) == nil)
    }

    @Test func nochKeineVeroeffentlichung() async {
        let dienst = Aktualisierungsdienst(einstellungen: einstellungen(), eigeneVersion: "0.1.0") { nil }
        await dienst.pruefe()
        #expect(dienst.hinweis == nil)
        #expect(dienst.fehler == nil)
        #expect(!dienst.gibtNeuere)
    }
}
