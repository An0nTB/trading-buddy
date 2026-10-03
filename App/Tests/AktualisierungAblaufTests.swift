#if os(macOS)
import Foundation
import Testing
@testable import Trading_Buddy

/// Ergänzung zu `AktualisierungTests` (#209, Doc 51): Versionsreihe, eine Abfrage am Tag auch über einen Neustart,
/// Schalter aus, stiller Netzfehler, kein zweiter Abruf während einer laufenden Prüfung und die Auswertung der
/// HTTP-Antwort. Kein echtes Netz: Abruf als Attrappe, `hole(session:)` über ein eigenes `URLProtocol`.
@Suite @MainActor struct AktualisierungAblaufTests {
    private typealias V = Aktualisierung.Veroeffentlichung

    private struct Ablage {
        let name = "appt-aktualisierung-ablauf-\(UUID().uuidString)"
        var d: UserDefaults { UserDefaults(suiteName: name)! }
        func aufraeumen() { UserDefaults.standard.removePersistentDomain(forName: name) }
    }

    private final class Zaehler: @unchecked Sendable {
        var anzahl = 0
    }

    private nonisolated static func version(_ tag: String) -> V {
        V(tag: tag, seite: URL(string: "https://github.com/An0nTB/trading-buddy/releases/tag/\(tag)")!)
    }

    private nonisolated static let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func versionsreihe() {
        let reihe = ["0.1.0", "0.1.1", "0.2.0", "0.10.0", "1.0.0"]
        for (i, alt) in reihe.enumerated() {
            for neu in reihe[(i + 1)...] {
                #expect(Aktualisierung.istNeuer(neu, als: alt), "\(neu) > \(alt)")
                #expect(!Aktualisierung.istNeuer(alt, als: neu), "\(alt) < \(neu)")
            }
            #expect(!Aktualisierung.istNeuer(alt, als: alt))
        }
        // Tag mit „v“ oder „V“ und Leerzeichen zählen wie die blanke Nummer.
        #expect(Aktualisierung.istNeuer("V0.2.0", als: "v0.1.1"))
        #expect(!Aktualisierung.istNeuer(" v1.0.0 ", als: "1.0.0"))
        #expect(Self.version("V1.2.3").version == "1.2.3")
        // Vorabversionen sind unlesbar und lösen nie einen Hinweis aus, in beide Richtungen.
        #expect(!Aktualisierung.istNeuer("0.2.0-beta.1", als: "0.1.0"))
        #expect(!Aktualisierung.istNeuer("0.3.0", als: "0.2.0-beta"))
    }

    /// Höchstens eine Abfrage am Tag, auch wenn die App dazwischen neu startet; gemeldete Version bleibt gemeldet.
    @Test func eineAbfrageAmTagUeberNeustart() async {
        let ablage = Ablage()
        defer { ablage.aufraeumen() }
        let zaehler = Zaehler()
        let erste = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            return Self.version("v0.2.0")
        }
        await erste.pruefe(jetzt: Self.start)
        #expect(erste.hinweis?.tag == "v0.2.0")
        erste.gemeldet()

        // Neustart: neuer Dienst über dieselben Einstellungen.
        let zweite = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            return Self.version("v0.2.0")
        }
        #expect(zweite.letztePruefung == Self.start)
        await zweite.pruefe(jetzt: Self.start.addingTimeInterval(3_600))
        #expect(zaehler.anzahl == 1)
        await zweite.pruefe(jetzt: Self.start.addingTimeInterval(25 * 3_600))
        #expect(zaehler.anzahl == 2)
        #expect(zweite.hinweis == nil)

        // Am Tag darauf gibt es eine neuere Version: Hinweis kommt.
        let dritte = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            return Self.version("v0.2.1")
        }
        await dritte.pruefe(jetzt: Self.start.addingTimeInterval(50 * 3_600))
        #expect(zaehler.anzahl == 3)
        #expect(dritte.hinweis?.tag == "v0.2.1")
    }

    /// Schalter aus: beim Start keine Abfrage. „Jetzt prüfen“ fragt trotzdem, ohne Hinweis.
    @Test func schalterAusHeisstKeineAbfrage() async {
        let ablage = Ablage()
        defer { ablage.aufraeumen() }
        ablage.d.set(false, forKey: Aktualisierung.schalterSchluessel)
        let zaehler = Zaehler()
        let dienst = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            return Self.version("v9.0.0")
        }
        #expect(!dienst.eingeschaltet)
        await dienst.pruefe(jetzt: Self.start)
        await dienst.pruefe(jetzt: Self.start.addingTimeInterval(48 * 3_600))
        #expect(zaehler.anzahl == 0)
        #expect(dienst.letztePruefung == nil)
        await dienst.pruefe(erzwungen: true, jetzt: Self.start)
        #expect(zaehler.anzahl == 1)
        #expect(dienst.hinweis == nil)
        #expect(dienst.gibtNeuere)
    }

    /// Netzfehler: kein Hinweis, kein Zeitstempel; der nächste Start fragt wieder. Ein bekannter Stand bleibt.
    @Test func netzfehlerBleibtStill() async {
        let ablage = Ablage()
        defer { ablage.aufraeumen() }
        let zaehler = Zaehler()
        let fehlerhaft = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            throw URLError(.timedOut)
        }
        await fehlerhaft.pruefe(jetzt: Self.start)
        await fehlerhaft.pruefe(jetzt: Self.start.addingTimeInterval(60))
        #expect(zaehler.anzahl == 2)
        #expect(fehlerhaft.hinweis == nil)
        #expect(!fehlerhaft.gibtNeuere)
        #expect(fehlerhaft.letztePruefung == nil)

        // Erst Erfolg, Hinweis gezeigt, am nächsten Tag Netzfehler: Stand und Zeitpunkt bleiben, kein neuer Hinweis.
        let erfolg = Zaehler()
        let dienst = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            erfolg.anzahl += 1
            if erfolg.anzahl > 1 { throw URLError(.notConnectedToInternet) }
            return Self.version("v0.5.0")
        }
        await dienst.pruefe(jetzt: Self.start)
        dienst.gemeldet()
        await dienst.pruefe(jetzt: Self.start.addingTimeInterval(25 * 3_600))
        #expect(erfolg.anzahl == 2)
        #expect(dienst.hinweis == nil)
        #expect(dienst.neueste?.tag == "v0.5.0")
        #expect(dienst.letztePruefung == Self.start)
        #expect(dienst.fehler != nil)
    }

    /// Zwei Anstöße während einer laufenden Prüfung: ein Abruf.
    @Test func keinZweiterAbrufWaehrendDerPruefung() async {
        let ablage = Ablage()
        defer { ablage.aufraeumen() }
        let zaehler = Zaehler()
        let dienst = Aktualisierungsdienst(einstellungen: ablage.d, eigeneVersion: "0.1.0") {
            zaehler.anzahl += 1
            try await Task.sleep(for: .milliseconds(200))
            return Self.version("v0.2.0")
        }
        let erster = Task { await dienst.pruefe(jetzt: Self.start) }
        let zweiter = Task { await dienst.pruefe(erzwungen: true, jetzt: Self.start) }
        await erster.value
        await zweiter.value
        #expect(zaehler.anzahl == 1)
        #expect(!dienst.laeuft)
    }

    /// Antwortet auf jede Anfrage mit `status` und `daten`; merkt sich die Anfragen.
    private final class Attrappe: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var daten = Data()
        nonisolated(unsafe) static var anfragen: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.anfragen.append(request)
            let antwort = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                          headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: antwort, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.daten)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// `hole(session:)`: 200 liefert die Version, 404 heißt „noch keine Veröffentlichung“, 500 ist ein Fehler.
    @Test func antwortDesServers() async throws {
        let konfiguration = URLSessionConfiguration.ephemeral
        konfiguration.protocolClasses = [Attrappe.self]
        let session = URLSession(configuration: konfiguration)
        defer { session.invalidateAndCancel() }
        Attrappe.anfragen = []

        Attrappe.status = 200
        Attrappe.daten = Data(#"{"tag_name":"v0.3.0","html_url":"https://github.com/An0nTB/trading-buddy/releases/tag/v0.3.0"}"#.utf8)
        let neu = try await Aktualisierung.hole(session: session)
        #expect(neu?.version == "0.3.0")

        Attrappe.status = 404
        Attrappe.daten = Data(#"{"message":"Not Found"}"#.utf8)
        #expect(try await Aktualisierung.hole(session: session) == nil)

        Attrappe.status = 500
        Attrappe.daten = Data()
        await #expect(throws: (any Error).self) { _ = try await Aktualisierung.hole(session: session) }

        #expect(Attrappe.anfragen.count == 3)
        let anfrage = try #require(Attrappe.anfragen.first)
        #expect(anfrage.url == Aktualisierung.adresse)
        #expect(anfrage.httpMethod == "GET")
        #expect(anfrage.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        // Hinaus geht nur die Anfrage selbst, ohne Inhalt.
        #expect(anfrage.httpBody == nil)
    }
}
#endif
