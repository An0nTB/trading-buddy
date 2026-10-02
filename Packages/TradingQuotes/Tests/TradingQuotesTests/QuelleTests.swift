import Foundation
import Testing
@testable import TradingQuotes

/// Aufgezeichnete Verbindung: liefert feste Nachrichten, danach „Verbindung getrennt“.
struct Getrennt: Error {}

actor Mitschnitt {
    var verbindungen = 0
    var gesendet: [String] = []
    func neueVerbindung() { verbindungen += 1 }
    func merke(_ text: String) { gesendet.append(text) }
}

actor Folge {
    var rest: [String]
    init(_ nachrichten: [String]) { rest = nachrichten }
    func naechste() -> String? { rest.isEmpty ? nil : rest.removeFirst() }
}

struct TestVerbindung: WebSocketVerbindung {
    let folge: Folge
    let mitschnitt: Mitschnitt
    func sende(_ text: String) async throws { await mitschnitt.merke(text) }
    func empfange() async throws -> String {
        guard let text = await folge.naechste() else { throw Getrennt() }
        return text
    }
    func schliesse() {}
}

func fabrik(_ nachrichten: [String], _ mitschnitt: Mitschnitt) -> WebSocketFabrik {
    { _ in
        await mitschnitt.neueVerbindung()
        return TestVerbindung(folge: Folge(nachrichten), mitschnitt: mitschnitt)
    }
}

func testquelle(_ leser: any Nachrichtenleser, _ nachrichten: [String], _ mitschnitt: Mitschnitt,
                versuche: Int) -> WebSocketKursquelle {
    WebSocketKursquelle(id: "test", name: "Test", verzoegerung: .echtzeit, hoechstzahlSymbole: nil,
                        adresse: { _ in URL(string: "wss://example.invalid")! },
                        macheLeser: { _ in leser },
                        verbinde: fabrik(nachrichten, mitschnitt),
                        warte: { _ in }, jetzt: { empfangen }, hoechstversuche: versuche)
}

func sammle(_ strom: AsyncStream<Quellereignis>) async -> [Quellereignis] {
    var ereignisse: [Quellereignis] = []
    for await e in strom { ereignisse.append(e) }
    return ereignisse
}

let krakenNachricht = #"{"channel":"ticker","type":"update","data":[{"symbol":"BTC/EUR","bid":58000.1,"ask":58000.3,"last":58000.2}]}"#

@Test func quelleVerbindetNachAbbruchNeuUndAbonniertJedesMal() async {
    let mitschnitt = Mitschnitt()
    let quelle = testquelle(KrakenLeser(symbole: ["BTC/EUR"]), [krakenNachricht], mitschnitt, versuche: 2)
    let ereignisse = await sammle(quelle.beobachte(["BTC/EUR"]))
    let kurs = Kurs(symbol: "BTC/EUR", letzter: d("58000.2"), geld: d("58000.1"), brief: d("58000.3"),
                    zeit: empfangen, quelle: "kraken")
    let getrennt = Quellereignis.status(.getrennt(grund: String(describing: Getrennt())))
    let einmal: [Quellereignis] = [.status(.verbunden), .kurs(kurs), getrennt]
    #expect(ereignisse == einmal + einmal)
    let verbindungen = await mitschnitt.verbindungen
    #expect(verbindungen == 2)
    let gesendetAnzahl = await mitschnitt.gesendet.count
    #expect(gesendetAnzahl == 2)
}

@Test func endgueltigerFehlerOhneNeuenVersuch() async {
    let mitschnitt = Mitschnitt()
    let fehler = #"{"type":"error","message":"Failed to subscribe"}"#
    let quelle = testquelle(CoinbaseLeser(symbole: ["XYZ-EUR"]), [fehler], mitschnitt, versuche: 5)
    let ereignisse = await sammle(quelle.beobachte(["XYZ-EUR"]))
    #expect(ereignisse == [.status(.verbunden), .status(.beendet(grund: "Coinbase: Failed to subscribe"))])
    let verbindungen = await mitschnitt.verbindungen
    #expect(verbindungen == 1)
}

struct OhneSchluessel: AlpacaSchluesselquelle {
    func alpacaSchluessel() async throws -> AlpacaSchluessel? { nil }
}

@Test func alpacaOhneSchluesselVerbindetGarNicht() async {
    let mitschnitt = Mitschnitt()
    let quelle = Kursquellen.alpaca(schluessel: OhneSchluessel(), verbinde: fabrik([], mitschnitt))
    let ereignisse = await sammle(quelle.beobachte(["AAPL"]))
    #expect(ereignisse == [.status(.beendet(grund: "Schlüssel fehlt"))])
    let verbindungen = await mitschnitt.verbindungen
    #expect(verbindungen == 0)
}

@Test func pausenWachsenBisEineMinute() {
    let pausen = (1...8).map { WebSocketKursquelle.pause($0) }
    let erwartet: [Duration] = [2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) }
    #expect(pausen == erwartet)
}

@Test func fertigeQuellenTragenIhreGrenzen() {
    let verbinde = fabrik([], Mitschnitt())
    #expect(Kursquellen.alpaca(schluessel: OhneSchluessel(), verbinde: verbinde).hoechstzahlSymbole == 30)
    #expect(Kursquellen.kraken(verbinde: verbinde).id == "kraken")
    #expect(Kursquellen.coinbase(verbinde: verbinde).id == "coinbase")
    #expect(Kursquellen.binance(verbinde: verbinde).hoechstzahlSymbole == 1024)
}
