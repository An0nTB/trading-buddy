import Foundation
import Testing
import TradingCore
@testable import TradingStore

/// XTB-Testdateien aus den TradingCore-Tests (synthetisch, nicht kopiert, nur gelesen).
private func kern(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/XTB/\(name).xlsx")
    return try Data(contentsOf: url)
}

/// Eigene XTB-Testdateien aus `Tests/Fixtures/XTB/erzeuge.py` (Folgezeitraum und Fehlerfälle).
private func eigen(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/XTB/\(name).xlsx")
    return try Data(contentsOf: url)
}

private func d(_ text: String) -> Decimal { Decimal(string: text)! }
private func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@discardableResult
private func importiere(_ journal: Journal, _ datei: Data, _ name: String) throws -> ImportErgebnis {
    try journal.importiereXTB(datei: datei, dateiname: "\(name).xlsx")
}

private func nurKonto(_ journal: Journal) throws -> Konto {
    let konten = try journal.konten()
    try #require(konten.count == 1)
    return konten[0]
}

@Test func xtbWirdGespeichertUndKommtGleichZurueck() throws {
    let journal = try Journal.imSpeicher()
    let datei = try kern("xtb_sonderfaelle")
    let ergebnis = try importiere(journal, datei, "xtb_sonderfaelle")
    let original = try XTBAuszug.lies(datei)
    #expect(ergebnis.status == .gespeichert)
    #expect(ergebnis.geschlosseneNeu == 3)
    #expect(ergebnis.csv.geldbewegungenNeu == 9)
    #expect(ergebnis.csv.hinweise == 2)

    let konto = try nurKonto(journal)
    #expect(konto.broker == "XTB")
    #expect(konto.kontonummer == "100001")
    #expect(konto.waehrung == "EUR")

    // Positionen wie bei MT4: nach Schließzeit sortiert, Werte exakt.
    let positionen = try journal.geschlossenePositionen(konto: konto)
    #expect(positionen == original.positionen.sorted { ($0.closeTime, $0.ticket) < ($1.closeTime, $1.ticket) })
    #expect(positionen.map(\.ticket) == ["910001", "910003", "910002"])
    let netto: [Decimal] = positionen.map { Trade($0).netProfit }
    #expect(netto == [250, 40, d("22.1")])

    let k = try journal.kontobewegungen(konto: konto)
    #expect(k.geldbewegungen == original.kasse.geldbewegungen.sorted { ($0.zeit, $0.id) < ($1.zeit, $1.id) })
    #expect(k.ausfuehrungen.isEmpty)
    // Sollwert aus den TradingCore-Tests (xtbAufbauWieXStation): Kasse ohne Handel 755,82.
    #expect(k.kassenwirkung == d("755.82"))
    #expect(k.hinweise == original.hinweise)

    let lauf = try #require(try journal.importe(konto: konto).first)
    #expect(lauf.importer == Journal.xtbImporter)
    #expect(lauf.art == "kontoauszug")
    #expect(lauf.serverZeitzone == "Europe/Berlin")
    // Letzte Zeit der Datei: Übertrag am 11.04.2026 10:00 deutscher Sommerzeit.
    #expect(lauf.stichtag == utc("2026-04-11T08:00:00Z"))
    #expect(try journal.importhinweise(importlauf: lauf) == original.hinweise)
}

@Test func gleicheXTBDateiZweimalErgibtKeineDubletten() throws {
    let journal = try Journal.imSpeicher()
    let datei = try kern("xtb_einfach")
    let erster = try importiere(journal, datei, "xtb_einfach")
    let zweiter = try importiere(journal, datei, "kopie")
    #expect(zweiter.status == .dateiBereitsImportiert)
    #expect(zweiter.importlaufId == erster.importlaufId)

    let konto = try nurKonto(journal)
    #expect(konto.kontonummer == "00000001")
    #expect(try journal.importe(konto: konto).count == 1)
    // Sollwerte aus den TradingCore-Tests (xtbEinfacherAufbau): zwei Trades, eine Einzahlung.
    let netto: [Decimal] = try journal.geschlossenePositionen(konto: konto).map { Trade($0).netProfit }
    #expect(netto == [200, d("-11.5")])
    #expect(try journal.kontobewegungen(konto: konto).geldbewegungen.map(\.art) == [.einzahlung])
}

@Test func folgezeitraumUeberschneidetSichOhneDubletten() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, kern("xtb_sonderfaelle"), "xtb_sonderfaelle")
    // 910003 und 800014 stehen in beiden Dateien, hier mit anderen Spalten und Zeiten als Text.
    let zweiter = try importiere(journal, eigen("xtb_folgezeitraum"), "xtb_folgezeitraum")
    #expect(zweiter.status == .gespeichert)
    #expect(zweiter.geschlosseneNeu == 1)
    #expect(zweiter.geschlosseneBekannt == 1)
    #expect(zweiter.csv.geldbewegungenNeu == 1)
    #expect(zweiter.csv.geldbewegungenBekannt == 1)

    let konto = try nurKonto(journal)
    #expect(try journal.importe(konto: konto).count == 2)
    let positionen = try journal.geschlossenePositionen(konto: konto)
    #expect(positionen.map(\.ticket) == ["910001", "910003", "910002", "910005"])
    let k = try journal.kontobewegungen(konto: konto)
    #expect(k.geldbewegungen.count == 10)
    // 755,82 aus der ersten Datei plus die neue Einzahlung von 300.
    #expect(k.kassenwirkung == d("1055.82"))

    // Reihenfolge egal: dieselben Positionen und Beträge.
    let andersrum = try Journal.imSpeicher()
    try importiere(andersrum, eigen("xtb_folgezeitraum"), "xtb_folgezeitraum")
    try importiere(andersrum, kern("xtb_sonderfaelle"), "xtb_sonderfaelle")
    let konto2 = try nurKonto(andersrum)
    let positionen2 = try andersrum.geschlossenePositionen(konto: konto2)
    #expect(positionen2.map(\.ticket) == positionen.map(\.ticket))
    let netto2: [Decimal] = positionen2.map { Trade($0).netProfit }
    let netto: [Decimal] = positionen.map { Trade($0).netProfit }
    #expect(netto2 == netto)
    #expect(try andersrum.kontobewegungen(konto: konto2).kassenwirkung == d("1055.82"))
}

@Test func abweichendePositionBrichtAbUndAendertNichts() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, kern("xtb_sonderfaelle"), "xtb_sonderfaelle")
    // Gleiche Position 910003, Ergebnis 41 statt 40.
    #expect(throws: SpeicherFehler.abweichenderDatensatz(tickets: ["910003"])) {
        try importiere(journal, eigen("xtb_abweichend"), "xtb_abweichend")
    }
    let konto = try nurKonto(journal)
    #expect(try journal.importe(konto: konto).count == 1)
    #expect(try journal.geschlossenePositionen(konto: konto).count == 3)
    #expect(try journal.kontobewegungen(konto: konto).geldbewegungen.count == 9)
}

@Test func falscheSummenzeileWirdNichtGespeichert() throws {
    let journal = try Journal.imSpeicher()
    // Positionen ergeben 50, die Summenzeile sagt 49.
    #expect(throws: SpeicherFehler.auszugWidersprichtSeinenSummen(["Positionen Ergebnis: Summe 49, Zeilen 50"])) {
        try importiere(journal, eigen("xtb_falsche_summe"), "xtb_falsche_summe")
    }
    #expect(try journal.konten().isEmpty)
}

@Test func kontoangabenAusDateiOderApp() throws {
    let journal = try Journal.imSpeicher()
    let ohneKopf = try eigen("xtb_ohne_kopf")
    // Ohne Kontonummer in Datei und Aufruf gibt es kein Konto.
    #expect(throws: SpeicherFehler.ungueltigerWert("Kontonummer fehlt in der Datei und wurde nicht angegeben")) {
        try journal.importiereXTB(datei: ohneKopf, dateiname: "ohne.xlsx")
    }
    #expect(try journal.konten().isEmpty)

    try journal.importiereXTB(datei: ohneKopf, dateiname: "ohne.xlsx", kontonummer: "Demo", kontowaehrung: "USD")
    let konto = try nurKonto(journal)
    #expect(konto.kontonummer == "Demo")
    #expect(konto.waehrung == "USD")
    // Die Datei nennt keine Währung; gespeichert wird die Kontowährung.
    #expect(try journal.kontobewegungen(konto: konto).geldbewegungen.map(\.waehrung) == ["USD"])
    #expect(try journal.geschlossenePositionen(konto: konto).map(\.ticket) == ["930001"])

    // Steht die Angabe in der Datei, muss die der App dazu passen.
    let einfach = try kern("xtb_einfach")
    #expect(throws: SpeicherFehler.ungueltigerWert("Kontonummer laut Datei 00000001, angegeben 1")) {
        try journal.importiereXTB(datei: einfach, dateiname: "einfach.xlsx", kontonummer: "1")
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Kontowährung laut Datei EUR, angegeben USD")) {
        try journal.importiereXTB(datei: einfach, dateiname: "einfach.xlsx", kontowaehrung: "USD")
    }
    #expect(try journal.konten().count == 1)
}

@Test func mt4UndXTBKommenSichNichtInDieQuere() throws {
    let journal = try Journal.imSpeicher()
    try importiere(journal, kern("xtb_einfach"), "xtb_einfach")
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/MT4/gbe-2025-06-04-daily.html")
    try journal.importiereMT4(datei: Data(contentsOf: url), dateiname: "gbe.html",
                              serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    let konten = try journal.konten()
    #expect(konten.map(\.broker) == ["XTB", "GBE brokers Ltd."])
    #expect(try journal.geschlossenePositionen(konto: konten[0]).count == 2)
    #expect(try journal.geschlossenePositionen(konto: konten[1]).count == 1)
}
