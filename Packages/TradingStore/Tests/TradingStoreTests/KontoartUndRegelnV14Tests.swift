import Foundation
import GRDB
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

@Test func journalAusV13BehaeltDatenUndBekommtDieNeuenSpalten() throws {
    // Erfundener Stand wie nach v13: Konto, Regeln (v5), Setup-Karte mit Kriterium (v7), Trade mit Journaleintrag.
    let ordner = FileManager.default.temporaryDirectory.appendingPathComponent("V14-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v13 Eigenständige Hand-Trades")
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (id, broker, kontonummer, kontoname, waehrung, standardRisiko)
                VALUES (1, 'Beispiel Broker', '4711', 'Alt', 'EUR', '25');
            INSERT INTO handelsregeln (kontoId, maxTagesverlust, maxTradesJeTag, stoppNachVerlusten, maxRisikoJeTrade,
                                       geaendert)
                VALUES (1, '150.5', 4, 2, '30', '2026-06-01 08:00:00.000');
            INSERT INTO setup (id, name, stopRegel, status, statusSeit, standardRisiko)
                VALUES (1, 'Ausbruch', 'Unter dem Tief', 'aktiv', '2026-05-01 08:00:00.000', '20');
            INSERT INTO kriterium (setupId, kennung, text, position) VALUES (1, 'k1', 'Trend über EMA', 0);
            INSERT INTO importlauf (id, kontoId, importer, importerVersion, dateiname, dateiHash, datei,
                                    art, stichtag, serverZeitzone, importiertAm)
                VALUES (1, 1, 'MT4-Auszug', '0.1.0', 'a.html', 'v13-test', X'00', 'daily',
                        '2026-06-03 18:00:00.000', 'UTC', '2026-06-03 18:00:00.000');
            INSERT INTO geschlossenePosition (kontoId, importlaufId, ticket, rohzeile, side, lots, symbol, openTime,
                                              openPrice, closeTime, closePrice, commission, swap, profit, produktart)
                VALUES (1, 1, '42', '[]', 'buy', '1', 'EURUSD', '2026-06-03 09:00:00.000', '1.1',
                        '2026-06-03 09:30:00.000', '1.2', '0', '0', '10', 'cfd');
            INSERT INTO journal (kontoId, ticket, setup, regeltreue, geaendertAm, risikoEinstieg, zeiteinheit)
                VALUES (1, '42', 'Ausbruch', 1, '2026-06-03 10:00:00.000', '15', 'M15');
            """)
    }
    try alt.close()

    let journal = try Journal(pfad: pfad, jetzt: jetzt, zeitzone: TimeZone(secondsFromGMT: 0)!)
    #expect(try journal.angewandteMigrationen().last == "v14 Kontoart und Regeln je Setup")
    let k = try #require(try journal.konten().first)
    #expect(k.kontoname == "Alt" && k.kontonummer == "4711")
    #expect(k.kontoart == .echt)
    #expect(try journal.standardRisiko(konto: k) == 25)
    // Alte Regeln bleiben, die neuen Grenzen sind aus.
    #expect(try journal.handelsregeln(konto: k)
        == Handelsregeln(maxTagesverlust: d("150.5"), maxTradesJeTag: 4, stoppNachVerlusten: 2, maxRisikoJeTrade: 30))
    let karte = try #require(try journal.playbook().first)
    #expect(karte.name == "Ausbruch" && karte.status == .aktiv && karte.stopRegel == "Unter dem Tief")
    #expect(karte.kriterien == [Kriterium(id: "k1", text: "Trend über EMA")])
    #expect(karte.maxTradesJeTag == nil && karte.haltedauer == nil && karte.pruefungNachTrades == nil)
    #expect(try journal.standardRisikoJeSetup() == ["Ausbruch": 20])
    let position = try #require(try journal.geschlossenePositionen(konto: k).first)
    #expect(position.ticket == "42" && position.profit == 10)
    let eintrag = try #require(try journal.journaleintraege(konto: k)["42"])
    #expect(eintrag.setup == "Ausbruch" && eintrag.regeltreue == true && eintrag.risikoEinstieg == 15)
    #expect(eintrag.zeiteinheit == "M15")
    // Die neue Kontoart lässt sich am alten Konto setzen.
    #expect(try journal.setzeKontoart(.demo, konto: k).kontoart == .demo)
}
