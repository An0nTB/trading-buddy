import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private func zeit(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func tag(_ text: String) -> Journaltag { Journaltag(text)! }

private func konto(_ journal: Journal, _ nummer: String = "100001") throws -> Konto {
    try journal.schreibe {
        try Journal.konto($0, broker: "GBE brokers Ltd.", nummer: nummer, name: "Test", waehrung: "EUR")
    }
}

@Test func tagesnotizKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    #expect(try journal.tagesnotiz(tag("2026-10-02")) == nil)
    let notiz = Tagesnotiz(tag: tag("2026-10-02"), plan: "DAX: nur Long über 24.000", rueckblick: "",
                           verfassung: 4, erstellt: zeit("2026-10-02T06:30:00Z"))
    let gespeichert = try journal.speichereTagesnotiz(notiz, jetzt: zeit("2026-10-02T06:31:00Z"))
    var erwartet = notiz
    erwartet.planErstellt = zeit("2026-10-02T06:31:00Z")
    erwartet.geaendert = zeit("2026-10-02T06:31:00Z")
    #expect(gespeichert == erwartet)
    #expect(try journal.tagesnotiz(tag("2026-10-02")) == erwartet)
}

@Test func planZeitpunktBleibtBeimAendern() throws {
    let journal = try Journal.imSpeicher()
    let morgens = zeit("2026-10-02T06:30:00Z")
    let abends = zeit("2026-10-02T18:00:00Z")
    var notiz = Tagesnotiz(tag: tag("2026-10-02"), plan: "nur Long", erstellt: morgens)
    try journal.speichereTagesnotiz(notiz, jetzt: morgens)

    // Abends Plan korrigiert und Rückblick ergänzt: Plan zählt weiter als „vor dem Handel“.
    notiz.plan = "nur Long, kein Handel vor 9:30"
    notiz.planErstellt = abends
    notiz.rueckblick = "Regel gehalten"
    let spaeter = try #require(try journal.speichereTagesnotiz(notiz, jetzt: abends))
    #expect(spaeter.planErstellt == morgens)
    #expect(spaeter.erstellt == morgens)
    #expect(spaeter.geaendert == abends)
    #expect(spaeter.hatPlan(vor: zeit("2026-10-02T07:00:00Z")))

    // Plan gelöscht und abends neu geschrieben: dann zählt der neue Zeitpunkt.
    notiz.plan = ""
    #expect(try journal.speichereTagesnotiz(notiz, jetzt: abends)?.planErstellt == nil)
    notiz.plan = "nachträglich"
    notiz.planErstellt = nil
    let neu = try #require(try journal.speichereTagesnotiz(notiz, jetzt: abends))
    #expect(neu.planErstellt == abends)
    #expect(!neu.hatPlan(vor: zeit("2026-10-02T07:00:00Z")))
}

@Test func leereTagesnotizWirdEntfernt() throws {
    let journal = try Journal.imSpeicher()
    let t = zeit("2026-10-02T06:30:00Z")
    try journal.speichereTagesnotiz(Tagesnotiz(tag: tag("2026-10-02"), rueckblick: "x", erstellt: t), jetzt: t)
    #expect(try journal.speichereTagesnotiz(Tagesnotiz(tag: tag("2026-10-02"), plan: "  \n", erstellt: t),
                                            jetzt: t) == nil)
    #expect(try journal.tagesnotiz(tag("2026-10-02")) == nil)
    #expect(try journal.lies { try TagesnotizZeile.fetchCount($0) } == 0)
}

@Test func tagesnotizenImZeitraumSortiert() throws {
    let journal = try Journal.imSpeicher()
    let t = zeit("2026-10-02T06:30:00Z")
    for text in ["2026-10-05", "2026-09-30", "2026-10-01", "2026-10-31", "2026-11-01"] {
        try journal.speichereTagesnotiz(Tagesnotiz(tag: tag(text), rueckblick: text, erstellt: t), jetzt: t)
    }
    let oktober = try journal.tagesnotizen(von: tag("2026-10-01"), bis: tag("2026-10-31"))
    #expect(oktober.map(\.tag.description) == ["2026-10-01", "2026-10-05", "2026-10-31"])
}

@Test func tagesnotizMitPlanwirkung() throws {
    let journal = try Journal.imSpeicher()
    let t = zeit("2026-10-02T06:00:00Z")
    try journal.speichereTagesnotiz(Tagesnotiz(tag: tag("2026-10-02"), plan: "Plan", erstellt: t), jetzt: t)
    let trade = Trade(id: "1", symbol: "DAX", side: .buy, lots: 1, openTime: zeit("2026-10-02T08:00:00Z"),
                      closeTime: zeit("2026-10-02T09:00:00Z"), openPrice: 24000, closePrice: 24010, profit: 10)
    let notizen = try journal.tagesnotizen(von: tag("2026-10-01"), bis: tag("2026-10-31"))
    let wirkung = Planwirkung(trades: [trade], notizen: notizen, zeitzone: TimeZone(identifier: "Europe/Berlin")!)
    #expect(wirkung.tageMitPlan == 1)
    #expect(wirkung.tageOhnePlan == 0)
}

@Test func ungueltigeVerfassungWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let t = zeit("2026-10-02T06:30:00Z")
    #expect(throws: SpeicherFehler.ungueltigerWert("Verfassung 6 liegt nicht zwischen 1 und 5")) {
        try journal.speichereTagesnotiz(Tagesnotiz(tag: tag("2026-10-02"), verfassung: 6, erstellt: t), jetzt: t)
    }
    #expect(try journal.tagesnotiz(tag("2026-10-02")) == nil)
}

@Test func verpassteTradesKommenGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let a = VerpassterTrade(id: "a", zeit: zeit("2026-10-02T09:15:00Z"), symbol: "DAX", seite: .buy,
                            setup: "Pullback", grund: .zoegern, notiz: "Angst nach Verlust", ergebnisR: Decimal(string: "2.5"))
    let b = VerpassterTrade(id: "b", zeit: zeit("2026-10-02T08:00:00Z"), symbol: "EURUSD", seite: .sell,
                            setup: "  ", grund: .regelSperre)
    let c = VerpassterTrade(id: "c", zeit: zeit("2026-10-03T08:00:00Z"), symbol: "DAX", seite: .buy,
                            grund: .zuSpaet)
    for v in [a, b, c] { try journal.speichereVerpasstenTrade(v) }

    var bOhneSetup = b
    bOhneSetup.setup = nil
    let amTag = try journal.verpassteTrades(von: zeit("2026-10-02T00:00:00Z"), bis: zeit("2026-10-03T00:00:00Z"))
    #expect(amTag == [bOhneSetup, a])
    #expect(amTag.first { $0.id == "a" }?.ergebnisR == Decimal(string: "2.5"))

    // Ersetzen über dieselbe ID.
    var geaendert = a
    geaendert.grund = .nichtAmPlatz
    try journal.speichereVerpasstenTrade(geaendert)
    let auswertung = VerpassteAuswertung(try journal.verpassteTrades(von: .distantPast, bis: .distantFuture))
    #expect(auswertung.anzahl == 3)
    #expect(auswertung.gewollt == 1)
    #expect(auswertung.jeSetup == ["Pullback": 1])

    try journal.loescheVerpasstenTrade(id: "c")
    #expect(try journal.verpassteTrades(von: .distantPast, bis: .distantFuture).map(\.id) == ["b", "a"])
}

@Test func ungueltigeVerpassteTradesWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let t = zeit("2026-10-02T09:15:00Z")
    #expect(throws: SpeicherFehler.ungueltigerWert("Verpasster Trade ohne Symbol")) {
        try journal.speichereVerpasstenTrade(VerpassterTrade(zeit: t, symbol: " ", seite: .buy, grund: .zoegern))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Verpasster Trade ohne ID")) {
        try journal.speichereVerpasstenTrade(VerpassterTrade(id: "", zeit: t, symbol: "DAX", seite: .buy,
                                                             grund: .zoegern))
    }
    try journal.speichereVerpasstenTrade(VerpassterTrade(id: "x", zeit: t, symbol: "DAX", seite: .buy, grund: .zoegern))
    try journal.schreibe { try $0.execute(sql: "UPDATE verpassterTrade SET grund = 'langeweile'") }
    #expect(throws: SpeicherFehler.unbekannterWert("langeweile")) {
        try journal.verpassteTrades(von: .distantPast, bis: .distantFuture)
    }
}

@Test func bilderJeBezug() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let anderes = try konto(journal, "2")
    let t = zeit("2026-10-02T10:00:00Z")
    try journal.speichereVerpasstenTrade(VerpassterTrade(id: "v1", zeit: t, symbol: "DAX", seite: .buy, grund: .zuSpaet))

    let einstieg = Bildverweis(datei: "2026-10/a.png", bezug: .trade("4711"), beschriftung: "Einstieg", erstellt: t)
    let ausstieg = Bildverweis(datei: "2026-10/b.PNG", bezug: .trade("4711"), erstellt: t.addingTimeInterval(60))
    let morgen = Bildverweis(datei: "2026-10/c.heic", bezug: .tag(tag("2026-10-02")), erstellt: t)
    let verpasst = Bildverweis(datei: "2026-10/d.jpg", bezug: .verpassterTrade("v1"), erstellt: t)
    try journal.speichereBild(ausstieg, konto: k)
    try journal.speichereBild(einstieg, konto: k)
    try journal.speichereBild(morgen)
    try journal.speichereBild(verpasst)

    #expect(try journal.bilder(trade: "4711", konto: k) == [einstieg, ausstieg])
    #expect(try journal.bilder(trade: "4711", konto: anderes).isEmpty)
    #expect(try journal.bilder(tag: tag("2026-10-02")) == [morgen])
    #expect(try journal.bilder(verpassterTrade: "v1") == [verpasst])
    #expect(try journal.bilddateien() == ["2026-10/a.png", "2026-10/b.PNG", "2026-10/c.heic", "2026-10/d.jpg"])

    // Neue Beschriftung über dieselbe Datei.
    var neu = einstieg
    neu.beschriftung = "Einstieg am Hoch"
    try journal.speichereBild(neu, konto: k)
    #expect(try journal.bilder(trade: "4711", konto: k).first == neu)

    try journal.loescheBild(datei: "2026-10/c.heic")
    #expect(try journal.bilder(tag: tag("2026-10-02")).isEmpty)
}

@Test func bildverweiseVerschwindenMitBezug() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let t = zeit("2026-10-02T10:00:00Z")
    try journal.speichereVerpasstenTrade(VerpassterTrade(id: "v1", zeit: t, symbol: "DAX", seite: .buy, grund: .zuSpaet))
    try journal.speichereBild(Bildverweis(datei: "a.png", bezug: .verpassterTrade("v1"), erstellt: t))
    try journal.speichereBild(Bildverweis(datei: "b.png", bezug: .trade("1"), erstellt: t), konto: k)
    try journal.speichereBild(Bildverweis(datei: "c.png", bezug: .tag(tag("2026-10-02")), erstellt: t))

    try journal.loescheVerpasstenTrade(id: "v1")
    _ = try journal.schreibe { try Konto.deleteOne($0, key: k.id!) }
    #expect(try journal.bilddateien() == ["c.png"])
}

@Test func ungueltigeBildverweiseWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let t = zeit("2026-10-02T10:00:00Z")
    for pfad in ["/Users/tim/a.png", "../a.png", "a/../../b.png", "a.pdf", "~/a.png", ""] {
        #expect(throws: SpeicherFehler.ungueltigerWert("Kein gültiger Bildpfad: \(pfad)")) {
            try journal.speichereBild(Bildverweis(datei: pfad, bezug: .tag(tag("2026-10-02")), erstellt: t))
        }
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Bild zum Trade 1 ohne Konto")) {
        try journal.speichereBild(Bildverweis(datei: "a.png", bezug: .trade("1"), erstellt: t))
    }
    var fremd = k
    fremd.id = 999
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.speichereBild(Bildverweis(datei: "a.png", bezug: .trade("1"), erstellt: t), konto: fremd)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Verpassten Trade v9 gibt es nicht")) {
        try journal.speichereBild(Bildverweis(datei: "a.png", bezug: .verpassterTrade("v9"), erstellt: t))
    }
    #expect(try journal.bilddateien().isEmpty)
}
