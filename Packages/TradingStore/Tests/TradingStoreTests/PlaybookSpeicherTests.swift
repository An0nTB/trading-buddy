import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private let seit = ISO8601DateFormatter().date(from: "2026-09-01T08:00:00Z")!
private let jetzt = ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z")!

private func konto(_ journal: Journal, _ nummer: String = "100001") throws -> Konto {
    try journal.schreibe {
        try Journal.konto($0, broker: "GBE brokers Ltd.", nummer: nummer, name: "Test", waehrung: "EUR")
    }
}

private let pullback = Setup(name: "Pullback", kriterien: [Kriterium(id: "k1", text: "Trend auf H1"),
                                                         Kriterium(id: "k2", text: "Rücklauf an EMA 20")],
                             stopRegel: "unter letztem Tief", zielRegel: "2 R", marktumfeld: "Trend",
                             notiz: "nur London", status: .aktiv, statusSeit: seit)

@Test func setupKarteKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let gespeichert = try journal.speichereSetup(pullback)
    let id = try #require(gespeichert.id)
    var erwartet = pullback
    erwartet.id = id
    #expect(gespeichert == erwartet)
    #expect(try journal.playbook() == [erwartet])

    // Ändern: Text umformuliert, Reihenfolge getauscht, ein Kriterium neu, Status gewechselt.
    var neu = gespeichert
    neu.kriterien = [Kriterium(id: "k2", text: "Rücklauf an die EMA 20"), Kriterium(id: "k1", text: "Trend auf H1"),
                     Kriterium(id: "k3", text: "Kein Termin in 30 Minuten")]
    neu.status = .pausiert
    neu.statusSeit = jetzt
    #expect(try journal.speichereSetup(neu) == neu)
    #expect(try journal.playbook() == [neu])
}

@Test func playbookIstNachNamenSortiert() throws {
    let journal = try Journal.imSpeicher()
    try journal.speichereSetup(Setup(name: "Range", statusSeit: seit))
    try journal.speichereSetup(pullback)
    try journal.speichereSetup(Setup(name: "Ausbruch", statusSeit: seit))
    #expect(try journal.playbook().map(\.name) == ["Ausbruch", "Pullback", "Range"])
    #expect(try journal.playbook().first?.status == .test)
}

@Test func umbenennenNimmtDieTradesMit() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    var karte = try journal.speichereSetup(pullback)
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1"]), konto: k, ticket: "1", jetzt: jetzt)
    try journal.setzeCheckliste(Checkliste(setup: "Ausbruch"), konto: k, ticket: "2", jetzt: jetzt)
    karte.name = "Pullback EMA"
    try journal.speichereSetup(karte)
    let listen = try journal.checklisten(konto: k)
    #expect(listen["1"] == Checkliste(setup: "Pullback EMA", erfuellt: ["k1"]))
    #expect(listen["2"] == Checkliste(setup: "Ausbruch"))
}

@Test func checklisteJeTradeUndKonto() throws {
    let journal = try Journal.imSpeicher()
    let a = try konto(journal, "1")
    let b = try konto(journal, "2")
    // Vorhandener Journaleintrag behält seine anderen Felder.
    try journal.speichereJournal(Journaleintrag(kontoId: a.id!, ticket: "88", regeltreue: true, zustand: 4,
                                                grund: "Plan", geaendertAm: seit))
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"]), konto: a, ticket: "88",
                                jetzt: jetzt)
    try journal.setzeCheckliste(Checkliste(setup: "Range", erfuellt: ["r1"]), konto: b, ticket: "88", jetzt: jetzt)

    #expect(try journal.checklisten(konto: a) == ["88": Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"])])
    #expect(try journal.checklisten(konto: b) == ["88": Checkliste(setup: "Range", erfuellt: ["r1"])])
    let eintrag = try #require(try journal.journaleintraege(konto: a)["88"])
    #expect(eintrag.setup == "Pullback")
    #expect(eintrag.regeltreue == true)
    #expect(eintrag.zustand == 4)
    #expect(eintrag.grund == "Plan")
    #expect(eintrag.geaendertAm == jetzt)

    // Ersetzen statt ergänzen.
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k2"]), konto: a, ticket: "88", jetzt: jetzt)
    #expect(try journal.checklisten(konto: a)["88"]?.erfuellt == ["k2"])
}

@Test func haekchenVerschwindenMitDemJournaleintrag() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1"]), konto: k, ticket: "1", jetzt: jetzt)
    try journal.loescheJournal(konto: k, ticket: "1")
    #expect(try journal.checklisten(konto: k).isEmpty)
    #expect(try journal.lies { try HakenZeile.fetchCount($0) } == 0)

    // Ohne Setup im Journal keine Checkliste, auch wenn der Eintrag bleibt.
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1"]), konto: k, ticket: "2", jetzt: jetzt)
    var eintrag = try #require(try journal.journaleintraege(konto: k)["2"])
    eintrag.setup = nil
    try journal.speichereJournal(eintrag)
    #expect(try journal.checklisten(konto: k).isEmpty)
}

@Test func loeschenDerKarteLaesstDieTradesStehen() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let karte = try journal.speichereSetup(pullback)
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1"]), konto: k, ticket: "1", jetzt: jetzt)
    try journal.loescheSetup(id: karte.id!)
    #expect(try journal.playbook().isEmpty)
    #expect(try journal.lies { try KriteriumZeile.fetchCount($0) } == 0)
    #expect(try journal.checklisten(konto: k)["1"] == Checkliste(setup: "Pullback", erfuellt: ["k1"]))
}

@Test func auswertungLiestAusDerDatenbank() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.speichereSetup(pullback)
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"]), konto: k, ticket: "1", jetzt: jetzt)
    try journal.setzeCheckliste(Checkliste(setup: "Pullback", erfuellt: ["k1"]), konto: k, ticket: "2", jetzt: jetzt)
    let trades = [
        Trade(id: "1", symbol: "EURUSD", side: .buy, lots: 1, openTime: seit, closeTime: jetzt, openPrice: 1,
              closePrice: 1, profit: 100),
        Trade(id: "2", symbol: "EURUSD", side: .buy, lots: 1, openTime: seit, closeTime: jetzt, openPrice: 1,
              closePrice: 1, profit: -40),
        Trade(id: "3", symbol: "EURUSD", side: .buy, lots: 1, openTime: seit, closeTime: jetzt, openPrice: 1,
              closePrice: 1, profit: 20),
    ]
    let direkt = PlaybookAuswertung(trades: trades, playbook: [pullback],
                                    checklisten: ["1": Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"]),
                                                  "2": Checkliste(setup: "Pullback", erfuellt: ["k1"])])
    let gespeichert = PlaybookAuswertung(trades: trades, playbook: try journal.playbook(),
                                         checklisten: try journal.checklisten(konto: k))
    #expect(gespeichert == direkt)
    #expect(gespeichert.setups.first?.vollstaendig.anzahl == 1)
    #expect(gespeichert.ohneSetup.anzahl == 1)
}

@Test func ungueltigeSetupsWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let karte = try journal.speichereSetup(pullback)

    #expect(throws: SpeicherFehler.ungueltigerWert("Setup „Pullback“ gibt es schon")) {
        try journal.speichereSetup(Setup(name: "Pullback", statusSeit: seit))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Setup ohne Namen")) {
        try journal.speichereSetup(Setup(name: "  ", statusSeit: seit))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Setup-Name „Range “ beginnt oder endet mit Leerraum")) {
        try journal.speichereSetup(Setup(name: "Range ", statusSeit: seit))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Kriterium doppelt in „Range“")) {
        try journal.speichereSetup(Setup(name: "Range", kriterien: [Kriterium(id: "a", text: "x"),
                                                                     Kriterium(id: "a", text: "y")]))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Kriterium ohne Text in „Range“")) {
        try journal.speichereSetup(Setup(name: "Range", kriterien: [Kriterium(id: "a", text: " ")]))
    }
    var fremd = karte
    fremd.id = 999
    fremd.name = "Neu"
    #expect(throws: SpeicherFehler.ungueltigerWert("Setup 999 gibt es nicht")) {
        try journal.speichereSetup(fremd)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Checkliste ohne Setup")) {
        try journal.setzeCheckliste(Checkliste(setup: ""), konto: k, ticket: "1", jetzt: jetzt)
    }
    var ohneKonto = k
    ohneKonto.id = 999
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.setzeCheckliste(Checkliste(setup: "Pullback"), konto: ohneKonto, ticket: "1", jetzt: jetzt)
    }
    #expect(try journal.playbook() == [karte])
    #expect(try journal.checklisten(konto: k).isEmpty)
}

@Test func unbekannterStatusInDerDatenbankIstEinFehler() throws {
    let journal = try Journal.imSpeicher()
    try journal.speichereSetup(pullback)
    try journal.schreibe { try $0.execute(sql: "UPDATE setup SET status = 'archiviert'") }
    #expect(throws: SpeicherFehler.unbekannterWert("archiviert")) { try journal.playbook() }
}
