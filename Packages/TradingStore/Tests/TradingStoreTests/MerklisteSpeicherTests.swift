import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private let jetzt = ISO8601DateFormatter().date(from: "2026-10-02T08:00:00Z")!

@Test func merklisteKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    #expect(try journal.merkliste().isEmpty)
    let sap = Merklisteneintrag(id: "1", begriff: "SAP.DE", anzeigename: "SAP", herkunft: .offenePosition,
                                status: .vorgeschlagen, erstellt: jetzt)
    let stichwort = Merklisteneintrag(id: "2", begriff: "Nvidia Zölle", art: .stichwort, notiz: "nur US",
                                      erstellt: jetzt)
    let isin = Merklisteneintrag(id: "3", begriff: "DE0007164600", erstellt: jetzt)
    #expect(try journal.speichereMerklisteneintrag(sap) == sap)
    try journal.speichereMerklisteneintrag(stichwort)
    try journal.speichereMerklisteneintrag(isin)
    #expect(try journal.merkliste() == [isin, stichwort, sap])
    #expect(try journal.merkliste().first?.art == .isin)

    // Ersetzen über dieselbe ID: Vorschlag bestätigt.
    var bestaetigt = sap
    bestaetigt.status = .aktiv
    try journal.speichereMerklisteneintrag(bestaetigt)
    #expect(try journal.merkliste().first { $0.id == "1" }?.status == .aktiv)

    try journal.loescheMerklisteneintrag(id: "2")
    #expect(try journal.merkliste().map(\.id) == ["3", "1"])
}

@Test func merklisteSaeubertBegriffUndAnzeigename() throws {
    let journal = try Journal.imSpeicher()
    var e = Merklisteneintrag(id: "1", begriff: "AAPL", erstellt: jetzt)
    e.begriff = "  Apple   Inc. "
    e.anzeigename = " "
    let gespeichert = try journal.speichereMerklisteneintrag(e)
    #expect(gespeichert.begriff == "Apple Inc.")
    #expect(gespeichert.anzeigename == "Apple Inc.")
}

@Test func merklisteOhneDoppelteBegriffe() throws {
    let journal = try Journal.imSpeicher()
    try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "AAPL", status: .abgelehnt,
                                                             erstellt: jetzt))
    #expect(throws: SpeicherFehler.ungueltigerWert("„AAPL“ steht schon auf der Merkliste")) {
        try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "2", begriff: "aapl", erstellt: jetzt))
    }
    // Derselbe Eintrag darf seinen Begriff in der Schreibweise ändern.
    var gleich = Merklisteneintrag(id: "1", begriff: "aapl", status: .abgelehnt, erstellt: jetzt)
    gleich.art = .symbol
    try journal.speichereMerklisteneintrag(gleich)
    #expect(try journal.merkliste().map(\.begriff) == ["aapl"])
}

@Test func merklisteVorschlagUeberspringtAbgelehnte() throws {
    let journal = try Journal.imSpeicher()
    try journal.speichereMerklisteneintrag(Merklisteneintrag(begriff: "AAPL", status: .abgelehnt, erstellt: jetzt))
    let vorschlag = Merkliste.vorschlag(trades: [], offeneSymbole: ["aapl", "SAP.DE"],
                                        bestehend: try journal.merkliste(), jetzt: jetzt)
    #expect(vorschlag.map(\.begriff) == ["SAP.DE"])
    for v in vorschlag { try journal.speichereMerklisteneintrag(v) }
    #expect(try journal.merkliste().map(\.status) == [.abgelehnt, .vorgeschlagen])
}

@Test func ungueltigeMerklisteneintraegeWerdenAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    #expect(throws: SpeicherFehler.ungueltigerWert("Merklisteneintrag ohne Begriff")) {
        try journal.speichereMerklisteneintrag(Merklisteneintrag(begriff: "   ", erstellt: jetzt))
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Merklisteneintrag ohne ID")) {
        try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "", begriff: "AAPL", erstellt: jetzt))
    }
    try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "1", begriff: "AAPL", erstellt: jetzt))
    try journal.schreibe { try $0.execute(sql: "UPDATE merkliste SET status = 'pausiert'") }
    #expect(throws: SpeicherFehler.unbekannterWert("pausiert")) { try journal.merkliste() }
}
