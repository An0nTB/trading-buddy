import Foundation
import Testing
@testable import TradingCore

/// Befunde aus dem Codex-Gesamtreview vom 02.10.2026 (Kern). Sollwerte von Hand.
private func befundZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func befundTrade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, nurDatum: Bool = false) -> Trade {
    Trade(id: id, symbol: "DAX", side: .buy, lots: 1, openTime: befundZeit(auf), closeTime: befundZeit(zu),
          openPrice: 100, closePrice: 100, profit: netto, nurDatum: nurDatum)
}

@Test func befundXLSXKaputteZellen() {
    // Negativer Textindex, Zeilennummer außerhalb von Excel, überlange und zu große Spalte.
    let xml = """
    <worksheet><sheetData>\
    <row r="1"><c r="A1" t="s"><v>-1</v></c><c r="B1" t="s"><v>0</v></c><c r="C1" t="s"><v>5</v></c></row>\
    <row r="99999999999"><c r="ZZZZZZZZZZZZZZZZZZZZ2"><v>7</v></c><c r="XFE2"><v>8</v></c></row>\
    </sheetData></worksheet>
    """
    let zeilen = XLSXMappe.zeilen(Data(xml.utf8), texte: ["a"])
    #expect(zeilen == [["", "a", ""], ["7", "8"]])
    #expect(XLSXMappe.spaltenIndex("AA7") == 26)
    #expect(XLSXMappe.spaltenIndex("XFD1") == 16_383)
    #expect(XLSXMappe.spaltenIndex("XFE1") == nil)
    #expect(XLSXMappe.spaltenIndex("Ä1") == nil)
    #expect(XLSXMappe.spaltenIndex("AAAA1") == nil)
}

@Test func befundPositionsbildungJeWaehrung() throws {
    func a(_ id: String, tag: Double, _ seite: Side, _ menge: Decimal, _ betrag: Decimal, _ waehrung: String,
           nurDatum: Bool = false) -> Ausfuehrung {
        Ausfuehrung(id: id, zeit: Date(timeIntervalSince1970: tag * 86_400), nurDatum: nurDatum, kennung: "X",
                    name: "X", seite: seite, menge: menge, preis: abs(betrag / menge), betrag: betrag,
                    waehrung: waehrung)
    }
    let split = Kapitalmassnahme(id: "s", zeit: Date(timeIntervalSince1970: 2 * 86_400), art: .split,
                                 vorgang: "SPLIT", kennung: "X", menge: 20)
    let ergebnis = Positionsbildung.bilde([
        a("k1", tag: 0, .buy, 10, -100, "EUR", nurDatum: true),
        a("k2", tag: 1, .buy, 10, -110, "USD"),
        a("v1", tag: 3, .sell, 20, 120, "EUR"),
        a("v2", tag: 4, .sell, 25, 150, "USD"),
    ], kapitalmassnahmen: [split])
    // Split 2:1 über beide Währungen; EUR-Verkauf nur gegen EUR-Kauf, USD nur gegen USD.
    #expect(ergebnis.trades.map(\.id) == ["v1", "v2"])
    #expect(ergebnis.trades.map(\.lots) == [20, 20])
    #expect(ergebnis.trades.map(\.profit) == [20, 10])
    #expect(ergebnis.trades.map(\.nurDatum) == [true, false])
    let rest = try #require(ergebnis.ohneBestand.first)
    #expect(rest.menge == 5 && rest.betrag == 30 && rest.waehrung == "USD")
    #expect(ergebnis.offen.isEmpty)
}

@Test func befundOhneUhrzeitInAuswertungen() {
    let trades = [
        befundTrade("a", "2026-03-02T00:00:00Z", "2026-03-02T00:00:00Z", netto: 10, nurDatum: true),
        befundTrade("b", "2026-03-03T00:00:00Z", "2026-03-05T00:00:00Z", netto: 10, nurDatum: true),
        befundTrade("c", "2026-03-04T09:00:00Z", "2026-03-04T09:02:00Z", netto: -10),
        befundTrade("d", "2026-03-05T09:30:00Z", "2026-03-05T10:00:00Z", netto: -10),
    ]
    let utc = TimeZone(secondsFromGMT: 0)!
    let stunden = Kennzahlen.aufschluesseln(trades, nach: .stunde, zeitzone: utc)
    #expect(stunden.map(\.schluessel) == ["9", Gruppe.ohneUhrzeit])
    let dauer = Kennzahlen.aufschluesseln(trades, nach: .haltedauer, zeitzone: utc)
    #expect(dauer.map(\.schluessel).sorted() == [Gruppe.ohneUhrzeit, "unter1Stunde", "unter5Minuten"].sorted())
    let k = Kennzahlen(trades: trades)
    #expect(k.haltedauerGewinner == nil)
    #expect(k.haltedauerVerlierer == 960)
    let muster = MusterFinder.finde(trades, zeitzone: utc, aufteilungen: [.stunde], mindestanzahl: 1)
    #expect(muster.map(\.schluessel) == ["9"])
}

@Test func befundTagesverlustAusUebernachtPosition() {
    let trades = [
        befundTrade("O1", "2026-03-01T20:00:00Z", "2026-03-02T08:00:00Z", netto: -120),
        befundTrade("N1", "2026-03-02T09:00:00Z", "2026-03-02T09:30:00Z", netto: 5),
    ]
    let utc = TimeZone(secondsFromGMT: 0)!
    let regeln = Handelsregeln(maxTagesverlust: 100)
    let v = Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: utc)
    #expect(v.map { "\($0.trade) \($0.art.rawValue)" } == ["N1 tagesverlust"])
    let s = Regelpruefung.tagesstaende(trades, regeln: regeln, zeitzone: utc)
    #expect(s.map(\.trades) == [1, 1])
    #expect(s.map(\.netto) == [0, -115])
    #expect(s.map(\.verstoesse) == [0, 1])
}
