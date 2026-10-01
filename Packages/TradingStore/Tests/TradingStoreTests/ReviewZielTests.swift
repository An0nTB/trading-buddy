import Foundation
import GRDB
import Testing
@testable import TradingStore

private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private let mai = (utc("2025-05-01T00:00:00Z"), utc("2025-06-01T00:00:00Z"))
private let juni = (utc("2025-06-01T00:00:00Z"), utc("2025-07-01T00:00:00Z"))
private let juli = (utc("2025-07-01T00:00:00Z"), utc("2025-08-01T00:00:00Z"))
private let angelegt = utc("2025-06-01T18:30:00Z")

private func mitKonto() throws -> (Journal, Konto) {
    let journal = try Journal.imSpeicher()
    let konto = try journal.schreibe {
        try Journal.konto($0, broker: "GBE brokers Ltd.", nummer: "100001", name: "Test", waehrung: "EUR")
    }
    return (journal, konto)
}

@Test func zielWirdAngelegtUndKommtGleichZurueck() throws {
    let (journal, konto) = try mitKonto()
    let ziel = try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: juni.0, bis: juni.1,
                                                 text: "Höchstens 2 Trades nach einem Verlust",
                                                 angelegtAm: angelegt))
    let id = try #require(ziel.id)
    #expect(ziel.status == .offen)
    #expect(ziel.ergebnis == nil)
    #expect(ziel.geaendertAm == angelegt)
    #expect(try journal.reviewZiele() == [ziel])
    #expect(try journal.reviewZiele().first?.id == id)
}

@Test func zielWirdAbgehaktUndWiederGeoeffnet() throws {
    let (journal, konto) = try mitKonto()
    let ziel = try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: juni.0, bis: juni.1,
                                                 text: "Kein Trade ohne Stop", angelegtAm: angelegt))
    let id = try #require(ziel.id)
    let spaeter = utc("2025-07-02T08:00:00Z")
    try journal.setzeZielstatus(id: id, .verfehlt, ergebnis: "3 Trades ohne Stop", jetzt: spaeter)

    let abgehakt = try #require(try journal.reviewZiele().first)
    #expect(abgehakt.status == .verfehlt)
    #expect(abgehakt.ergebnis == "3 Trades ohne Stop")
    #expect(abgehakt.geaendertAm == spaeter)
    #expect(abgehakt.angelegtAm == angelegt)
    #expect(abgehakt.text == "Kein Trade ohne Stop")

    // Wieder öffnen ersetzt auch das Ergebnis.
    try journal.setzeZielstatus(id: id, .offen, jetzt: spaeter)
    let offen = try #require(try journal.reviewZiele().first)
    #expect(offen.status == .offen)
    #expect(offen.ergebnis == nil)
}

@Test func zieleNachZeitraumUndStatus() throws {
    let (journal, konto) = try mitKonto()
    let imMai = try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: mai.0, bis: mai.1, text: "Mai"))
    let imJuni = try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: juni.0, bis: juni.1, text: "Juni"))
    // Ohne Konto: gilt für alle Konten.
    let imJuli = try journal.legeZielAn(ReviewZiel(von: juli.0, bis: juli.1, text: "Juli"))
    try journal.setzeZielstatus(id: try #require(imMai.id), .erreicht)

    #expect(try journal.reviewZiele().map(\.text) == ["Mai", "Juni", "Juli"])
    // Überschneidung mit Juni: Mai endet am 01.06. (ausschließlich), Juli beginnt am 01.07.
    #expect(try journal.reviewZiele(von: juni.0, bis: juni.1).map(\.text) == ["Juni"])
    // Ein einzelner Tag im Juni findet das Juni-Ziel.
    #expect(try journal.reviewZiele(von: utc("2025-06-15T00:00:00Z"), bis: utc("2025-06-16T00:00:00Z"))
            .map(\.id) == [imJuni.id])
    #expect(try journal.reviewZiele(status: .offen).map(\.text) == ["Juni", "Juli"])
    #expect(try journal.reviewZiele(von: juli.0).map(\.kontoId) == [nil])
    #expect(imJuli.kontoId == nil)
}

@Test func ungueltigeZieleWerdenAbgelehnt() throws {
    let (journal, konto) = try mitKonto()
    #expect(throws: SpeicherFehler.ungueltigerWert("Ziel ohne Text")) {
        try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: juni.0, bis: juni.1, text: "  \n"))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Zeitraum endet nicht nach seinem Beginn")) {
        try journal.legeZielAn(ReviewZiel(kontoId: konto.id, von: juni.1, bis: juni.0, text: "verkehrt"))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.legeZielAn(ReviewZiel(kontoId: 999, von: juni.0, bis: juni.1, text: "fremdes Konto"))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Neues Ziel hat schon die ID 5")) {
        try journal.legeZielAn(ReviewZiel(id: 5, von: juni.0, bis: juni.1, text: "mit ID"))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Ziel 42 gibt es nicht")) {
        try journal.setzeZielstatus(id: 42, .erreicht)
    }
    #expect(try journal.reviewZiele().isEmpty)
}

@Test func zielWirdGeloescht() throws {
    let (journal, _) = try mitKonto()
    let bleibt = try journal.legeZielAn(ReviewZiel(von: mai.0, bis: mai.1, text: "bleibt"))
    let weg = try journal.legeZielAn(ReviewZiel(von: juni.0, bis: juni.1, text: "weg"))
    try journal.loescheZiel(id: try #require(weg.id))
    try journal.loescheZiel(id: 999)
    #expect(try journal.reviewZiele() == [bleibt])
}

@Test func unbekannterStatusInDerDatenbankFaelltAuf() throws {
    let (journal, _) = try mitKonto()
    try journal.legeZielAn(ReviewZiel(von: juni.0, bis: juni.1, text: "Ziel"))
    // Etwa eine ältere oder neuere App-Version mit anderem Statuswort.
    try journal.schreibe { try $0.execute(sql: "UPDATE reviewZiel SET status = 'vertagt'") }
    #expect(throws: SpeicherFehler.unbekannterWert("vertagt")) { try journal.reviewZiele() }
}
