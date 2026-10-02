import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private func d(_ text: String) -> Decimal { Decimal(string: text)! }
private let jetzt = ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z")!

private func konto(_ journal: Journal, _ nummer: String = "100001") throws -> Konto {
    try journal.schreibe {
        try Journal.konto($0, broker: "GBE brokers Ltd.", nummer: nummer, name: "Test", waehrung: "EUR")
    }
}

/// Topstep-ähnlich 50K wie in den TradingCore-Tests; jedes Feld anders als die Vorgabe.
private let topstep = PropFirmRegeln(
    name: "Topstep 50K Combine", startkapital: 50000, zeitzone: "America/Chicago", tageswechselMinuten: 17 * 60,
    maxTagesverlust: 1000, maxGesamtverlust: 2000, gesamtverlustart: .nachgezogenTagesende,
    einfrierenBeiSaldo: 50000, gewinnziel: 3000, mindestHandelstage: 2, handelstagzaehlung: .gewinntag,
    mindestTagesgewinn: d("150.5"), konsistenzMaxAnteil: d("0.5"), konsistenzbezug: .summeGewinntage,
    keinHaltenUeberTageswechsel: true, keinHaltenUeberWochenende: true, maxLotsJeTrade: d("0.1"),
    stopPflicht: true)

@Test func ohneRegelnIstLeer() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    #expect(try journal.handelsregeln(konto: k) == Handelsregeln())
    #expect(try journal.handelsregeln(konto: k).leer)
}

@Test func eigeneRegelnKommenGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let regeln = Handelsregeln(maxTagesverlust: d("250.10"), maxTradesJeTag: 5, stoppNachVerlusten: 3,
                               maxRisikoJeTrade: d("0.1"))
    try journal.setzeHandelsregeln(regeln, konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == regeln)

    // Einzelne Regeln aus: nil bleibt nil.
    let weniger = Handelsregeln(maxTradesJeTag: 3)
    try journal.setzeHandelsregeln(weniger, konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == weniger)
}

@Test func propFirmRegelnKommenGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let regeln = Handelsregeln(maxTradesJeTag: 4, propFirm: topstep)
    try journal.setzeHandelsregeln(regeln, konto: k, jetzt: jetzt)
    let gelesen = try journal.handelsregeln(konto: k)
    #expect(gelesen == regeln)
    #expect(gelesen.propFirm?.mindestTagesgewinn == d("150.5"))

    // Mit Vorgaben (nur Name und Startkapital) ebenso.
    let ftmo = Handelsregeln(propFirm: PropFirmRegeln(name: "FTMO 2-Step 100K", startkapital: 100000))
    try journal.setzeHandelsregeln(ftmo, konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == ftmo)
}

@Test func regelnGeltenJeKonto() throws {
    let journal = try Journal.imSpeicher()
    let a = try konto(journal, "1")
    let b = try konto(journal, "2")
    try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 2), konto: a, jetzt: jetzt)
    try journal.setzeHandelsregeln(Handelsregeln(propFirm: topstep), konto: b, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: a) == Handelsregeln(maxTradesJeTag: 2))
    #expect(try journal.handelsregeln(konto: b) == Handelsregeln(propFirm: topstep))
}

@Test func leereRegelnEntfernenDieZeile() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.setzeHandelsregeln(Handelsregeln(maxTagesverlust: 100), konto: k, jetzt: jetzt)
    try journal.setzeHandelsregeln(Handelsregeln(), konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k).leer)
    #expect(try journal.lies { try RegelZeile.fetchCount($0) } == 0)
}

@Test func regelnVerschwindenMitDemKonto() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 2), konto: k, jetzt: jetzt)
    _ = try journal.schreibe { try Konto.deleteOne($0, key: k.id!) }
    #expect(try journal.lies { try RegelZeile.fetchCount($0) } == 0)
}

@Test func ungueltigeRegelnWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 2), konto: k, jetzt: jetzt)

    #expect(throws: SpeicherFehler.ungueltigerWert("Trades je Tag muss größer als 0 sein")) {
        try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 0), konto: k, jetzt: jetzt)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Höchster Tagesverlust muss größer als 0 sein")) {
        try journal.setzeHandelsregeln(Handelsregeln(maxTagesverlust: -50), konto: k, jetzt: jetzt)
    }
    var pf = topstep
    pf.name = "  "
    #expect(throws: SpeicherFehler.ungueltigerWert("Prop-Firm ohne Namen")) {
        try journal.setzeHandelsregeln(Handelsregeln(propFirm: pf), konto: k, jetzt: jetzt)
    }
    pf = topstep
    pf.zeitzone = "Europe/Nirgendwo"
    #expect(throws: SpeicherFehler.ungueltigerWert("Unbekannte Zeitzone Europe/Nirgendwo")) {
        try journal.setzeHandelsregeln(Handelsregeln(propFirm: pf), konto: k, jetzt: jetzt)
    }
    pf = topstep
    pf.tageswechselMinuten = 24 * 60
    #expect(throws: SpeicherFehler.ungueltigerWert("Tageswechsel 1440 Minuten liegt nicht im Tag")) {
        try journal.setzeHandelsregeln(Handelsregeln(propFirm: pf), konto: k, jetzt: jetzt)
    }
    pf = topstep
    pf.konsistenzMaxAnteil = d("1.5")
    #expect(throws: SpeicherFehler.ungueltigerWert("Konsistenzanteil 1.5 ist größer als 1")) {
        try journal.setzeHandelsregeln(Handelsregeln(propFirm: pf), konto: k, jetzt: jetzt)
    }
    pf = topstep
    pf.startkapital = 0
    #expect(throws: SpeicherFehler.ungueltigerWert("Startkapital muss größer als 0 sein")) {
        try journal.setzeHandelsregeln(Handelsregeln(propFirm: pf), konto: k, jetzt: jetzt)
    }

    var fremd = k
    fremd.id = 999
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 2), konto: fremd, jetzt: jetzt)
    }
    // Nichts davon hat die gespeicherten Regeln verändert.
    #expect(try journal.handelsregeln(konto: k) == Handelsregeln(maxTradesJeTag: 2))
}

@Test func unbekannteArtInDerDatenbankIstEinFehler() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.setzeHandelsregeln(Handelsregeln(propFirm: topstep), konto: k, jetzt: jetzt)
    try journal.schreibe { try $0.execute(sql: "UPDATE handelsregeln SET pfGesamtverlustart = 'intraday'") }
    #expect(throws: SpeicherFehler.unbekannterWert("intraday")) { try journal.handelsregeln(konto: k) }
}

@Test func v5WirdNachgeholtWennV6SchonDaIst() throws {
    // #53 (v6) kam vor #54 (v5) auf main: Eine Datenbank mit v6, aber ohne v5, muss v5 beim Öffnen nachholen.
    let ordner = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path
    do {
        let journal = try Journal(pfad: pfad)
        try journal.schreibe { db in
            try db.execute(sql: "DROP TABLE handelsregeln")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v5 Handelsregeln je Konto'")
        }
        #expect(try !journal.angewandteMigrationen().contains("v5 Handelsregeln je Konto"))
    }
    let journal = try Journal(pfad: pfad)
    #expect(try journal.angewandteMigrationen().contains("v5 Handelsregeln je Konto"))
    let k = try konto(journal)
    try journal.setzeHandelsregeln(Handelsregeln(maxTradesJeTag: 2), konto: k, jetzt: jetzt)
    #expect(try journal.handelsregeln(konto: k) == Handelsregeln(maxTradesJeTag: 2))
}
