import Foundation
import Testing
@testable import TradingCore

/// Erfundene Journal-Sicherung aus Fixtures/JournalSicherung, keine echten Konten oder Personen.
/// Sollwerte unabhängig vom Swift-Code von Hand und mit Python (decimal, zoneinfo) gerechnet (05.10.2026).
private func journalDaten(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

private func jsDez(_ text: String) -> Decimal { Decimal(string: text)! }

private func jsUTC(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: iso)!
}

private let journalBeispiel = "JournalSicherung/journal-sicherung-beispiel.json"

@Test func journalSicherungZahlenregel() {
    let z = JournalSicherung.zahl
    #expect(z("1.234,50") == .wert(jsDez("1234.5")))
    // Nur Punkt mit Dreiergruppen: deutsche Tausender wie in der Vorlage.
    #expect(z("18.872") == .wert(jsDez("18872")))
    #expect(z("148.20") == .wert(jsDez("148.2")))
    // Nur Komma: das letzte trennt die Dezimalen, auch bei drei Nachkommastellen.
    #expect(z("6,106") == .wert(jsDez("6.106")))
    // Folge der Vorlage, bewusst übernommen: Mit Punkt geschrieben ist derselbe Kurs 6106.
    #expect(z("6.106") == .wert(jsDez("6106")))
    #expect(z("1,234,50") == .wert(jsDez("1234.5")))
    #expect(z("1,234.50") == .wert(jsDez("1234.5")))
    // Abschließendes Trennzeichen wie in echten Sicherungen: parseFloat liest 3.
    #expect(z("3,") == .wert(jsDez("3")))
    #expect(z("3.") == .wert(jsDez("3")))
    #expect(z(" 100 €") == .wert(jsDez("100")))
    #expect(z("\u{00A0}1.000") == .wert(jsDez("1000")))
    #expect(z("-1.000") == .wert(jsDez("-1000")))
    #expect(z("-2,5") == .wert(jsDez("-2.5")))
    #expect(z("") == .leer)
    #expect(z("  ") == .leer)
    #expect(z("abc") == .ungueltig)
    #expect(z("12abc") == .ungueltig)
    #expect(z("1.2.3") == .ungueltig)
    #expect(z(",") == .ungueltig)
}

@Test func journalSicherungZahlfeldMitJSONZahl() {
    #expect(JournalSicherung.zahlfeld(20) == .wert(jsDez("20")))
    #expect(JournalSicherung.zahlfeld(150.35) == .wert(jsDez("150.35")))
    #expect(JournalSicherung.zahlfeld("150,35") == .wert(jsDez("150.35")))
    #expect(JournalSicherung.zahlfeld(nil) == .leer)
    #expect(JournalSicherung.zahlfeld(NSNull()) == .leer)
}

@Test func journalSicherungZeitpunkt() {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    // Winterzeit +01:00, Sommerzeit +02:00.
    #expect(JournalSicherung.zeitpunkt(datum: "2026-03-02", uhrzeit: "10:00", zeitzone: berlin)
            == jsUTC("2026-03-02T09:00:00Z"))
    #expect(JournalSicherung.zeitpunkt(datum: "2026-07-01", uhrzeit: "10:00", zeitzone: berlin)
            == jsUTC("2026-07-01T08:00:00Z"))
    #expect(JournalSicherung.zeitpunkt(datum: "2026-07-01", uhrzeit: "10:00:15", zeitzone: berlin)
            == jsUTC("2026-07-01T08:00:15Z"))
    #expect(JournalSicherung.zeitpunkt(datum: "2026-01-15", uhrzeit: "", zeitzone: berlin)
            == jsUTC("2026-01-14T23:00:00Z"))
    #expect(JournalSicherung.zeitpunkt(datum: "2026-02-30", uhrzeit: "10:00", zeitzone: berlin) == nil)
    #expect(JournalSicherung.zeitpunkt(datum: "2026-13-01", uhrzeit: "10:00", zeitzone: berlin) == nil)
    #expect(JournalSicherung.zeitpunkt(datum: "2026-03-02", uhrzeit: "25:00", zeitzone: berlin) == nil)
    #expect(JournalSicherung.zeitpunkt(datum: "", uhrzeit: "10:00", zeitzone: berlin) == nil)
}

@Test func journalSicherungBeispielPositionen() throws {
    let daten = try journalDaten(journalBeispiel)
    #expect(JournalSicherung.erkennt(daten))
    let s = try JournalSicherung.lies(daten)
    #expect(s.setups == ["Ausbruch", "Pullback", "Umkehr"])
    #expect(s.offen == 1)
    #expect(s.hinweise == [Importhinweis(zeile: 7, vorgang: "Muster SE", folge: .nichtVerbucht),
                           Importhinweis(zeile: 9, vorgang: "Beispiel AG 2026-03-03", folge: .nichtVerbucht)])
    let p = s.positionen
    #expect(p.map(\.ticket) == ["js-t1001", "js-t1002", "js-t1003", "js-t1004", "js-t1005", "js-t1008",
                                "js-zeile-10", "js-t1011"])
    #expect(p.map(\.symbol) == ["Beispiel AG", "DAX", "KO Short DAX", "Beispiel Welt ETF", "Beispielcoin",
                                "Beispiel AG", "Gold", "KO Long Beispiel AG"])
    // Short direkt dreht das Vorzeichen; der Short-Schein wird gekauft.
    #expect(p.map(\.side) == [.buy, .sell, .buy, .buy, .buy, .sell, .buy, .buy])
    let lots: [Decimal] = [10, 2, 500, 20, jsDez("0.4"), 10, 1, 3]
    #expect(p.map(\.lots) == lots)
    let einstieg: [Decimal] = [100, 18872, jsDez("1.2"), jsDez("148.2"), jsDez("1234.5"), 50, jsDez("2345.1"),
                               jsDez("6.106")]
    #expect(p.map(\.openPrice) == einstieg)
    let ausstieg: [Decimal] = [jsDez("112.5"), jsDez("18650.5"), jsDez("1.45"), jsDez("150.35"), jsDez("1180.25"),
                               jsDez("52.5"), jsDez("2360.6"), jsDez("6.52")]
    #expect(p.map(\.closePrice) == ausstieg)
    let ergebnis: [Decimal] = [125, 443, 125, 43, jsDez("-21.7"), -25, jsDez("15.5"), jsDez("1.24")]
    #expect(p.map(\.profit) == ergebnis)
    let stops: [Decimal?] = [95, nil, 1, nil, nil, 53, nil, jsDez("5.606")]
    #expect(p.map(\.stopLoss) == stops)
    #expect(p.allSatisfy { $0.takeProfit == nil && $0.commission == 0 && $0.swap == 0 })
    #expect(p.map(\.produktart) == [.aktie, .cfd, .derivat, .fonds, .krypto, .aktie, .cfd, .derivat])
    let zeiten = ["2026-03-02T09:00:00Z", "2026-07-01T08:00:00Z", "2026-07-02T13:30:00Z", "2026-01-14T23:00:00Z",
                  "2026-04-10T19:15:00Z", "2026-03-02T13:05:00Z", "2026-11-02T08:05:00Z", "2026-09-30T22:00:00Z"]
    #expect(p.map(\.openTime) == zeiten.map(jsUTC))
    // Ausstiegszeit kennt das Journal nicht.
    #expect(p.allSatisfy { $0.closeTime == $0.openTime && !$0.ausstiegszeitBekannt })
    let erste = try #require(p.first)
    #expect(erste.rohzeile.count == JournalSicherung.felder.count)
    #expect(erste.rohzeile[0] == "t1001")
    #expect(erste.rohzeile[10] == "100,00")
}

@Test func journalSicherungBeispielEintraege() throws {
    let s = try JournalSicherung.lies(try journalDaten(journalBeispiel))
    let e = s.eintraege
    #expect(e.count == s.positionen.count)
    #expect(e.map(\.ticket) == s.positionen.map(\.ticket))
    #expect(e.map(\.markterwartung) == [.buy, .sell, .sell, .buy, .buy, .sell, .buy, .buy])
    #expect(e.map(\.schein) == [false, false, true, false, false, false, false, true])
    #expect(e.map(\.regeltreue) == [true, false, true, true, false, false, nil, true])
    #expect(e.map(\.setup) == ["Ausbruch", "Umkehr", "Umkehr", "Pullback", nil, nil, "Pullback", "Ausbruch"])
    #expect(e.map(\.zeiteinheit) == ["M15", "H1", "M5", "D1", "H4", "M5", "H1", "M15"])
    // Risiko 0 (als JSON-Zahl) zählt wie leer.
    let risiko: [Decimal?] = [50, nil, 100, nil, nil, 30, nil, jsDez("1.5")]
    #expect(e.map(\.risiko) == risiko)
    #expect(e.map(\.klasse) == ["Aktie", "Index", "Index", "ETF", "Krypto", "Aktie", "Rohstoff", "Aktie"])
    #expect(e[0].notiz == "erfundener Testtrade")
    #expect(e[3].notiz == nil)
    #expect(e[0].link == nil)
    #expect(e[1].link == "https://example.org/chart/1")
}

@Test func journalSicherungTradeOhneZeitauswertung() throws {
    let s = try JournalSicherung.lies(try journalDaten(journalBeispiel))
    let trades = s.positionen.map { Trade($0) }
    #expect(trades.allSatisfy { $0.nurDatum })
    // R aus dem Journal-Risiko: Long 50 € Risiko, 125 € Gewinn; Short-Schein 100 € Risiko, 125 € Gewinn.
    #expect(trades[0].risk == 50)
    #expect(trades[0].rMultiple == jsDez("2.5"))
    #expect(trades[2].risk == 100)
    #expect(trades[5].risk == 30)
    #expect(trades[1].risk == nil)
}

@Test func journalSicherungLehntFremdeDateienAb() throws {
    let mt4 = try journalDaten("MT4/beispiel-2026-05-13-daily.html")
    let kraken = try journalDaten("Krypto/Kraken/kraken_einfach.csv")
    #expect(!JournalSicherung.erkennt(mt4))
    #expect(!JournalSicherung.erkennt(kraken))
    #expect(throws: JournalSicherungFehler.keinJSON) { try JournalSicherung.lies(mt4) }
    #expect(throws: JournalSicherungFehler.keinJSON) { try JournalSicherung.lies(kraken) }
    let liste = Data("[1, 2]".utf8)
    #expect(!JournalSicherung.erkennt(liste))
    #expect(throws: JournalSicherungFehler.keineTradesListe) { try JournalSicherung.lies(liste) }
    #expect(!JournalSicherung.erkennt(Data(#"{"trades": [{"foo": 1}]}"#.utf8)))
    #expect(!JournalSicherung.erkennt(Data(#"{"setups": []}"#.utf8)))
}

@Test func journalSicherungLeerUndMitBOM() throws {
    let leer = Data(#"{"trades": [], "setups": ["Ausbruch"]}"#.utf8)
    #expect(JournalSicherung.erkennt(leer))
    let s = try JournalSicherung.lies(leer)
    #expect(s.positionen.isEmpty && s.eintraege.isEmpty && s.hinweise.isEmpty)
    #expect(s.offen == 0)
    #expect(s.setups == ["Ausbruch"])
    let json = #"{"trades": [{"id": 17, "datum": "2026-03-02", "entry": "10", "exit": "11", "groesse": "1"}]}"#
    let mitBOM = Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)
    #expect(JournalSicherung.erkennt(mitBOM))
    let b = try JournalSicherung.lies(mitBOM)
    #expect(b.positionen.map(\.ticket) == ["js-17"])
    #expect(b.positionen.map(\.profit) == [1])
    // Leere Uhrzeit (hier fehlend): 00:00 in Berlin.
    #expect(b.positionen.map(\.openTime) == [jsUTC("2026-03-01T23:00:00Z")])
    #expect(b.positionen.map(\.produktart) == [.unbekannt])
    #expect(b.eintraege.map(\.regeltreue) == [nil])
}

@Test func journalSicherungProduktart() {
    #expect(JournalSicherung.produktart(klasse: " Aktie ") == .aktie)
    #expect(JournalSicherung.produktart(klasse: "Fonds") == .fonds)
    #expect(JournalSicherung.produktart(klasse: "crypto") == .krypto)
    #expect(JournalSicherung.produktart(klasse: "Devisen") == .cfd)
    #expect(JournalSicherung.produktart(klasse: "Anleihe") == .unbekannt)
    #expect(JournalSicherung.produktart(klasse: nil) == .unbekannt)
}

// MARK: - ManuellerTrade

private let handStart = jsUTC("2026-03-02T09:00:00Z")

private func handLong(stopKurs: Decimal? = nil, risiko: Decimal? = 50) -> ManuellerTrade {
    ManuellerTrade(symbol: "Beispiel AG", einstieg: handStart, markterwartung: .buy, groesse: 10,
                   einstiegskurs: 100, ausstiegskurs: jsDez("112.5"), stopKurs: stopKurs, risiko: risiko,
                   produktart: .aktie)
}

@Test func manuellerTradeStopAusRisiko() {
    let long = handLong()
    #expect(long.handelsseite == .buy)
    #expect(long.stop == 95)
    #expect(long.ergebnis == 125)
    let short = ManuellerTrade(symbol: "Beispiel AG", einstieg: handStart, markterwartung: .sell, groesse: 10,
                               einstiegskurs: 50, ausstiegskurs: jsDez("52.5"), risiko: 30)
    #expect(short.handelsseite == .sell)
    #expect(short.stop == 53)
    #expect(short.ergebnis == -25)
    // Short-Schein: gekauft, Stop unter dem Scheinpreis, Gewinn bei steigendem Scheinpreis.
    let schein = ManuellerTrade(symbol: "KO Short DAX", einstieg: handStart, markterwartung: .sell, schein: true,
                                groesse: 500, einstiegskurs: jsDez("1.2"), ausstiegskurs: jsDez("1.45"), risiko: 100)
    #expect(schein.handelsseite == .buy)
    #expect(schein.stop == 1)
    #expect(schein.ergebnis == 125)
    // Negatives Risiko zählt mit seinem Betrag.
    #expect(handLong(risiko: -50).stop == 95)
    #expect(handLong(risiko: 0).stop == nil)
    #expect(handLong(risiko: nil).stop == nil)
}

@Test func manuellerTradeStopKursHatVorrang() {
    #expect(handLong(stopKurs: 97, risiko: 50).stop == 97)
    #expect(handLong(stopKurs: 97, risiko: 50).position(ticket: "x").stopLoss == 97)
}

@Test func manuellerTradePruefung() {
    #expect(handLong().pruefe().isEmpty)
    var t = handLong()
    t.symbol = "  "
    t.groesse = 0
    #expect(t.pruefe() == [.symbolLeer, .groesseNichtPositiv])
    t = handLong(risiko: nil)
    t.einstiegskurs = 0
    #expect(t.pruefe() == [.kursNichtPositiv])
    t = handLong()
    t.ausstiegskurs = 0
    #expect(t.pruefe() == [.kursNichtPositiv])
    // Ausgeknockter Schein darf mit 0 schließen.
    t.schein = true
    #expect(t.pruefe().isEmpty)
    t = handLong()
    t.ausstieg = handStart.addingTimeInterval(-60)
    #expect(t.pruefe() == [.ausstiegVorEinstieg])
    #expect(handLong(stopKurs: 101).pruefe() == [.stopAufFalscherSeite])
    #expect(handLong(stopKurs: 100).pruefe() == [.stopAufFalscherSeite])
    var short = handLong(stopKurs: 49)
    short.markterwartung = .sell
    #expect(short.pruefe() == [.stopAufFalscherSeite])
    short.stopKurs = 103
    #expect(short.pruefe().isEmpty)
}

@Test func manuellerTradeOhneAusstiegszeit() {
    let p = handLong().position(ticket: "hand-1")
    #expect(p.ticket == "hand-1")
    #expect(p.rohzeile.isEmpty)
    #expect(!p.ausstiegszeitBekannt)
    #expect(p.closeTime == p.openTime)
    let trade = Trade(p)
    #expect(trade.nurDatum)
    #expect(trade.holdingTime == 0)
    var mitZeit = handLong()
    mitZeit.ausstieg = handStart.addingTimeInterval(3600)
    let q = mitZeit.position(ticket: "hand-2")
    #expect(q.ausstiegszeitBekannt)
    #expect(q.closeTime == jsUTC("2026-03-02T10:00:00Z"))
    #expect(!Trade(q).nurDatum)
    #expect(Trade(q).holdingTime == 3600)
}

@Test func manuellerTradeGebuehren() {
    var t = handLong()
    t.gebuehren = jsDez("2.5")
    let p = t.position(ticket: "hand-3")
    #expect(p.commission == jsDez("-2.5"))
    #expect(p.profit == 125)
    #expect(p.netProfit == jsDez("122.5"))
    #expect(Trade(p).netProfit == jsDez("122.5"))
    #expect(handLong().position(ticket: "hand-4").commission == 0)
}

@Test func manuellerTradeRundung() {
    let drittel = ManuellerTrade(symbol: "Beispiel AG", einstieg: handStart, markterwartung: .buy, groesse: 3,
                                 einstiegskurs: 10, ausstiegskurs: jsDez("10.3333"))
    #expect(drittel.ergebnis == 1)
    // −27,125 rundet vom Betrag weg auf −27,13 (Math.round im Journal ergäbe −27,12).
    let halb = ManuellerTrade(symbol: "Beispielcoin", einstieg: handStart, markterwartung: .buy,
                              groesse: jsDez("0.5"), einstiegskurs: jsDez("1234.5"), ausstiegskurs: jsDez("1180.25"))
    #expect(halb.ergebnis == jsDez("-27.13"))
}
