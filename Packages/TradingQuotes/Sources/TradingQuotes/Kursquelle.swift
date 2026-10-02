import Foundation

/// Vertrag, den jede Datenquelle erfüllt (R1 „Provider-Schnittstelle“): Symbole rein, Kurse raus.
/// Wer die Quelle wechselt, ändert nur die Zuordnung, nicht die App.
public protocol Kursquelle: Sendable {
    /// Kurzname, auf den `Kurszuordnung.quelle` verweist, etwa "kraken".
    var id: String { get }
    /// Name für die Anzeige.
    var name: String { get }
    var verzoegerung: Verzoegerung { get }
    /// Höchstzahl gleichzeitig beobachteter Symbole; `nil` ohne bekannte Grenze.
    var hoechstzahlSymbole: Int? { get }
    /// Beobachtet die Symbole (Schreibweise der Quelle), bis der Strom abgebrochen wird.
    /// Verbindungsabbrüche meldet die Quelle als Status und verbindet sich selbst neu.
    func beobachte(_ symbole: [String]) -> AsyncStream<Quellereignis>
}

/// Fehler, nach denen ein neuer Versuch nichts bringt.
public enum Kursquellenfehler: Error, Sendable, Equatable {
    case schluesselFehlt
    case abgelehnt(String)
}

/// Ergebnis einer gelesenen Nachricht.
struct Lesung: Sendable, Equatable {
    var kurse: [Kurs] = []
    /// Antworten an den Anbieter, etwa Anmeldung und Abo nach „connected“ (Alpaca).
    var senden: [String] = []
    /// Anbieter verweigert endgültig (falscher Schlüssel, Grenze überschritten).
    var abbruch: String?
}

/// Übersetzt die Nachrichten eines Anbieters. Reine Logik ohne Netz, deshalb mit Text-Nachrichten testbar.
protocol Nachrichtenleser: Sendable {
    /// Nachrichten direkt nach dem Verbinden (Abo).
    func start() -> [String]
    /// Liest eine Nachricht. Unbekannte Nachrichten (Herzschlag, Bestätigungen) ergeben eine leere Lesung.
    mutating func lies(_ text: String, empfangen: Date) -> Lesung
}

/// Kursquelle über eine WebSocket-Verbindung: verbinden, abonnieren, lesen, bei Abbruch mit wachsender Pause neu verbinden.
struct WebSocketKursquelle: Kursquelle {
    let id: String
    let name: String
    let verzoegerung: Verzoegerung
    let hoechstzahlSymbole: Int?
    /// Adresse je Symbolliste (Binance trägt die Symbole in die Adresse ein).
    let adresse: @Sendable ([String]) -> URL
    /// Baut den Leser; darf werfen, etwa wenn der Schlüssel fehlt.
    let macheLeser: @Sendable ([String]) async throws -> any Nachrichtenleser
    let verbinde: WebSocketFabrik
    let warte: @Sendable (Duration) async -> Void
    let jetzt: @Sendable () -> Date
    /// Für Tests: nach so vielen Abbrüchen insgesamt aufgeben. `nil` heißt nie.
    var hoechstversuche: Int?

    func beobachte(_ symbole: [String]) -> AsyncStream<Quellereignis> {
        let quelle = self
        return AsyncStream { fortsetzung in
            let aufgabe = Task { await quelle.lauf(symbole, fortsetzung) }
            fortsetzung.onTermination = { _ in aufgabe.cancel() }
        }
    }

    /// Pause vor dem n-ten neuen Versuch: 2, 4, 8, 16, 32, dann 60 Sekunden.
    static func pause(_ versuch: Int) -> Duration {
        .seconds(min(60, 1 << min(versuch, 6)))
    }

    private func lauf(_ symbole: [String], _ fortsetzung: AsyncStream<Quellereignis>.Continuation) async {
        var versuch = 0
        var abbrueche = 0
        while !Task.isCancelled {
            do {
                var leser = try await macheLeser(symbole)
                let verbindung = try await verbinde(adresse(symbole))
                defer { verbindung.schliesse() }
                for text in leser.start() { try await verbindung.sende(text) }
                fortsetzung.yield(.status(.verbunden))
                while !Task.isCancelled {
                    let text = try await verbindung.empfange()
                    let lesung = leser.lies(text, empfangen: jetzt())
                    for antwort in lesung.senden { try await verbindung.sende(antwort) }
                    for kurs in lesung.kurse { fortsetzung.yield(.kurs(kurs)) }
                    if let grund = lesung.abbruch { throw Kursquellenfehler.abgelehnt(grund) }
                    versuch = 0
                }
            } catch let fehler as Kursquellenfehler {
                fortsetzung.yield(.status(.beendet(grund: Self.text(fehler))))
                break
            } catch {
                if Task.isCancelled { break }
                fortsetzung.yield(.status(.getrennt(grund: String(describing: error))))
            }
            versuch += 1
            abbrueche += 1
            if let hoechstversuche, abbrueche >= hoechstversuche { break }
            await warte(Self.pause(versuch))
        }
        fortsetzung.finish()
    }

    static func text(_ fehler: Kursquellenfehler) -> String {
        switch fehler {
        case .schluesselFehlt: "Schlüssel fehlt"
        case .abgelehnt(let grund): grund
        }
    }
}
