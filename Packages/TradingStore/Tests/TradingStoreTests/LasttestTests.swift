import Foundation
import Testing
import TradingCore
@testable import TradingStore

// Lasttest (Beta mit Testern): drei Jahre Historie, 10 000 Ausführungen bzw. 5 000 Trades auf drei Konten.
// Die Grenze ist großzügig für den langsamsten CI-Runner (Debug-Build, parallele Tests); die gemessenen
// Zeiten stehen im Testprotokoll unter „Lasttest“ und in Doc 11.

private let grenze: Duration = .seconds(10)

@discardableResult
private func miss<T>(_ schritt: String, _ arbeit: () throws -> T) throws -> T {
    var ergebnis: T?
    let dauer = try ContinuousClock().measure { ergebnis = try arbeit() }
    let ms = Double(dauer.components.seconds) * 1_000 + Double(dauer.components.attoseconds) / 1e15
    print("Lasttest \(schritt): \(Int(ms.rounded())) ms")
    #expect(dauer < grenze, "\(schritt) dauerte \(dauer)")
    return ergebnis!
}

private func ordner() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lasttest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func lastdatenSindReproduzierbar() {
    let a = Lastdaten.erzeuge(), b = Lastdaten.erzeuge()
    #expect(a.scalable == b.scalable && a.ibkr == b.ibkr && a.mt5 == b.mt5)
    #expect(a.handelstage.count == Lastdaten.handelstageAnzahl)
    #expect(Lastdaten.zahl(-12_345, 2) == "-123.45")
    #expect(Lastdaten.zahl(5, 3, komma: true) == "0,005")
    // Der Zusatz hängt an, ohne Vorhandenes zu ändern.
    let c = Lastdaten.erzeuge(zusatz: true)
    #expect(c.scalable != a.scalable && c.ibkr.starts(with: a.ibkr))
}

@Test func zehntausendAusfuehrungenBleibenFlott() throws {
    let dir = try ordner()
    defer { try? FileManager.default.removeItem(at: dir) }
    let daten = try miss("Daten erzeugen") { Lastdaten.erzeuge() }
    let server = TimeZone(secondsFromGMT: 2 * 3600)!
    let journal = try Journal(pfad: dir.appendingPathComponent("journal.sqlite").path)
    let ausfuehrungen = 2 * Lastdaten.roundtripsJeBroker, positionen = Lastdaten.mt5Positionen

    // Erstimport
    let s = try miss("Erstimport Scalable (\(ausfuehrungen) Ausführungen)") {
        try journal.importiereCSV(datei: daten.scalable, dateiname: "scalable.csv", kontonummer: "Depot")
    }
    #expect(s.csv.ausfuehrungenNeu == ausfuehrungen && s.csv.geldbewegungenNeu == daten.scalableGeld)
    let i = try miss("Erstimport IBKR (\(ausfuehrungen) Ausführungen)") {
        try journal.importiereCSV(datei: daten.ibkr, dateiname: "ibkr.csv", kontonummer: "IBKR")
    }
    #expect(i.csv.ausfuehrungenNeu == ausfuehrungen && i.csv.geldbewegungenNeu == daten.ibkrGeld)
    let m = try miss("Erstimport MT5 (\(positionen) Positionen)") {
        try journal.importiereMT5(datei: daten.mt5, dateiname: "mt5.html", serverZeitzone: server)
    }
    #expect(m.geschlosseneNeu == positionen && m.csv.geldbewegungenNeu == daten.mt5Geld)

    // Dieselben Dateien noch einmal: erkannt am Fingerabdruck.
    let zweitimport = try miss("Zweitimport gleiche Dateien") {
        [try journal.importiereCSV(datei: daten.scalable, dateiname: "s.csv", kontonummer: "Depot").status,
         try journal.importiereCSV(datei: daten.ibkr, dateiname: "i.csv", kontonummer: "IBKR").status,
         try journal.importiereMT5(datei: daten.mt5, dateiname: "m.html", serverZeitzone: server).status]
    }
    #expect(zweitimport == [.dateiBereitsImportiert, .dateiBereitsImportiert, .dateiBereitsImportiert])

    // Nächster Export mit einem neuen Vorgang: jede alte Zeile wird gegen den Bestand verglichen.
    let weiter = Lastdaten.erzeuge(zusatz: true)
    let s2 = try miss("Folgeimport Scalable, Dublettenprüfung") {
        try journal.importiereCSV(datei: weiter.scalable, dateiname: "scalable-2.csv", kontonummer: "Depot")
    }
    #expect(s2.csv.ausfuehrungenBekannt == ausfuehrungen && s2.csv.geldbewegungenNeu == 1)
    let i2 = try miss("Folgeimport IBKR, Dublettenprüfung") {
        try journal.importiereCSV(datei: weiter.ibkr, dateiname: "ibkr-2.csv", kontonummer: "IBKR")
    }
    #expect(i2.csv.ausfuehrungenBekannt == ausfuehrungen && i2.csv.geldbewegungenNeu == 1)
    let m2 = try miss("Folgeimport MT5, Dublettenprüfung") {
        try journal.importiereMT5(datei: weiter.mt5, dateiname: "mt5-2.html", serverZeitzone: server)
    }
    #expect(m2.geschlosseneBekannt == positionen && m2.geschlosseneNeu == 1)

    // Was die App beim Start je Konto liest.
    let konten = try journal.konten()
    #expect(konten.count == 3)
    var trades = 0
    for konto in konten {
        trades += try miss("Laden \(konto.broker)") { () throws -> Int in
            let bewegungen = try journal.kontobewegungen(konto: konto)
            let geschlossen = try journal.geschlossenePositionen(konto: konto)
            _ = try journal.journaleintraege(konto: konto)
            _ = try journal.importe(konto: konto)
            _ = try journal.offenePositionenLetzterAuszug(konto: konto)
            _ = try journal.symboleOhneProduktart(konto: konto)
            _ = try journal.ziele(konto: konto)
            _ = try journal.checklisten(konto: konto)
            _ = try journal.handelsregeln(konto: konto)
            return bewegungen.ausfuehrungen.count / 2 + geschlossen.count
        }
    }
    #expect(trades == Lastdaten.roundtripsJeBroker * 2 + positionen + 1)

    // Tagesnotizen an jedem Handelstag, Journal zu jeder MT5-Position, Merkliste.
    let mt5Konto = try #require(konten.first { $0.broker == "Beispiel Broker Ltd." })
    let tickets = try journal.geschlossenePositionen(konto: mt5Konto).map(\.ticket)
    try miss("Schreiben \(daten.handelstage.count) Tagesnotizen, \(tickets.count) Journaleinträge, 300 Merkliste") {
        for tag in daten.handelstage {
            _ = try journal.speichereTagesnotiz(
                Tagesnotiz(tag: Journaltag(tag, zeitzone: Lastdaten.utc), plan: "Plan für den Tag",
                           rueckblick: "Rückblick", verfassung: 3, erstellt: tag), jetzt: tag)
        }
        for ticket in tickets {
            try journal.speichereJournal(Journaleintrag(kontoId: mt5Konto.id!, ticket: ticket, setup: "Ausbruch",
                                                        regeltreue: true, zustand: 4, grund: "Lasttest"))
        }
        for n in 0..<300 {
            try journal.speichereMerklisteneintrag(Merklisteneintrag(id: "last-\(n)", begriff: "Stichwort \(n)",
                                                                     erstellt: daten.handelstage[n]))
        }
    }
    let erster = Journaltag(daten.handelstage[0], zeitzone: Lastdaten.utc)
    let letzter = Journaltag(daten.handelstage[daten.handelstage.count - 1], zeitzone: Lastdaten.utc)
    let geladen = try miss("Laden Tagesnotizen, Journal, Merkliste") {
        [try journal.tagesnotizen(von: erster, bis: letzter).count,
         try journal.journaleintraege(konto: mt5Konto).count,
         try journal.merkliste().count]
    }
    #expect(geladen == [daten.handelstage.count, tickets.count, 300])

    // Datensicherung und Wiederherstellen in ein leeres Journal.
    let sicherung = try miss("Datensicherung") {
        try journal.sichereInOrdner(dir.appendingPathComponent("Sicherung"))
    }
    let pruefung = try miss("Sicherung prüfen") { Journal.pruefeSicherung(sicherung) }
    #expect(pruefung.zustand == .aktuell)
    #expect(pruefung.ausfuehrungen == 2 * ausfuehrungen && pruefung.geschlossenePositionen == positionen + 1)
    let ziel = try Journal(pfad: dir.appendingPathComponent("ziel.sqlite").path)
    let ergebnis = try miss("Wiederherstellen") { try ziel.stelleWiederHer(aus: sicherung) }
    #expect(ergebnis == pruefung)
    #expect(try ziel.konten() == konten)
    #expect(try ziel.merkliste().count == 300)
}
