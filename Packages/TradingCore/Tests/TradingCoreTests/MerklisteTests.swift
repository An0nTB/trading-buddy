import Foundation
import Testing
@testable import TradingCore

/// Merkliste für Nachrichten (Doc 26, N-E3). Sollwerte von Hand (02.10.2026).
private func merkZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func merkTrade(_ symbol: String, geschlossen: String) -> Trade {
    let schluss = merkZeit(geschlossen)
    return Trade(id: symbol + geschlossen, symbol: symbol, side: .buy, lots: 1,
                 openTime: schluss.addingTimeInterval(-3_600), closeTime: schluss,
                 openPrice: 100, closePrice: 101, profit: 1)
}

@Test func merklisteArtSchaetzen() {
    #expect(Merkliste.art(fuer: "AAPL") == .symbol)
    #expect(Merkliste.art(fuer: "SAP.DE") == .symbol)
    #expect(Merkliste.art(fuer: "XAUUSD.r") == .symbol)
    #expect(Merkliste.art(fuer: "BTC/EUR") == .symbol)
    #expect(Merkliste.art(fuer: "DE40") == .symbol)
    #expect(Merkliste.art(fuer: "Apple Inc.") == .name)
    #expect(Merkliste.art(fuer: "Allianz") == .name)
    #expect(Merkliste.art(fuer: "US0378331005") == .isin)
    #expect(Merkliste.art(fuer: "DE0007164600") == .isin)
    // Falsche Prüfziffer: keine ISIN, aber symbolhaft.
    #expect(Merkliste.art(fuer: "DE0007164601") == .symbol)
    #expect(Merkliste.art(fuer: "") == .name)
}

@Test func merklisteISINPruefziffer() {
    #expect(Merkliste.istISIN("US0378331005"))
    #expect(Merkliste.istISIN("IE00B4L5Y983"))
    #expect(Merkliste.istISIN("DE000BASF111"))
    #expect(!Merkliste.istISIN("DE0007164601"))
    #expect(!Merkliste.istISIN("us0378331005"))
    #expect(!Merkliste.istISIN("US037833100"))
    #expect(!Merkliste.istISIN("US03783310055"))
    #expect(!Merkliste.istISIN("1S0378331005"))
}

@Test func merklisteneintragBereinigtUndCodable() throws {
    let zeit = merkZeit("2026-10-02T12:00:00Z")
    let e = Merklisteneintrag(id: "e1", begriff: "  Nvidia   Zölle ", erstellt: zeit)
    #expect(e.begriff == "Nvidia Zölle")
    #expect(e.anzeigename == "Nvidia Zölle")
    #expect(e.art == .name)
    #expect(e.herkunft == .vonHand && e.status == .aktiv)
    #expect(e.schluessel == "nvidia zölle")
    let stichwort = Merklisteneintrag(id: "e2", begriff: "Zinsen", art: .stichwort, anzeigename: "Leitzins",
                                      erstellt: zeit)
    #expect(stichwort.art == .stichwort && stichwort.anzeigename == "Leitzins")
    let daten = try JSONEncoder().encode([e, stichwort])
    #expect(try JSONDecoder().decode([Merklisteneintrag].self, from: daten) == [e, stichwort])
}

@Test func merklisteVorschlagAusJournal() {
    let jetzt = merkZeit("2026-10-02T12:00:00Z")
    let trades = [
        merkTrade("EURUSD", geschlossen: "2026-09-30T10:00:00Z"),
        merkTrade("DE40", geschlossen: "2026-09-25T10:00:00Z"),
        merkTrade("EURUSD", geschlossen: "2026-09-10T10:00:00Z"),
        // Vor der 30-Tage-Grenze (02.09.2026 12:00 UTC).
        merkTrade("Apple", geschlossen: "2026-08-01T10:00:00Z"),
        // Schon abgelehnt, andere Schreibweise.
        merkTrade("xauusd", geschlossen: "2026-09-28T10:00:00Z"),
        // Auch offen: zählt nur einmal, als offene Position.
        merkTrade("SAP.DE", geschlossen: "2026-09-20T10:00:00Z"),
        // Nach „jetzt“: nicht vorschlagen.
        merkTrade("GBPUSD", geschlossen: "2026-10-03T10:00:00Z"),
    ]
    let abgelehnt = Merklisteneintrag(id: "x", begriff: "XAUUSD", herkunft: .letzteTage, status: .abgelehnt,
                                      erstellt: jetzt)
    let v = Merkliste.vorschlag(trades: trades, offeneSymbole: ["SAP.DE", " BTC/EUR "], bestehend: [abgelehnt],
                                jetzt: jetzt)
    let begriffe: [String] = v.map(\.begriff)
    #expect(begriffe == ["BTC/EUR", "SAP.DE", "EURUSD", "DE40"])
    let herkunft: [Merklisteneintrag.Herkunft] = v.map(\.herkunft)
    #expect(herkunft == [.offenePosition, .offenePosition, .letzteTage, .letzteTage])
    #expect(v.filter { $0.status != .vorgeschlagen }.isEmpty)
    #expect(Merkliste.vorschlag(trades: trades, offeneSymbole: [], bestehend: v + [abgelehnt], jetzt: jetzt)
        .isEmpty)
}
