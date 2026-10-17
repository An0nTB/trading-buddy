import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

private let utcZone = TimeZone(secondsFromGMT: 0)!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
private func zahl(_ text: String) -> Decimal { Decimal(string: text)! }

private func mt4Datei(ticket: String = "51819669") throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-06-03-daily.html")
    return Data(try String(contentsOf: url, encoding: .utf8)
        .replacingOccurrences(of: "51819669", with: ticket).utf8)
}

@discardableResult
private func importiereMT4(_ journal: Journal, ticket: String = "51819669") throws -> ImportErgebnis {
    try journal.importiereMT4(datei: mt4Datei(ticket: ticket), dateiname: "beispiel.html", serverZeitzone: utcZone)
}

private func brokerkonto(_ journal: Journal) throws -> Konto {
    try journal.legeKontoAn(broker: "Beispiel Broker Ltd.", kontonummer: "12345678", waehrung: "EUR")
}

private func handtrade() -> ManuellerTrade {
    ManuellerTrade(symbol: "EURaud", einstieg: zeit("2026-06-03T16:00:00Z"),
                   ausstieg: zeit("2026-06-03T16:30:00Z"), markterwartung: .sell,
                   groesse: zahl("0.01"), einstiegskurs: zahl("1.78989"), ausstiegskurs: zahl("1.78838"))
}

private func csv(name: String = "SAP", waehrung: String = "EUR", nurDatum: Bool = false) -> Data {
    let kaufzeit = nurDatum ? "00:00:00" : "09:00:00"
    let verkaufzeit = nurDatum ? "00:00:00" : "14:00:00"
    return Data("""
        datetime;account_type;category;type;name;symbol;shares;price;amount;fee;tax;currency;description;transaction_id
        2026-06-03T\(kaufzeit)Z;DEFAULT;TRADING;BUY;\(name);DE000SYN0001;2;100;-200;0;0;\(waehrung);Kauf;kauf-1
        2026-06-04T\(verkaufzeit)Z;DEFAULT;TRADING;SELL;\(name);DE000SYN0001;-2;110;220;0;0;\(waehrung);Verkauf;verkauf-1
        """.utf8)
}

@discardableResult
private func importiereCSV(_ journal: Journal, name: String = "SAP", waehrung: String = "EUR",
                           nurDatum: Bool = false) throws -> Konto {
    try journal.importiereCSV(datei: csv(name: name, waehrung: waehrung, nurDatum: nurDatum),
                              dateiname: "beispiel.csv", kontonummer: "Depot")
    return try #require(try journal.konten().first { $0.broker == "Trade Republic" })
}

private func csvHandtrade(symbol: String = "SAP", richtung: Side = .buy, schein: Bool = false) -> ManuellerTrade {
    ManuellerTrade(symbol: symbol, einstieg: zeit("2026-06-03T12:00:00Z"),
                   ausstieg: zeit("2026-06-04T15:00:00Z"), markterwartung: richtung, schein: schein,
                   groesse: 2, einstiegskurs: 100, ausstiegskurs: 110)
}

@Test(arguments: [true, false])
func handtradeDuplikatWirdInBeidenReihenfolgenErkannt(handZuerst: Bool) throws {
    let journal = try Journal.imSpeicher()
    let konto = try brokerkonto(journal)
    if !handZuerst { try importiereMT4(journal) }
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    if handZuerst { try importiereMT4(journal) }

    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate == [hand.ticket: ["51819669"]])
    #expect(Set(bestand.trades.map(\.id)) == [hand.ticket, "51819669"])
    #expect(bestand.auswertbareTrades.map(\.id) == ["51819669"])
    #expect(bestand.auswertbareTrades.map(\.netProfit).reduce(0, +) == zahl("0.80"))
    #expect(try journal.geschlossenePositionen(konto: konto).count == 2)
    #expect(try journal.manuellerTrade(konto: konto, ticket: hand.ticket) != nil)
}

@Test(arguments: ["symbol", "richtung", "menge", "eroeffnungstag", "schlusstag", "einstiegskurs", "ausstiegskurs"])
func handtradeDuplikatBrauchtAlleVergleichsmerkmale(abweichung: String) throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    switch abweichung {
    case "symbol": hand.symbol = "EURUSD"
    case "richtung": hand.markterwartung = .buy
    case "menge": hand.groesse = zahl("0.02")
    case "eroeffnungstag": hand.einstieg = zeit("2026-06-02T16:00:00Z")
    case "schlusstag": hand.ausstieg = zeit("2026-06-04T16:30:00Z")
    case "einstiegskurs": hand.einstiegskurs += zahl("0.001")
    case "ausstiegskurs": hand.ausstiegskurs! += zahl("0.001")
    default: Issue.record("Unbekannte Abweichung")
    }
    try journal.speichereManuellenTrade(hand, konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatBleibtAufSeinKontoBegrenzt() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let anderes = try journal.legeKontoAn(broker: "Beispiel Broker Ltd.", kontonummer: "anderes", waehrung: "EUR")
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: anderes)
    let bestand = try journal.tradeBestand(konto: anderes, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.map(\.id) == [hand.ticket])
}

@Test(arguments: ["  sap  ", "SaP", "SYN   AG"])
func handtradeDuplikatNormalisiertSymbol(symbol: String) throws {
    let journal = try Journal.imSpeicher()
    let konto = try importiereCSV(journal, name: symbol.contains("SYN") ? "SYN AG" : "SAP")
    let hand = try journal.speichereManuellenTrade(csvHandtrade(symbol: symbol), konto: konto)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate
        == [hand.ticket: ["verkauf-1"]])
}

@Test(arguments: ["0.0001", "-0.0001"])
func handtradeDuplikatErlaubtKleineKursabweichung(abweichung: String) throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    hand.einstiegskurs += zahl(abweichung)
    hand.ausstiegskurs! += zahl(abweichung)
    let position = try journal.speichereManuellenTrade(hand, konto: konto)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate
        == [position.ticket: ["51819669"]])
}

@Test func handtradeDuplikatOhneBekannteSchliessungWirdNichtGeraten() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    hand.ausstieg = nil
    try journal.speichereManuellenTrade(hand, konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatIgnoriertOffeneHandtrades() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    hand.ausstieg = nil
    hand.ausstiegskurs = nil
    let ticket = try journal.speichereHandtrade(hand, konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.trades.map(\.id) == ["51819669"])
    #expect(try journal.offeneManuelleTrades(konto: konto).map(\.ticket) == [ticket])
}

@Test func handtradeDuplikatZeigtAlleKandidatenSortiertOhneZusammenlegung() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal, ticket: "900")
    try importiereMT4(journal, ticket: "100")
    let konto = try brokerkonto(journal)
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate == [hand.ticket: ["100", "900"]])
    #expect(bestand.trades.count == 3)
    #expect(Set(bestand.auswertbareTrades.map(\.id)) == ["100", "900"])
}

@Test func handtradeDuplikatPrueftNichtZweiHandtradesGegeneinander() throws {
    let journal = try Journal.imSpeicher()
    let konto = try brokerkonto(journal)
    try journal.speichereManuellenTrade(handtrade(), konto: konto)
    try journal.speichereManuellenTrade(handtrade(), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatBehaltenUeberstehtNeuesJournalUndWiederimport() throws {
    let ordner = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/Duplikate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path
    let journal = try Journal(pfad: pfad)
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    try journal.behalteHandtrade(konto: konto, ticket: hand.ticket)

    let neu = try Journal(pfad: pfad)
    try importiereMT4(neu)
    try importiereMT4(neu, ticket: "900")
    let bestand = try neu.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 3)
    #expect(bestand.auswertbareTrades.contains { $0.id == hand.ticket })
}

@Test func handtradeDuplikatBearbeitenHebtBestaetigungAuf() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    try journal.behalteHandtrade(konto: konto, ticket: hand.ticket)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate.isEmpty)
    var geaendert = handtrade()
    geaendert.gebuehren = 1
    try journal.speichereManuellenTrade(geaendert, konto: konto, ticket: hand.ticket)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate == [hand.ticket: ["51819669"]])
    #expect(bestand.auswertbareTrades.count == 1)
}

@Test func handtradeDuplikatLoeschenLaesstBrokertradeUnveraendert() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    let vorher = try journal.geschlossenePositionen(konto: konto)
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    try journal.behalteHandtrade(konto: konto, ticket: hand.ticket)
    try journal.loescheManuellenTrade(konto: konto, ticket: hand.ticket)
    #expect(try journal.geschlossenePositionen(konto: konto) == vorher)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate.isEmpty)
    // Auch bei Wiederverwendung des Tickets darf keine alte Bestätigung übrig bleiben.
    try journal.speichereManuellenTrade(handtrade(), konto: konto, ticket: hand.ticket)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate
        == [hand.ticket: ["51819669"]])
}

@Test(arguments: ["51819669", "fehlt", "offen"])
func handtradeDuplikatBehaltenLehntFremdeUndFehlendeTradesAb(ticket: String) throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    hand.ausstieg = nil
    hand.ausstiegskurs = nil
    try journal.speichereHandtrade(hand, konto: konto, ticket: "offen")
    #expect(throws: SpeicherFehler.self) {
        try journal.behalteHandtrade(konto: konto, ticket: ticket)
    }
}

@Test func handtradeDuplikatCSVVergleichtBasiswertUndMarktrichtung() throws {
    let journal = try Journal.imSpeicher()
    let konto = try importiereCSV(journal, name: "Nasdaq 100 Short 25000 Turbo Open End")
    let hand = try journal.speichereManuellenTrade(
        csvHandtrade(symbol: "nasdaq  100", richtung: .sell, schein: true), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.trades.allSatisfy { $0.richtung == .sell })
    #expect(bestand.moeglicheDuplikate == [hand.ticket: ["verkauf-1"]])
    #expect(bestand.auswertbareTrades.map(\.id) == ["verkauf-1"])
}

@Test func handtradeDuplikatCSVInAndererWaehrungBleibtEigenstaendig() throws {
    let journal = try Journal.imSpeicher()
    let konto = try importiereCSV(journal, waehrung: "USD")
    #expect(konto.waehrung == "EUR")
    try journal.speichereManuellenTrade(csvHandtrade(), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatCSVNurDatumBleibtInWestlicherZeitzoneAmBuchungstag() throws {
    let journal = try Journal.imSpeicher()
    let konto = try importiereCSV(journal, nurDatum: true)
    let hand = try journal.speichereManuellenTrade(csvHandtrade(), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: TimeZone(identifier: "America/New_York")!)
    #expect(bestand.moeglicheDuplikate == [hand.ticket: ["verkauf-1"]])
}

@Test func handtradeDuplikatZeitpunkteVerwendenDenKalendertagDesNutzers() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    var hand = handtrade()
    hand.ausstieg = zeit("2026-06-03T23:30:00Z")
    let position = try journal.speichereManuellenTrade(hand, konto: konto)
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate
        == [position.ticket: ["51819669"]])
    #expect(try journal.tradeBestand(konto: konto, zeitzone: TimeZone(identifier: "Europe/Berlin")!)
        .moeglicheDuplikate.isEmpty)
}

@Test(arguments: [true, false])
func handtradeDuplikatKurstoleranzHatEineEngeGrenze(aufGrenze: Bool) throws {
    let journal = try Journal.imSpeicher()
    let konto = try importiereCSV(journal)
    var hand = csvHandtrade()
    hand.einstiegskurs = zahl(aufGrenze ? "99.99" : "99.9899")
    let position = try journal.speichereManuellenTrade(hand, konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    if aufGrenze {
        #expect(bestand.moeglicheDuplikate == [position.ticket: ["verkauf-1"]])
    } else {
        #expect(bestand.moeglicheDuplikate.isEmpty)
        #expect(bestand.auswertbareTrades.count == 2)
    }
}

@Test func handtradeDuplikatBrauchtAuchBeimBrokerEineBekannteSchliessung() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    try journal.schreibe { db in
        try db.execute(sql: "UPDATE geschlossenePosition SET ausstiegszeitBekannt = 0 WHERE ticket = '51819669'")
    }
    try journal.speichereManuellenTrade(handtrade(), konto: konto)
    let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
    #expect(bestand.moeglicheDuplikate.isEmpty)
    #expect(bestand.auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatKontoloeschenEntferntAuchBestaetigungen() throws {
    let journal = try Journal.imSpeicher()
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    let hand = try journal.speichereManuellenTrade(handtrade(), konto: konto)
    try journal.behalteHandtrade(konto: konto, ticket: hand.ticket)
    try journal.loescheKonto(konto)
    #expect(try journal.konten().isEmpty)
    #expect(try journal.lies { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM handtradeEigenstaendig") } == 0)
    try importiereMT4(journal)
    let neu = try brokerkonto(journal)
    try journal.speichereManuellenTrade(handtrade(), konto: neu, ticket: hand.ticket)
    #expect(try journal.tradeBestand(konto: neu, zeitzone: utcZone).moeglicheDuplikate
        == [hand.ticket: ["51819669"]])
}

@Test func handtradeDuplikatMigrationPrueftAuchDenAltbestand() throws {
    let ordner = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/Duplikate-v12-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v12 Offene Trades von Hand")
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (id, broker, kontonummer, kontoname, waehrung)
                VALUES (1, 'Beispiel Broker Ltd.', '12345678', 'Alt', 'EUR');
            INSERT INTO importlauf (id, kontoId, importer, importerVersion, dateiname, dateiHash, datei,
                                    art, stichtag, serverZeitzone, importiertAm)
                VALUES (1, 1, 'Von Hand', '0.1.0', '', 'von-hand-1', X'', 'von-hand',
                        '2026-06-03 18:00:00.000', 'UTC', '2026-06-03 18:00:00.000');
            INSERT INTO geschlossenePosition (kontoId, importlaufId, ticket, rohzeile, side, lots, symbol,
                                              openTime, openPrice, closeTime, closePrice, commission, swap,
                                              profit, produktart, markterwartung)
                VALUES (1, 1, 'hand-alt', '[]', 'sell', '0.01', 'euraud',
                        '2026-06-03 16:00:00.000', '1.78989', '2026-06-03 16:30:00.000', '1.78838',
                        '0', '0', '0', 'cfd', 'sell');
            """)
    }
    try alt.close()
    let journal = try Journal(pfad: pfad)
    try importiereMT4(journal)
    let konto = try brokerkonto(journal)
    #expect(try journal.angewandteMigrationen().last == "v14 Kontoart und Regeln je Setup")
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).moeglicheDuplikate
        == ["hand-alt": ["51819669"]])
    try journal.behalteHandtrade(konto: konto, ticket: "hand-alt")
    #expect(try journal.tradeBestand(konto: konto, zeitzone: utcZone).auswertbareTrades.count == 2)
}

@Test func handtradeDuplikatMigrationErhaeltV13BestaetigungenNachErneutemOeffnen() throws {
    let ordner = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/Duplikate-v13-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path
    let alt = try DatabaseQueue(path: pfad)
    try Schema.migrator.migrate(alt, upTo: "v13 Eigenständige Hand-Trades")
    try alt.write { db in
        try db.execute(sql: """
            INSERT INTO konto (id, broker, kontonummer, kontoname, waehrung)
                VALUES (1, 'Beispiel Broker Ltd.', '12345678', 'Alt', 'EUR');
            INSERT INTO importlauf (id, kontoId, importer, importerVersion, dateiname, dateiHash, datei,
                                    art, stichtag, serverZeitzone, importiertAm) VALUES
                (1, 1, 'Von Hand', '0.2.0', '', 'von-hand-1', X'', 'von-hand',
                 '2026-06-03 18:00:00.000', 'UTC', '2026-06-03 18:00:00.000'),
                (2, 1, 'MT4-Auszug', '0.2.0', 'beispiel.html', 'beispiel-v13', X'010203', 'daily',
                 '2026-06-03 18:00:00.000', 'UTC', '2026-06-03 18:00:00.000');
            INSERT INTO geschlossenePosition (kontoId, importlaufId, ticket, rohzeile, side, lots, symbol,
                                              openTime, openPrice, closeTime, closePrice, commission, swap,
                                              profit, produktart, markterwartung)
                VALUES (1, 2, 'broker-alt', '[]', 'sell', '0.01', 'euraud',
                        '2026-06-03 16:00:00.000', '1.78989', '2026-06-03 16:30:00.000', '1.78838',
                        '-0.1', '-0.2', '1.51', 'cfd', 'sell');
            """)
        for ticket in ["hand-bestaetigt-1", "hand-bestaetigt-2", "hand-unbestaetigt"] {
            try db.execute(sql: """
                INSERT INTO geschlossenePosition (kontoId, importlaufId, ticket, rohzeile, side, lots, symbol,
                                                  openTime, openPrice, closeTime, closePrice, commission, swap,
                                                  profit, produktart, markterwartung)
                    SELECT kontoId, 1, ?, rohzeile, side, lots, symbol, openTime, openPrice, closeTime,
                           closePrice, commission, swap, profit, produktart, markterwartung
                    FROM geschlossenePosition WHERE ticket = 'broker-alt'
                """, arguments: [ticket])
        }
        // Bereits unter v13 bestätigt, ohne Aufruf von behalteHandtrade nach dem Upgrade.
        try db.execute(sql: """
            INSERT INTO handtradeEigenstaendig (kontoId, ticket)
                VALUES (1, 'hand-bestaetigt-1'), (1, 'hand-bestaetigt-2')
            """)
    }
    let migrationen = try alt.read { try Schema.migrator.appliedMigrations($0) }
    #expect(migrationen.last == "v13 Eigenständige Hand-Trades")
    let vorher = try alt.read { db in
        #expect(try !db.columns(in: "konto").contains { $0.name == "kontoart" })
        return try Dictionary(uniqueKeysWithValues:
            ["konto", "importlauf", "geschlossenePosition", "handtradeEigenstaendig"].map {
                ($0, try Row.fetchAll(db, sql: "SELECT * FROM \($0) ORDER BY rowid"))
            })
    }
    let tradesVorher = try alt.read { db in
        try GeschlossenZeile.order(Column("closeTime"), Column("ticket")).fetchAll(db).map { zeile in
            var trade = Trade(try zeile.modell())
            trade.markterwartung = try zeile.erwartung()
            return trade
        }
    }
    #expect(tradesVorher.count == 4)
    #expect(vorher["handtradeEigenstaendig"]?.count == 2)
    try alt.close()

    for _ in 0..<2 {
        let journal = try Journal(pfad: pfad)
        #expect(try journal.angewandteMigrationen() == migrationen + ["v14 Kontoart und Regeln je Setup"])
        try journal.lies { db in
            for (tabelle, zeilen) in vorher {
                let erste = try #require(zeilen.first)
                let spalten = erste.columnNames.map { "\"\($0)\"" }.joined(separator: ", ")
                let nachher = try Row.fetchAll(db, sql: "SELECT \(spalten) FROM \(tabelle) ORDER BY rowid")
                #expect(nachher == zeilen, "v13-Werte und Beziehungen in \(tabelle)")
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
        }
        let konto = try #require(try journal.konten().first)
        let bestand = try journal.tradeBestand(konto: konto, zeitzone: utcZone)
        #expect(bestand.trades == tradesVorher)
        #expect(bestand.moeglicheDuplikate == ["hand-unbestaetigt": ["broker-alt"]])
        #expect(bestand.auswertbareTrades == tradesVorher.filter { $0.id != "hand-unbestaetigt" })
        try journal.db.close()
    }
}
