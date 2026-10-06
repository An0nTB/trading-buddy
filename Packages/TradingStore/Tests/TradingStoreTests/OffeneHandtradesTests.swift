import Foundation
import Testing
import TradingCore
@testable import TradingStore

// Offene Trades von Hand (Migration v12): speichern, lesen, schließen, wieder öffnen, löschen. Erfundene Daten.

private let zeit = ISO8601DateFormatter().date(from: "2026-10-06T21:00:00Z")!
private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func offenerSchein() -> ManuellerTrade {
    ManuellerTrade(symbol: "KO Short Beispielindex", einstieg: utc("2026-10-06T08:00:00Z"), markterwartung: .sell,
                   schein: true, groesse: 100, einstiegskurs: 2, ausstiegskurs: nil, risiko: 50, gebuehren: 1,
                   produktart: .derivat)
}

@Test func offenerHandtradeWirdGespeichertUndGelesen() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.legeKontoAn(broker: "Von Hand", kontonummer: "Depot", waehrung: "EUR")
    let eintrag = Journaleintrag(kontoId: 0, ticket: "", setup: "Umkehr", risikoEinstieg: 50, geaendertAm: zeit)
    let ticket = try journal.speichereHandtrade(offenerSchein(), konto: konto, eintrag: eintrag, jetzt: zeit)
    #expect(ticket.hasPrefix("hand-"))
    #expect(try journal.geschlossenePositionen(konto: konto).isEmpty)
    #expect(try journal.offenePositionenLetzterAuszug(konto: konto) == nil)

    let offen = try journal.offeneManuelleTrades(konto: konto)
    #expect(offen.map(\.ticket) == [ticket])
    let gelesen = try #require(offen.first?.trade)
    #expect(gelesen.offen && gelesen.schein && gelesen.markterwartung == .sell)
    #expect(gelesen.stopKurs == Decimal(string: "1.5") && gelesen.gebuehren == 1)
    #expect(try journal.manuellerTrade(konto: konto, ticket: ticket) == gelesen)
    #expect(try journal.markterwartungen(konto: konto) == [ticket: .sell])
    #expect(try journal.journaleintraege(konto: konto)[ticket]?.setup == "Umkehr")
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade ist offen")) {
        try journal.speichereManuellenTrade(offenerSchein(), konto: konto, jetzt: zeit)
    }
}

@Test func schliessenErsetztDieOffeneZeileUndBehaeltDasJournal() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.legeKontoAn(broker: "Von Hand", kontonummer: "Depot", waehrung: "EUR")
    let eintrag = Journaleintrag(kontoId: 0, ticket: "", grund: "Idee", geaendertAm: zeit)
    let ticket = try journal.speichereHandtrade(offenerSchein(), konto: konto, eintrag: eintrag, jetzt: zeit)

    var geschlossen = try #require(try journal.manuellerTrade(konto: konto, ticket: ticket))
    geschlossen.ausstieg = utc("2026-10-06T10:00:00Z")
    geschlossen.ausstiegskurs = Decimal(string: "2.5")
    let p = try journal.speichereManuellenTrade(geschlossen, konto: konto, ticket: ticket, jetzt: zeit)
    #expect(p.ticket == ticket && p.profit == 50 && p.ausstiegszeitBekannt)
    #expect(try journal.offeneManuelleTrades(konto: konto).isEmpty)
    #expect(try journal.manuelleTickets(konto: konto) == [ticket])
    #expect(try journal.journaleintraege(konto: konto)[ticket]?.grund == "Idee")

    // Wieder öffnen: die geschlossene Zeile verschwindet.
    try journal.speichereHandtrade(offenerSchein(), konto: konto, ticket: ticket, jetzt: zeit)
    #expect(try journal.geschlossenePositionen(konto: konto).isEmpty)
    #expect(try journal.offeneManuelleTrades(konto: konto).map(\.ticket) == [ticket])
}

@Test func offenerHandtradeWirdGeloescht() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.legeKontoAn(broker: "Von Hand", kontonummer: "Depot", waehrung: "EUR")
    let eintrag = Journaleintrag(kontoId: 0, ticket: "", grund: "Idee", geaendertAm: zeit)
    let ticket = try journal.speichereHandtrade(offenerSchein(), konto: konto, eintrag: eintrag, jetzt: zeit)
    #expect(try journal.loescheManuellenTrade(konto: konto, ticket: ticket).isEmpty)
    #expect(try journal.offeneManuelleTrades(konto: konto).isEmpty)
    #expect(try journal.journaleintraege(konto: konto)[ticket] == nil)
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade \(ticket) gibt es nicht")) {
        try journal.loescheManuellenTrade(konto: konto, ticket: ticket)
    }
}
