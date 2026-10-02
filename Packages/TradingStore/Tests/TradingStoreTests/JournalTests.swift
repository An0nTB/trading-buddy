import Foundation
import Testing
import TradingCore
@testable import TradingStore

/// Die pseudonymisierten GBE-Auszüge aus den TradingCore-Tests (nicht kopiert, nur gelesen).
private func datei(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/\(name).html")
    return try Data(contentsOf: url)
}

private let alleDateien = [
    "gbe-2025-05-14-daily", "gbe-2025-05-18-daily", "gbe-2025-05-22-daily", "gbe-2025-05-25-daily",
    "gbe-2025-05-31-monthly", "gbe-2025-06-02-daily", "gbe-2025-06-04-daily", "gbe-2025-06-05-daily",
    "gbe-2025-06-06-daily", "gbe-2025-06-07-daily",
]

private let utc = TimeZone(secondsFromGMT: 0)!
private func d(_ text: String) -> Decimal { Decimal(string: text)! }

@discardableResult
private func importiere(_ journal: Journal, _ name: String, zeitzone: TimeZone = utc,
                        waehrung: String = "EUR") throws -> ImportErgebnis {
    try journal.importiereMT4(datei: datei(name), dateiname: "\(name).html",
                              serverZeitzone: zeitzone, kontowaehrung: waehrung)
}

private func nurKonto(_ journal: Journal) throws -> Konto {
    let konten = try journal.konten()
    try #require(konten.count == 1)
    return konten[0]
}

private func netto(_ positionen: [ClosedPosition]) -> Decimal {
    positionen.reduce(Decimal(0)) { $0 + $1.netProfit }
}

private let alleMigrationen = ["v1 Konten, Importe, MT4-Auszüge", "v2 Journal je Trade", "v3 Broker-Importe CSV",
                              "v4 Review-Ziele", "v6 Produktart"]

@Test func migrationenLaufenUndSindWiederholbar() throws {
    let ordner = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let pfad = ordner.appendingPathComponent("journal.sqlite").path

    let erstes = try Journal(pfad: pfad)
    try importiere(erstes, "gbe-2025-06-04-daily")
    #expect(try erstes.angewandteMigrationen() == alleMigrationen)

    // Zweites Öffnen derselben Datei: keine Migration läuft doppelt, Daten bleiben.
    let zweites = try Journal(pfad: pfad)
    #expect(try zweites.angewandteMigrationen() == alleMigrationen)
    #expect(try zweites.geschlossenePositionen(konto: nurKonto(zweites)).count == 1)
}

@Test func gleicheDateiZweimalErgibtKeineDubletten() throws {
    let journal = try Journal.imSpeicher()
    let erster = try importiere(journal, "gbe-2025-05-31-monthly")
    #expect(erster.status == .gespeichert)
    #expect(erster.geschlosseneNeu == 83)
    #expect(erster.geloeschteNeu == 57)

    let zweiter = try importiere(journal, "gbe-2025-05-31-monthly")
    #expect(zweiter.status == .dateiBereitsImportiert)
    #expect(zweiter.importlaufId == erster.importlaufId)

    let konto = try nurKonto(journal)
    #expect(try journal.importe(konto: konto).count == 1)
    #expect(try journal.geschlossenePositionen(konto: konto).count == 83)
    #expect(try journal.geloeschteOrders(konto: konto).count == 57)
    #expect(netto(try journal.geschlossenePositionen(konto: konto)) == d("7.14"))
}

/// Sollwerte unabhängig vom Swift-Code mit Python aus den zehn Dateien gezählt (01.10.2026):
/// 109 geschlossene Zeilen, davon 104 verschiedene Tickets; 83 gelöschte Orders, davon 79 verschiedene;
/// Netto über alle Tickets 14.29 (Mai 7.14, Juni 7.15); keine abweichenden Doppelten.
@Test func tagesUndMonatsauszuegeUeberschneidenSichOhneDubletten() throws {
    let journal = try Journal.imSpeicher()
    var bekannt = 0
    for name in alleDateien {
        bekannt += try importiere(journal, name).geschlosseneBekannt
    }
    let konto = try nurKonto(journal)
    let geschlossen = try journal.geschlossenePositionen(konto: konto)
    #expect(geschlossen.count == 104)
    #expect(Set(geschlossen.map(\.ticket)).count == 104)
    #expect(bekannt == 5)
    #expect(try journal.geloeschteOrders(konto: konto).count == 79)
    #expect(netto(geschlossen) == d("14.29"))
    #expect(try journal.importe(konto: konto).count == 10)

    // Reihenfolge egal: Monatsauszug zuletzt ergibt denselben Bestand.
    let andersrum = try Journal.imSpeicher()
    for name in alleDateien.reversed() { try importiere(andersrum, name) }
    #expect(try andersrum.geschlossenePositionen(konto: nurKonto(andersrum)) == geschlossen)
}

@Test func monatsfilterTrifftSummeDesAuszugs() throws {
    let journal = try Journal.imSpeicher()
    for name in alleDateien { try importiere(journal, name) }
    let konto = try nurKonto(journal)
    let iso = ISO8601DateFormatter()
    let juni = try journal.geschlossenePositionen(konto: konto,
                                                  von: iso.date(from: "2025-06-01T00:00:00Z"),
                                                  bis: iso.date(from: "2025-07-01T00:00:00Z"))
    #expect(juni.count == 21)
    #expect(netto(juni) == d("7.15"))
}

@Test func werteKommenUnveraendertZurueck() throws {
    let journal = try Journal.imSpeicher()
    let zeitzone = TimeZone(secondsFromGMT: 3 * 3600)!
    try importiere(journal, "gbe-2025-05-14-daily", zeitzone: zeitzone)
    let original = try MT4Statement.parse(html: String(decoding: datei("gbe-2025-05-14-daily"), as: UTF8.self),
                                          serverZeitzone: zeitzone)
    let konto = try nurKonto(journal)
    #expect(konto.broker == "GBE brokers Ltd.")
    #expect(konto.kontonummer == "100001")
    #expect(konto.waehrung == "EUR")

    // Decimal und Zeiten überstehen den Weg durch SQLite exakt.
    #expect(try journal.geschlossenePositionen(konto: konto) == original.closedPositions.sorted {
        ($0.closeTime, $0.ticket) < ($1.closeTime, $1.ticket)
    })
    // Rohzeile (Regel 9) kommt mit: erste Zelle ist das Ticket.
    #expect(try journal.geschlossenePositionen(konto: konto).allSatisfy { $0.rohzeile.first == $0.ticket })
    #expect(Set(try journal.geloeschteOrders(konto: konto).map(\.ticket)) == Set(original.cancelledOrders.map(\.ticket)))

    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.serverZeitzone == zeitzone.identifier)
    #expect(TimeZone(identifier: lauf.serverZeitzone)?.secondsFromGMT() == 3 * 3600)
    #expect(lauf.art == "daily")
    #expect(lauf.importerVersion == TradingCore.version)
    #expect(lauf.dateiHash == Journal.fingerabdruck(try datei("gbe-2025-05-14-daily")))
    #expect(lauf.datei == (try datei("gbe-2025-05-14-daily")))
    #expect(try journal.kontostand(importlauf: lauf) == original.summary)
}

@Test func offenePositionenSindMomentaufnahmeJeAuszug() throws {
    let journal = try Journal.imSpeicher()
    for name in ["gbe-2025-05-18-daily", "gbe-2025-05-22-daily", "gbe-2025-05-25-daily"] {
        try importiere(journal, name)
    }
    let konto = try nurKonto(journal)
    let laeufe = try journal.importe(konto: konto)
    #expect(laeufe.count == 3)
    // Jeder Auszug hat seine eigene offene Position; sie werden nicht aufsummiert
    // und tauchen nie bei den geschlossenen Positionen auf.
    let floating = try laeufe.map { lauf in
        try journal.offenePositionen(importlauf: lauf).reduce(Decimal(0)) { $0 + $1.netProfit }
    }
    #expect(floating == [d("-4.89"), d("0.06"), d("1.01")])
    #expect(try journal.kontostand(importlauf: laeufe[2])?.floatingPL == d("1.01"))
    #expect(try laeufe.map { try journal.offenePositionen(importlauf: $0).map(\.ticket) }
            == [["88152851"], ["88167088"], ["88167088"]])
    #expect(try journal.geschlossenePositionen(konto: konto).map(\.ticket) == ["88167086"])
}

@Test func offenePositionenDesLetztenAuszugs() throws {
    let journal = try Journal.imSpeicher()
    // Absichtlich nicht in Datumsfolge importiert: Maßgeblich ist der Stichtag, nicht die Reihenfolge.
    for name in ["gbe-2025-05-25-daily", "gbe-2025-05-18-daily", "gbe-2025-05-22-daily"] {
        try importiere(journal, name)
    }
    let konto = try nurKonto(journal)
    let letzter = try #require(try journal.offenePositionenLetzterAuszug(konto: konto))
    let laeufe = try journal.importe(konto: konto)
    #expect(letzter.importlauf == laeufe.last)
    #expect(letzter.importlauf.dateiname == "gbe-2025-05-25-daily.html")
    // Sollwert wie in offenePositionenSindMomentaufnahmeJeAuszug: am 25.05. offen 88167088, Floating 1.01.
    #expect(letzter.positionen.map(\.ticket) == ["88167088"])
    let floating: Decimal = letzter.positionen.reduce(0) { $0 + $1.netProfit }
    #expect(floating == d("1.01"))

    // Konto ohne MT4-Auszug: keine Angabe statt einer leeren Liste.
    let ohne = try journal.schreibe {
        try Journal.konto($0, broker: "XTB", nummer: "1", name: "ohne MT4", waehrung: "EUR")
    }
    #expect(try journal.offenePositionenLetzterAuszug(konto: ohne)?.importlauf == nil)
}

@Test func abweichenderDoppelterBrichtAbUndAendertNichts() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "gbe-2025-05-31-monthly")

    // Derselbe Tagesauszug mit einer geänderten Zeile: gleiches Ticket, anderer Schlusskurs.
    // Kursergebnis bleibt, damit die Summenprüfung des Auszugs nicht schon vorher anschlägt.
    let original = String(decoding: try datei("gbe-2025-05-14-daily"), as: UTF8.self)
    let geaendert = original.replacingOccurrences(of: "<td>0.59880</td>", with: "<td>0.59881</td>")
    #expect(geaendert != original)

    let konto = try nurKonto(journal)
    let vorher = try journal.geschlossenePositionen(konto: konto)
    #expect(throws: SpeicherFehler.abweichenderDatensatz(tickets: ["88075715"])) {
        try journal.importiereMT4(datei: Data(geaendert.utf8), dateiname: "geaendert.html", serverZeitzone: utc)
    }
    // Transaktion zurückgerollt: kein neuer Import, keine neuen Positionen.
    #expect(try journal.importe(konto: konto).count == 1)
    #expect(try journal.geschlossenePositionen(konto: konto) == vorher)
}

@Test func andereZeitzoneFuerDasselbeKontoFaelltAuf() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "gbe-2025-05-31-monthly", zeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    // Der Tagesauszug enthält Tickets aus dem Monatsauszug; mit anderer Zeitzone
    // ergeben sie andere UTC-Zeiten und gelten deshalb als abweichend.
    #expect(throws: SpeicherFehler.self) {
        try importiere(journal, "gbe-2025-05-14-daily", zeitzone: utc)
    }
}

@Test func andereKontowaehrungWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, "gbe-2025-05-14-daily", waehrung: "EUR")
    #expect(throws: SpeicherFehler.andereKontowaehrung(gespeichert: "EUR", angegeben: "USD")) {
        try importiere(journal, "gbe-2025-06-02-daily", waehrung: "USD")
    }
    #expect(try journal.importe(konto: nurKonto(journal)).count == 1)
}

@Test func auszugMitFalscherSummeWirdNichtGespeichert() throws {
    let journal = try Journal.imSpeicher()
    let text = String(decoding: try datei("gbe-2025-05-14-daily"), as: UTF8.self)
        .replacingOccurrences(of: "<td>-5.13</td>", with: "<td>-5.14</td>")
    #expect(throws: SpeicherFehler.self) {
        try journal.importiereMT4(datei: Data(text.utf8), dateiname: "falsch.html", serverZeitzone: utc)
    }
    #expect(try journal.konten().isEmpty)
}

@Test func fingerabdruckIstSHA256() {
    // Bekannter Prüfwert für die leere Eingabe (FIPS 180-4).
    #expect(Journal.fingerabdruck(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
}
