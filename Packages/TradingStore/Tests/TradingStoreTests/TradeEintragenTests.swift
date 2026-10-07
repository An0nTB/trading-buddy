import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

// Journal-Sicherung importieren und Trades von Hand speichern (Migration v11, Doc 02 Nr. 63). Erfundene Daten.

private let zeit = ISO8601DateFormatter().date(from: "2026-10-05T22:45:00Z")!
private let berlin = TimeZone(identifier: "Europe/Berlin")!

private func d(_ text: String) -> Decimal { Decimal(string: text)! }
private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Test func handtradeOhneKursbewegungBehaeltRisikoNachLaden() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.legeKontoAn(broker: "Von Hand", kontonummer: "Test", waehrung: "EUR")
    let hand = ManuellerTrade(symbol: "Testwert", einstieg: zeit, markterwartung: .buy,
                              groesse: 10, einstiegskurs: 100, ausstiegskurs: 100, stopKurs: 95, gebuehren: 2)
    let ticket = try journal.speichereHandtrade(hand, konto: konto)
    let position = try #require(try journal.geschlossenePositionen(konto: konto).first)
    let trade = Trade(position).mitGeplantemRisiko(100)
    #expect(trade.stopRisiko == 50)
    #expect(trade.rMultiple == d("-0.04"))
    #expect(!trade.risikoAngenommen)
    var bearbeitet = try #require(try journal.manuellerTrade(konto: konto, ticket: ticket))
    bearbeitet.stopKurs = 80
    try journal.speichereHandtrade(bearbeitet, konto: konto, ticket: ticket)
    let neu = try #require(try journal.geschlossenePositionen(konto: konto).first)
    #expect(Trade(neu).stopRisiko == 200)
    #expect(Trade(neu).rMultiple == d("-0.01"))
}

@Test func nurHandelsdatenAusFormularUndSicherungHabenBekanntenPunktwert() throws {
    let position = ClosedPosition(ticket: "42", rohzeile: [], side: .buy, lots: 10, symbol: "Testwert",
                                  openTime: zeit, openPrice: 100, stopLoss: 95, closeTime: zeit,
                                  closePrice: 100, commission: -2, swap: 0, profit: 0)
    // Derselbe Altbestand: Erst der gespeicherte Marker belegt die Abrechnung je Stück.
    let broker = try GeschlossenZeile(kontoId: 1, importlaufId: 1, position).modell()
    #expect(Trade(broker).stopRisiko == nil)
    let hand = try GeschlossenZeile(kontoId: 1, importlaufId: 1, position, markterwartung: .buy).modell()
    #expect(Trade(hand).stopRisiko == 50)
    #expect(Trade(hand).rMultiple == d("-0.04"))
}

private func beispielSicherung() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/JournalSicherung/"
            + "journal-sicherung-beispiel.json")
    return try Data(contentsOf: url)
}

/// Kleine Sicherung mit den Trades `t1` (Notiz frei wählbar), `t2` (Exit frei wählbar) und optional `t3`.
private func sicherung(notiz: String = "erste Notiz", exit2: String = "21", mitT3: Bool = false) -> Data {
    var trades = [
        #"{"id": "t1", "datum": "2026-09-01", "uhrzeit": "10:00", "asset": "Beispiel AG", "klasse": "Aktie", "#
            + #""richtung": "Long", "art": "direkt", "setup": "Ausbruch", "groesse": "10", "entry": "100", "#
            + #""exit": "105", "risiko": "25", "regel": true, "notiz": "\#(notiz)"}"#,
        #"{"id": "t2", "datum": "2026-09-02", "uhrzeit": "11:00", "asset": "KO Short Beispiel", "#
            + #""klasse": "Index", "richtung": "Short", "art": "schein", "groesse": "100", "entry": "2", "#
            + #""exit": "\#(exit2)", "regel": false}"#,
    ]
    if mitT3 {
        trades.append(#"{"id": "t3", "datum": "2026-09-03", "asset": "Muster SE", "richtung": "Long", "#
            + #""groesse": "1", "entry": "50", "exit": "49", "setup": "Neu im Browser"}"#)
    }
    return Data(#"{"trades": [\#(trades.joined(separator: ","))], "setups": ["Ausbruch"]}"#.utf8)
}

@Test func journalSicherungImportUebernimmtTradesJournalUndSetups() throws {
    let journal = try Journal.imSpeicher()
    let ergebnis = try journal.importiereJournalSicherung(datei: beispielSicherung(),
                                                          dateiname: "journal-sicherung-beispiel.json",
                                                          kontonummer: "Kollege", zeitzone: berlin, jetzt: zeit)
    #expect(ergebnis.status == .gespeichert)
    #expect(ergebnis.geschlosseneNeu == 8 && ergebnis.geschlosseneBekannt == 0)
    #expect(ergebnis.journaleintraegeNeu == 8 && ergebnis.setupsNeu == 3)
    #expect(ergebnis.ohneAusstieg == 1 && ergebnis.csv.hinweise == 2)

    let konto = try #require(try journal.konten().first)
    #expect(konto.broker == Journal.journalSicherungBroker && konto.kontonummer == "Kollege")
    #expect(konto.waehrung == "EUR")
    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.importer == Journal.journalSicherungImporter)
    #expect(try journal.importhinweise(importlauf: lauf).map(\.zeile) == [7, 9])

    let positionen = try journal.geschlossenePositionen(konto: konto)
    #expect(positionen.count == 8)
    #expect(positionen.allSatisfy { !$0.ausstiegszeitBekannt && $0.closeTime == $0.openTime })
    let schein = try #require(positionen.first { $0.ticket == "js-t1003" })
    #expect(schein.side == .buy && schein.profit == d("125"))
    let erwartung = try journal.markterwartungen(konto: konto)
    #expect(erwartung["js-t1003"] == .sell && erwartung["js-t1002"] == .sell && erwartung["js-t1001"] == .buy)
    #expect(erwartung.count == 8)

    let eintraege = try journal.journaleintraege(konto: konto)
    let erster = try #require(eintraege["js-t1001"])
    #expect(erster.setup == "Ausbruch" && erster.regeltreue == true && erster.grund == "erfundener Testtrade")
    #expect(erster.risikoEinstieg == d("50") && erster.geaendertAm == zeit && erster.zeiteinheit == "M15")
    #expect(eintraege["js-t1004"]?.risikoEinstieg == nil)
    #expect(eintraege["js-zeile-10"]?.regeltreue == nil)
    #expect(try journal.risikoquellen(konto: konto).wirksam(ticket: "js-t1011")
        == WirksamesRisiko(betrag: d("1.5"), herkunft: .trade))
    #expect(try journal.playbook().map(\.name) == ["Ausbruch", "Pullback", "Umkehr"])

    let nochmal = try journal.importiereJournalSicherung(datei: beispielSicherung(), dateiname: "kopie.json",
                                                         kontonummer: "Kollege", jetzt: zeit)
    #expect(nochmal.status == .dateiBereitsImportiert && nochmal.importlaufId == lauf.id)
}

@Test func journalSicherungImportNeuereSicherungErgaenztUndSchuetztHenry() throws {
    let journal = try Journal.imSpeicher()
    try journal.importiereJournalSicherung(datei: sicherung(), dateiname: "a.json", kontonummer: "K", jetzt: zeit)
    let konto = try #require(try journal.konten().first)
    var eintrag = try #require(try journal.journaleintraege(konto: konto)["js-t1"])
    eintrag.grund = "in Henry ergänzt"
    try journal.speichereJournal(eintrag)

    // Neuere Sicherung: Notiz im Browser geändert, ein Trade dazu. Positionen gleich, Henrys Eintrag bleibt.
    let ergebnis = try journal.importiereJournalSicherung(datei: sicherung(notiz: "im Browser geändert", mitT3: true),
                                                          dateiname: "b.json", kontonummer: "K", jetzt: zeit)
    #expect(ergebnis.geschlosseneNeu == 1 && ergebnis.geschlosseneBekannt == 2)
    #expect(ergebnis.journaleintraegeNeu == 1 && ergebnis.setupsNeu == 1)
    let eintraege = try journal.journaleintraege(konto: konto)
    #expect(eintraege["js-t1"]?.grund == "in Henry ergänzt")
    #expect(eintraege["js-t2"]?.regeltreue == false)
    #expect(eintraege["js-t3"]?.setup == "Neu im Browser")
    #expect(try journal.playbook().map(\.name) == ["Ausbruch", "Neu im Browser"])

    // Exit nachträglich geändert: Abbruch ohne Änderung.
    #expect(throws: SpeicherFehler.abweichenderDatensatz(tickets: ["js-t2"])) {
        try journal.importiereJournalSicherung(datei: sicherung(exit2: "2,5", mitT3: true), dateiname: "c.json",
                                               kontonummer: "K", jetzt: zeit)
    }
    #expect(try journal.importe(konto: konto).count == 2)
    #expect(try journal.geschlossenePositionen(konto: konto).first { $0.ticket == "js-t2" }?.closePrice == 21)

    // Konto in anderer Währung oder ohne Nummer.
    try journal.legeKontoAn(broker: Journal.journalSicherungBroker, kontonummer: "Dollar", waehrung: "USD")
    #expect(throws: SpeicherFehler.andereKontowaehrung(gespeichert: "USD", angegeben: "EUR")) {
        try journal.importiereJournalSicherung(datei: sicherung(notiz: "Dollar"), dateiname: "d.json",
                                               kontonummer: "Dollar")
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Kontonummer fehlt")) {
        try journal.importiereJournalSicherung(datei: sicherung(notiz: "x"), dateiname: "e.json", kontonummer: " ")
    }
    #expect(throws: JournalSicherungFehler.keineTradesListe) {
        try journal.importiereJournalSicherung(datei: Data(#"{"setups": []}"#.utf8), dateiname: "f.json",
                                               kontonummer: "K")
    }
}

@Test func journalAusV10BekommtAusstiegszeitBekannt() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("V11-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let pfad = dir.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v10 Risiko und Tags")
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (broker, kontonummer, kontoname, waehrung) VALUES ('Beispiel Broker', '7', 'Alt', 'EUR');
            INSERT INTO importlauf (kontoId, importer, importerVersion, dateiname, dateiHash, datei, art, stichtag,
                                    serverZeitzone, importiertAm)
                VALUES (1, 'MT4-Auszug', '0.1.0', 'a.html', 'abc', X'00', 'daily', '2026-01-02 10:00:00.000', 'UTC',
                        '2026-01-02 10:00:00.000');
            INSERT INTO geschlossenePosition (kontoId, importlaufId, ticket, rohzeile, side, lots, symbol, openTime,
                                              openPrice, closeTime, closePrice, commission, swap, profit, produktart)
                VALUES (1, 1, '42', '[]', 'buy', '1', 'EURUSD', '2026-01-02 09:00:00.000', '1.1',
                        '2026-01-02 09:30:00.000', '1.2', '0', '0', '10', 'cfd');
            """)
    }
    try alt.close()

    let journal = try Journal(pfad: pfad, jetzt: zeit, zeitzone: TimeZone(secondsFromGMT: 0)!)
    #expect(try journal.angewandteMigrationen().last == "v12 Offene Trades von Hand")
    let konto = try #require(try journal.konten().first)
    let position = try #require(try journal.geschlossenePositionen(konto: konto).first)
    #expect(position.ausstiegszeitBekannt && position.closeTime == utc("2026-01-02T09:30:00Z"))
    #expect(try journal.markterwartungen(konto: konto).isEmpty)
    #expect(try journal.manuelleTickets(konto: konto).isEmpty)
    #expect(try journal.manuellerTrade(konto: konto, ticket: "42") == nil)
}

@Test func manuellerTradeWirdGespeichertGelesenGeaendertUndGeloescht() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.legeKontoAn(broker: "Beispiel Broker", kontonummer: "Hand 1", waehrung: "eur")
    #expect(konto.waehrung == "EUR" && konto.kontoname == "Hand 1")
    #expect(try journal.legeKontoAn(broker: "Beispiel Broker", kontonummer: "Hand 1", waehrung: "EUR").id == konto.id)
    #expect(throws: SpeicherFehler.self) {
        try journal.legeKontoAn(broker: "Beispiel Broker", kontonummer: "Hand 2", waehrung: "Euro")
    }

    let schein = ManuellerTrade(symbol: " KO Short DAX ", einstieg: utc("2026-10-05T08:00:00Z"),
                                ausstieg: utc("2026-10-05T09:15:00Z"), markterwartung: .sell, schein: true,
                                groesse: 100, einstiegskurs: 2, ausstiegskurs: d("2.5"), risiko: 50, gebuehren: 1,
                                produktart: .derivat)
    let angaben = Journaleintrag(kontoId: 0, ticket: "", setup: "Umkehr", regeltreue: true,
                                 grund: "Plan eingehalten", risikoEinstieg: 50, zeiteinheit: "M5", geaendertAm: zeit)
    let p = try journal.speichereManuellenTrade(schein, konto: konto, eintrag: angaben, jetzt: zeit)
    #expect(p.ticket.hasPrefix("hand-") && p.symbol == "KO Short DAX")
    #expect(p.side == .buy && p.profit == 50 && p.commission == -1 && p.stopLoss == d("1.5"))
    #expect(p.ausstiegszeitBekannt)
    #expect(try journal.geschlossenePositionen(konto: konto) == [p])
    #expect(try journal.journaleintraege(konto: konto)[p.ticket]?.setup == "Umkehr")
    #expect(try journal.journaleintraege(konto: konto)[p.ticket]?.zeiteinheit == "M5")
    #expect(try journal.markterwartungen(konto: konto) == [p.ticket: .sell])
    #expect(try journal.manuelleTickets(konto: konto) == [p.ticket])
    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.importer == Journal.vonHandImporter && lauf.datei.isEmpty)

    // Wieder lesen ergibt dieselbe Position.
    var gelesen = try #require(try journal.manuellerTrade(konto: konto, ticket: p.ticket))
    #expect(gelesen.markterwartung == .sell && gelesen.schein && gelesen.gebuehren == 1)
    #expect(gelesen.stopKurs == d("1.5") && gelesen.ausstieg == utc("2026-10-05T09:15:00Z"))
    #expect(gelesen.position(ticket: p.ticket) == p)

    // Ändern ohne Ausstiegszeit: dieselbe Zeile, Eintrag bleibt, ein Importlauf.
    gelesen.ausstieg = nil
    gelesen.ausstiegskurs = d("1.8")
    let geaendert = try journal.speichereManuellenTrade(gelesen, konto: konto, ticket: p.ticket,
                                                        jetzt: zeit.addingTimeInterval(60))
    #expect(geaendert.profit == -20 && !geaendert.ausstiegszeitBekannt && geaendert.closeTime == geaendert.openTime)
    #expect(try journal.geschlossenePositionen(konto: konto) == [geaendert])
    #expect(try journal.journaleintraege(konto: konto)[p.ticket]?.grund == "Plan eingehalten")
    #expect(try journal.importe(konto: konto).map(\.stichtag) == [zeit.addingTimeInterval(60)])

    // Ein zweiter Trade, falsche Eingaben ändern nichts.
    let aktie = ManuellerTrade(symbol: "Muster SE", einstieg: utc("2026-10-02T12:30:00Z"), markterwartung: .buy,
                               groesse: 10, einstiegskurs: 80, ausstiegskurs: 82)
    let zweiter = try journal.speichereManuellenTrade(aktie, konto: konto, jetzt: zeit)
    #expect(zweiter.ticket != p.ticket && zweiter.stopLoss == nil)
    #expect(try journal.importe(konto: konto).count == 1)
    var leer = aktie
    leer.groesse = 0
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade unvollständig: groesseNichtPositiv")) {
        try journal.speichereManuellenTrade(leer, konto: konto, jetzt: zeit)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Risiko -1 muss größer als 0 sein")) {
        try journal.speichereManuellenTrade(aktie, konto: konto, eintrag: Journaleintrag(kontoId: 0, ticket: "",
                                                                                         risikoEinstieg: -1))
    }
    #expect(try journal.geschlossenePositionen(konto: konto).count == 2)

    // Importierte Trades bleiben unberührt.
    try journal.importiereJournalSicherung(datei: sicherung(), dateiname: "a.json", kontonummer: "Hand 1",
                                           broker: "Beispiel Broker", jetzt: zeit)
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade js-t1 stammt aus einem Import")) {
        try journal.speichereManuellenTrade(aktie, konto: konto, ticket: "js-t1", jetzt: zeit)
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade js-t1 stammt aus einem Import")) {
        try journal.loescheManuellenTrade(konto: konto, ticket: "js-t1")
    }
    #expect(try journal.manuellerTrade(konto: konto, ticket: "js-t1") == nil)

    // Löschen nimmt Eintrag, Tags und Bildverweise mit.
    try journal.setzeTags(["fomo"], konto: konto, ticket: p.ticket, jetzt: zeit)
    try journal.speichereBild(Bildverweis(datei: "2026-10/hand.png", bezug: .trade(p.ticket), erstellt: zeit),
                              konto: konto)
    #expect(try journal.loescheManuellenTrade(konto: konto, ticket: p.ticket) == ["2026-10/hand.png"])
    #expect(try journal.manuelleTickets(konto: konto) == [zweiter.ticket])
    #expect(try journal.journaleintraege(konto: konto)[p.ticket] == nil)
    #expect(try journal.tags(konto: konto)[p.ticket] == nil)
    #expect(try journal.bilder(trade: p.ticket, konto: konto).isEmpty)
    #expect(throws: SpeicherFehler.ungueltigerWert("Trade \(p.ticket) gibt es nicht")) {
        try journal.loescheManuellenTrade(konto: konto, ticket: p.ticket)
    }
}
