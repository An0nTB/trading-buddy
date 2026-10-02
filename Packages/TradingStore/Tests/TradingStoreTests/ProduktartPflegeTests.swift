import Foundation
import GRDB
import Testing
import TradingCore
@testable import TradingStore

/// Testdateien aus den TradingCore-Tests (pseudonymisiert oder synthetisch, nur gelesen).
private func kern(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TradingCore/Tests/TradingCoreTests/Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

/// Eigene Testdateien dieses Pakets.
private func eigen(_ pfad: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/\(pfad)")
    return try Data(contentsOf: url)
}

private func nurKonto(_ journal: Journal) throws -> Konto {
    let konten = try journal.konten()
    try #require(konten.count == 1)
    return konten[0]
}

@Test func vorgabeGiltNurOhneErkannteArt() {
    // Importer kennt die Art: Vorgabe zählt nicht.
    #expect(vorgegeben(.aktie, gespeichert: nil, .fonds) == .aktie)
    // Neue Zeile ohne Art: Vorgabe.
    #expect(vorgegeben(.unbekannt, gespeichert: nil, .fonds) == .fonds)
    // Gespeichert noch ohne Art: Vorgabe ergänzt.
    #expect(vorgegeben(.unbekannt, gespeichert: "unbekannt", .fonds) == .fonds)
    // Gespeichert mit Art: bleibt, die Vorgabe erzeugt keine Abweichung.
    #expect(vorgegeben(.unbekannt, gespeichert: "derivat", .fonds) == .unbekannt)
    // Ohne Vorgabe ändert sich nichts.
    #expect(vorgegeben(.unbekannt, gespeichert: nil, nil) == .unbekannt)
}

@Test func csvImportMitProduktartVorgabe() throws {
    let journal = try Journal.imSpeicher()
    let datei = try kern("R2/scalable_2026.csv")
    let original = try ScalableCSV.lies(String(decoding: datei, as: UTF8.self)).ausfuehrungen
    try #require(!original.isEmpty && original.allSatisfy { $0.produktart == .unbekannt })
    try journal.importiereCSV(datei: datei, dateiname: "scalable.csv", kontonummer: "Depot",
                              produktartVorgabe: .fonds)
    #expect(try journal.kontobewegungen(konto: nurKonto(journal)).ausfuehrungen.allSatisfy { $0.produktart == .fonds })

    // Trade Republic erkennt die Art selbst; die Vorgabe füllt nur, was offen bleibt.
    let depot = try Journal.imSpeicher()
    let tr = try kern("R2/trade_republic_2026_komma.csv")
    let soll = try TradeRepublicCSV.lies(String(decoding: tr, as: UTF8.self)).ausfuehrungen
    try depot.importiereCSV(datei: tr, dateiname: "tr.csv", kontonummer: "Depot", produktartVorgabe: .derivat)
    let gespeichert = try depot.kontobewegungen(konto: nurKonto(depot)).ausfuehrungen
    let arten = Dictionary(uniqueKeysWithValues: gespeichert.map { ($0.id, $0.produktart) })
    for a in soll {
        #expect(arten[a.id] == (a.produktart == .unbekannt ? .derivat : a.produktart))
    }
}

@Test func xtbVorgabeAendertKeineBekannteArt() throws {
    let journal = try Journal.imSpeicher()
    try journal.importiereXTB(datei: kern("XTB/xtb_sonderfaelle.xlsx"), dateiname: "a.xlsx", produktartVorgabe: .cfd)
    // 910003 steht in beiden Dateien; die zweite Vorgabe darf sie weder ändern noch als Abweichung melden.
    let zweiter = try journal.importiereXTB(datei: eigen("XTB/xtb_folgezeitraum.xlsx"), dateiname: "b.xlsx",
                                            produktartVorgabe: .aktie)
    #expect(zweiter.status == .gespeichert)
    let arten = try Dictionary(uniqueKeysWithValues: journal.geschlossenePositionen(konto: nurKonto(journal))
        .map { ($0.ticket, $0.produktart) })
    #expect(arten == ["910001": .cfd, "910002": .cfd, "910003": .cfd, "910005": .aktie])
}

@Test func symboleOhneProduktartNachpflegen() throws {
    let journal = try Journal.imSpeicher()
    try journal.importiereCSV(datei: kern("R2/scalable_2026.csv"), dateiname: "scalable.csv", kontonummer: "Depot")
    let konto = try nurKonto(journal)
    let ausfuehrungen = try journal.kontobewegungen(konto: konto).ausfuehrungen
    let luecken = try journal.symboleOhneProduktart(konto: konto)
    #expect(luecken.map(\.anzahl).reduce(0, +) == ausfuehrungen.count)
    #expect(Set(luecken.map(\.symbol)) == Set(ausfuehrungen.map(\.kennung)))
    let erste = try #require(luecken.first)
    let soll = ausfuehrungen.filter { $0.kennung == erste.symbol }
    let name = soll.map(\.name).max() ?? ""
    #expect(erste.name == (name.isEmpty ? erste.symbol : name))

    #expect(try journal.setzeProduktart(konto: konto, symbol: erste.symbol, .aktie) == erste.anzahl)
    #expect(try journal.setzeProduktart(konto: konto, symbol: erste.symbol, .aktie) == 0)
    #expect(try !journal.symboleOhneProduktart(konto: konto).contains { $0.symbol == erste.symbol })
    let nachher = try journal.kontobewegungen(konto: konto).ausfuehrungen
    #expect(nachher.filter { $0.kennung == erste.symbol }.allSatisfy { $0.produktart == .aktie })
    #expect(nachher.filter { $0.kennung != erste.symbol }.allSatisfy { $0.produktart == .unbekannt })

    // Über den Namen (so zeigt die App Trades aus Ausführungen) geht es auch; Korrektur überschreibt.
    if !erste.name.isEmpty, erste.name != erste.symbol {
        #expect(try journal.setzeProduktart(konto: konto, symbol: erste.name, .fonds) >= erste.anzahl)
    }
}

@Test func produktartNachpflegeTrifftAuchOffenePositionen() throws {
    let journal = try Journal.imSpeicher()
    // 05-14 hat geschlossene, 05-25 offene Positionen (wie in ProduktartSpeicherTests).
    for name in ["gbe-2025-05-14-daily", "gbe-2025-05-25-daily"] {
        try journal.importiereMT4(datei: kern("MT4/\(name).html"), dateiname: "\(name).html",
                                  serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    }
    let konto = try nurKonto(journal)
    #expect(try journal.symboleOhneProduktart(konto: konto).isEmpty)
    let offen = try journal.importe(konto: konto).flatMap { try journal.offenePositionen(importlauf: $0) }
    let symbol = try #require(offen.first?.symbol)
    let geschlossen = try journal.geschlossenePositionen(konto: konto).filter { $0.symbol == symbol }
    let erwartet = offen.filter { $0.symbol == symbol }.count + geschlossen.count

    #expect(try journal.setzeProduktart(konto: konto, symbol: symbol, .unbekannt) == erwartet)
    let luecke = try #require(try journal.symboleOhneProduktart(konto: konto).first)
    #expect(luecke == ProduktartLuecke(symbol: symbol, name: symbol, anzahl: erwartet))
    #expect(try journal.setzeProduktart(konto: konto, symbol: symbol, .cfd) == erwartet)
    #expect(try journal.symboleOhneProduktart(konto: konto).isEmpty)
}

@Test func ungueltigeProduktartNachpflegeWirdAbgelehnt() throws {
    let journal = try Journal.imSpeicher()
    let konto = try journal.schreibe {
        try Journal.konto($0, broker: "Scalable Capital", nummer: "Depot", name: "Depot", waehrung: "EUR")
    }
    #expect(throws: SpeicherFehler.ungueltigerWert("Produktart ohne Symbol")) {
        try journal.setzeProduktart(konto: konto, symbol: " ", .aktie)
    }
    var fremd = konto
    fremd.id = 999
    #expect(throws: SpeicherFehler.ungueltigerWert("Konto 999 gibt es nicht")) {
        try journal.setzeProduktart(konto: fremd, symbol: "DE0007164600", .aktie)
    }
    #expect(try journal.setzeProduktart(konto: konto, symbol: "DE0007164600", .aktie) == 0)
}
