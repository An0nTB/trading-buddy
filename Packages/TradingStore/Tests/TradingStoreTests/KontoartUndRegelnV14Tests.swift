import Foundation
import Testing
import TradingCore
@testable import TradingStore

// Migration v14 (Tims Auftrag 17.10.2026, E1 bis E7): Kontoart, Prozent- und Monatsgrenzen, offene Positionen,
// Kontostand als Bezug, Grenzen der Setup-Karte.
private func d(_ text: String) -> Decimal { Decimal(string: text)! }
private let jetzt = ISO8601DateFormatter().date(from: "2026-10-17T08:00:00Z")!

private func konto(_ journal: Journal, _ nummer: String = "100001") throws -> Konto {
    try journal.schreibe {
        try Journal.konto($0, broker: "XTB", nummer: nummer, name: "Demo", waehrung: "EUR")
    }
}

@Test func neuesKontoIstEchtgeldUndLaesstSichAufDemoStellen() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    #expect(k.kontoart == .echt)
    let demo = try journal.setzeKontoart(.demo, konto: k)
    #expect(demo.kontoart == .demo)
    #expect(try journal.konten().first?.kontoart == .demo)
    #expect(try journal.setzeKontoart(.echt, konto: demo).kontoart == .echt)
    var fremd = k
    fremd.id = 999
    #expect(throws: SpeicherFehler.self) { try journal.setzeKontoart(.demo, konto: fremd) }
}

@Test func neueRegelnKommenGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let regeln = Handelsregeln(maxTradesJeTag: 6, maxTagesverlustProzent: d("1.5"), maxRisikoJeTradeProzent: d("0.5"),
                               maxMonatsverlust: 120, maxMonatsverlustProzent: 6, maxOffenePositionen: 3,
                               maxOffenesRisiko: d("80.5"), maxOffenesRisikoProzent: 6,
                               kontostand: Kontostandbezug(betrag: 1200, seit: jetzt))
    try journal.setzeHandelsregeln(regeln, konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == regeln)
}

@Test func kontostandAllein() throws {
    // Ein Kontostand ohne Regel bleibt gespeichert, zählt aber nicht als Regel.
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let nurStand = Handelsregeln(kontostand: Kontostandbezug(betrag: 1200, seit: jetzt))
    try journal.setzeHandelsregeln(nurStand, konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == nurStand)
    #expect(try journal.handelsregeln(konto: k).leer)
    try journal.setzeHandelsregeln(Handelsregeln(), konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == Handelsregeln())
}

@Test func ungueltigeNeueGrenzenWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let falsch = [Handelsregeln(maxTagesverlustProzent: 0), Handelsregeln(maxRisikoJeTradeProzent: 101),
                  Handelsregeln(maxMonatsverlust: -1), Handelsregeln(maxOffenePositionen: 0),
                  Handelsregeln(kontostand: Kontostandbezug(betrag: 0, seit: jetzt))]
    for r in falsch {
        #expect(throws: SpeicherFehler.self) { try journal.setzeHandelsregeln(r, konto: k, jetzt: jetzt) }
    }
}

@Test func setupGrenzenKommenGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let karte = Setup(name: "Day-DE", status: .test, statusSeit: jetzt, maxTradesJeTag: 3, haltedauer: .gleicherTag,
                      pruefungNachTrades: 50)
    let gespeichert = try journal.speichereSetup(karte)
    #expect(gespeichert.maxTradesJeTag == 3)
    #expect(gespeichert.haltedauer == .gleicherTag)
    #expect(gespeichert.pruefungNachTrades == 50)
    // Ändern auf „kein Wochenende“ und Grenzen aus.
    var geaendert = gespeichert
    geaendert.haltedauer = .keinWochenende
    geaendert.maxTradesJeTag = nil
    try journal.speichereSetup(geaendert)
    let gelesen = try #require(try journal.playbook().first)
    #expect(gelesen.haltedauer == .keinWochenende)
    #expect(gelesen.maxTradesJeTag == nil)
    #expect(gelesen.pruefungNachTrades == 50)
    #expect(throws: SpeicherFehler.self) { try journal.speichereSetup(Setup(name: "X", maxTradesJeTag: 0)) }
    #expect(throws: SpeicherFehler.self) { try journal.speichereSetup(Setup(name: "Y", pruefungNachTrades: -5)) }
}
