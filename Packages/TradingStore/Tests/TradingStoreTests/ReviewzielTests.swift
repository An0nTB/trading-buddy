import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private let mai = (utc("2025-05-01T00:00:00Z"), utc("2025-06-01T00:00:00Z"))
private let juni = (utc("2025-06-01T00:00:00Z"), utc("2025-07-01T00:00:00Z"))
private let juli = (utc("2025-07-01T00:00:00Z"), utc("2025-08-01T00:00:00Z"))
private let erstellt = utc("2025-06-01T18:30:00Z")

private func konto(_ journal: Journal, _ nummer: String = "100001") throws -> Konto {
    try journal.schreibe {
        try Journal.konto($0, broker: "GBE brokers Ltd.", nummer: nummer, name: "Test", waehrung: "EUR")
    }
}

@Test func zielWirdAngelegtUndKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let ziel = try journal.legeZielAn(Reviewziel(text: "Höchstens 2 Revanche-Trades", von: juni.0, bis: juni.1,
                                                 messgroesse: "Revanche-Trades", zielwert: 2, erstellt: erstellt),
                                      konto: k)
    let id = try #require(ziel.id)
    #expect(ziel.status == .offen)
    #expect(ziel.ergebnis == nil)
    #expect(ziel.messgroesse == "Revanche-Trades")
    #expect(ziel.zielwert == 2)
    #expect(ziel.geaendert == erstellt)
    #expect(try journal.ziele(konto: k) == [ziel])
    #expect(try journal.ziele(konto: k).first?.id == id)
}

@Test func zielwertBleibtExakt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let wert = Decimal(string: "0.1")!
    try journal.legeZielAn(Reviewziel(text: "Verlust je Trade höchstens 0,1 R", von: juni.0, bis: juni.1,
                                      messgroesse: "R je Verlusttrade", zielwert: wert), konto: k)
    #expect(try journal.ziele(konto: k).first?.zielwert == wert)
}

@Test func zielWirdAbgehaktUndWiederGeoeffnet() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let ziel = try journal.legeZielAn(Reviewziel(text: "Kein Trade ohne Stop", von: juni.0, bis: juni.1,
                                                 erstellt: erstellt), konto: k)
    let id = try #require(ziel.id)
    let spaeter = utc("2025-07-02T08:00:00Z")
    try journal.setzeZielstatus(id: id, .verfehlt, ergebnis: "3 Trades ohne Stop", jetzt: spaeter)

    let abgehakt = try #require(try journal.ziele(konto: k).first)
    #expect(abgehakt.status == .verfehlt)
    #expect(abgehakt.ergebnis == "3 Trades ohne Stop")
    #expect(abgehakt.geaendert == spaeter)
    #expect(abgehakt.erstellt == erstellt)
    #expect(abgehakt.text == "Kein Trade ohne Stop")

    // Wieder öffnen ersetzt auch das Ergebnis.
    try journal.setzeZielstatus(id: id, .offen, jetzt: spaeter)
    let offen = try #require(try journal.ziele(konto: k).first)
    #expect(offen.status == .offen)
    #expect(offen.ergebnis == nil)
}

@Test func zieleNachKontoZeitraumUndStatus() throws {
    let journal = try Journal.imSpeicher()
    let a = try konto(journal, "100001")
    let b = try konto(journal, "100002")
    let imMai = try journal.legeZielAn(Reviewziel(text: "Mai", von: mai.0, bis: mai.1), konto: a)
    let imJuni = try journal.legeZielAn(Reviewziel(text: "Juni", von: juni.0, bis: juni.1), konto: a)
    try journal.legeZielAn(Reviewziel(text: "Juli", von: juli.0, bis: juli.1), konto: a)
    try journal.legeZielAn(Reviewziel(text: "anderes Konto", von: juni.0, bis: juni.1), konto: b)
    try journal.setzeZielstatus(id: try #require(imMai.id), .erreicht)

    #expect(try journal.ziele(konto: a).map(\.text) == ["Mai", "Juni", "Juli"])
    #expect(try journal.ziele(konto: b).map(\.text) == ["anderes Konto"])
    // Überschneidung mit Juni: Mai endet am 01.06. (ausschließlich), Juli beginnt am 01.07.
    #expect(try journal.ziele(konto: a, von: juni.0, bis: juni.1).map(\.text) == ["Juni"])
    // Ein einzelner Tag im Juni findet das Juni-Ziel.
    let tag = try journal.ziele(konto: a, von: utc("2025-06-15T00:00:00Z"), bis: utc("2025-06-16T00:00:00Z"))
    #expect(tag.map(\.id) == [imJuni.id])
    #expect(try journal.ziele(konto: a, status: .offen).map(\.text) == ["Juni", "Juli"])
    #expect(try journal.ziele(konto: a, von: juli.0).map(\.text) == ["Juli"])
}

@Test func ungueltigeZieleWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    #expect(throws: SpeicherFehler.ungueltigerWert("Ziel ohne Text")) {
        try journal.legeZielAn(Reviewziel(text: "  \n", von: juni.0, bis: juni.1), konto: k)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Zeitraum endet nicht nach seinem Beginn")) {
        try journal.legeZielAn(Reviewziel(text: "verkehrt", von: juni.1, bis: juni.0), konto: k)
    }
    var fremd = k
    fremd.id = 999
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.legeZielAn(Reviewziel(text: "fremdes Konto", von: juni.0, bis: juni.1), konto: fremd)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Neues Ziel hat schon die ID 5")) {
        try journal.legeZielAn(Reviewziel(id: 5, text: "mit ID", von: juni.0, bis: juni.1), konto: k)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Ziel 42 gibt es nicht")) {
        try journal.setzeZielstatus(id: 42, .erreicht)
    }
    #expect(try journal.ziele(konto: k).isEmpty)
}

@Test func zielWirdGeloescht() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    let bleibt = try journal.legeZielAn(Reviewziel(text: "bleibt", von: mai.0, bis: mai.1), konto: k)
    let weg = try journal.legeZielAn(Reviewziel(text: "weg", von: juni.0, bis: juni.1), konto: k)
    try journal.loescheZiel(id: try #require(weg.id))
    try journal.loescheZiel(id: 999)
    #expect(try journal.ziele(konto: k) == [bleibt])
}

@Test func unbekannterStatusInDerDatenbankFaelltAuf() throws {
    let journal = try Journal.imSpeicher()
    let k = try konto(journal)
    try journal.legeZielAn(Reviewziel(text: "Ziel", von: juni.0, bis: juni.1), konto: k)
    // Etwa eine andere App-Version mit einem Statuswort, das diese nicht kennt.
    try journal.schreibe { try $0.execute(sql: "UPDATE reviewziel SET status = 'vertagt'") }
    #expect(throws: SpeicherFehler.unbekannterWert("vertagt")) { try journal.ziele(konto: k) }
}
