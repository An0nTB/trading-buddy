import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.13.0: Ticket- und Symbolfilter in hole_trades (Doc 31), Produktart (Doc 23), Trades nur mit Datum
/// westlich von UTC (Doc 36, Doc 40).

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private let newYork = TimeZone(identifier: "America/New_York")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ symbol: String, _ schluss: String, netto: Decimal, art: Produktart = .unbekannt,
                   waehrung: String? = nil) -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: zeit(schluss).addingTimeInterval(-600),
          closeTime: zeit(schluss), openPrice: 100, closePrice: 100 + netto, profit: netto, produktart: art,
          waehrung: waehrung)
}

private let alle = [trade("1001", "SAP", "2025-05-05T10:00:00", netto: 10, art: .aktie),
                    trade("1002", "BTCEUR", "2025-05-06T10:00:00", netto: -4, art: .krypto),
                    trade("2001", "DAX", "2025-05-07T10:00:00", netto: 3),
                    trade("3001", "AAPL", "2025-05-08T15:00:00", netto: 5, art: .aktie, waehrung: "USD"),
                    trade("1003", "SAP", "2025-06-10T10:00:00", netto: 6, art: .aktie)]

private func export(_ trades: [Trade] = alle, zone: TimeZone = berlin) -> JournalExport {
    JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: trades)],
                  zeitzone: zone, erstellt: zeit("2026-10-01T20:00:00"))
}

@Test func ticketsOhneZeitraumNehmenIhreMonate() throws {
    let anfrage = try Anfrage.lies(["ticket": "1001, 1003"], export: export())
    let mai = try #require(Zeitspanne.monat(jahr: 2025, monat: 5, zeitzone: berlin))
    let juni = try #require(Zeitspanne.monat(jahr: 2025, monat: 6, zeitzone: berlin))
    #expect(anfrage.tickets == ["1001", "1003"] && anfrage.zeitraum == Zeitspanne(von: mai.von, bis: juni.bis))
    #expect(anfrage.vorgabe == "Kein Zeitraum angegeben, daher die Monate der gesuchten Tickets.")
    let text = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10)
    #expect(text.contains("| 1001 | 05.05.2025 12:00 | SAP |") && text.contains("| 1003 | 10.06.2025 12:00 | SAP |"))
    #expect(!text.contains("| 1002 |") && !text.contains("Nicht im Zeitraum"))

    // Mit Zeitraum: nur die Tickets darin, die übrigen werden genannt.
    let mitMonat = try Anfrage.lies(["ticket": "1001,1003", "monat": "2025-05"], export: export())
    let nurMai = Ausgabe.trades(mitMonat, auswahl: .chronologisch, muster: nil, anzahl: 10)
    #expect(nurMai.contains("| 1001 |") && !nurMai.contains("| 1003 |"))
    #expect(nurMai.contains("Nicht im Zeitraum dieses Kontos: Ticket 1003."))
}

@Test func unbekanntesTicketUndTicketInAndererWaehrung() throws {
    let datei = export()
    let name = datei.kurzname(datei.konten[0])
    #expect(throws: AnfrageFehler.ticketUnbekannt("9999", name, nil)) {
        try Anfrage.lies(["ticket": "9999"], export: datei)
    }
    #expect(AnfrageFehler.ticketUnbekannt("9999", name, nil).text.hasPrefix("TICKET UNBEKANNT: „9999“"))
    // 3001 ist ein USD-Trade ohne Kurs in der Datei: nicht in der Abfrage in EUR, aber mit waehrung.
    #expect(throws: AnfrageFehler.ticketUnbekannt("3001", name, "USD")) {
        try Anfrage.lies(["ticket": "3001"], export: datei)
    }
    #expect(AnfrageFehler.ticketUnbekannt("3001", name, "USD").text.contains("abfragen mit waehrung=USD."))
    let usd = try Anfrage.lies(["ticket": "3001", "waehrung": "USD"], export: datei)
    #expect(Ausgabe.trades(usd, auswahl: .chronologisch, muster: nil, anzahl: 10).contains("| 3001 |"))
}

@Test func symbolfilterInDerTradeListe() throws {
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export())
    let text = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10, symbol: " sap ")
    #expect(text.contains("# Henry · Trades Mai 2025 · SAP"))
    #expect(text.contains("| 1001 |") && !text.contains("| 1002 |") && !text.contains("| 2001 |"))
    let keins = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10, symbol: "XYZ")
    #expect(keins.contains("Keine passenden Trades."))
}

@Test func produktartInAuswertungListeUndAufschluesselung() throws {
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export())
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Nach Produktart (laut Broker-Export)"))
    #expect(text.contains("| Aktie | 1 | 10,00 |") && text.contains("| Krypto | 1 | \(Format.zahl(Decimal(-4))) |"))
    #expect(text.contains("| unbekannt | 1 | 3,00 |"))

    let liste = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 10)
    #expect(liste.contains("| Haltedauer | Muster | Produkt |"))
    #expect(liste.contains("| Krypto |") && liste.contains("| unbekannt |"))

    #expect(Aufschluesselung(rawValue: "produktart") == .produktart)
    #expect(Aufschluesselung.alleWerte.contains("produktart"))
    let gruppen = Ausgabe.aufschluesselung(anfrage, nach: .produktart)
    #expect(gruppen.contains("# Henry · Produktart · Mai 2025") && gruppen.contains("| Aktie | 1 | 10,00 |"))
    #expect(gruppen.contains("nicht der Steuertopf"))
}

@Test func produktartNurWennDerExportSieNennt() throws {
    let nurAktien = export([alle[0], alle[4]])
    let eine = Ausgabe.auswertung(try Anfrage.lies(["von": "2025-05-01", "bis": "2025-06-30"], export: nurAktien))
    #expect(eine.contains("Produktart laut Broker-Export: alle 2 Trades Aktie.") && !eine.contains("## Nach Produktart"))

    let ohneArt = try Anfrage.lies(["monat": "2025-05"], export: export([alle[2]]))
    let ohne = Ausgabe.auswertung(ohneArt)
    #expect(!ohne.contains("## Nach Produktart") && !ohne.contains("Produktart laut Broker-Export"))
    #expect(!Ausgabe.trades(ohneArt, auswahl: .chronologisch, muster: nil, anzahl: 10).contains("| Produkt |"))
}

@Test func tradesNurMitDatumBleibenWestlichVonUTCAmSelbenTag() throws {
    var nurDatum = trade("tr1", "SAP", "2025-05-05T00:00:00", netto: 7, art: .aktie)
    nurDatum.nurDatum = true
    nurDatum.openTime = zeit("2025-05-02T00:00:00")
    var ortszeit = nurDatum
    ortszeit.id = "sc1"
    // Mitternacht in New York (Scalable rechnet in Ortszeit)
    ortszeit.openTime = zeit("2025-05-02T04:00:00")
    ortszeit.closeTime = zeit("2025-05-05T04:00:00")
    let mitUhrzeit = trade("mt1", "SAP", "2025-05-05T00:00:00", netto: 1)

    let westen = export([nurDatum, ortszeit, mitUhrzeit], zone: newYork).mitTageslage()
    let trades = westen.konten[0].trades
    #expect(trades[0].closeTime == zeit("2025-05-05T12:00:00") && trades[0].openTime == zeit("2025-05-02T12:00:00"))
    #expect(trades[0].holdingTime == nurDatum.holdingTime)
    #expect(trades[1] == ortszeit && trades[2] == mitUhrzeit)
    // Östlich von UTC bleibt alles wie in der App.
    #expect(export([nurDatum], zone: berlin).mitTageslage() == export([nurDatum], zone: berlin))

    // Der Tag in New York ist der 05.05., nicht der Vortag.
    let tag = try Anfrage.lies(["von": "2025-05-05", "bis": "2025-05-05"], export: westen)
    #expect(tag.auswertung().trades.map(\.id).contains("tr1"))
    let liste = Ausgabe.trades(tag, auswahl: .chronologisch, muster: nil, anzahl: 10)
    #expect(liste.contains("| tr1 | 05.05.2025 | SAP |"))
}

@Test func exportdateiLiestMitTageslage() throws {
    let ordner = FileManager.default.temporaryDirectory
        .appending(path: "tb-tageslage-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    var nurDatum = trade("tr1", "SAP", "2025-05-05T00:00:00", netto: 7)
    nurDatum.nurDatum = true
    let datei = export([nurDatum], zone: newYork)
    try datei.json().write(to: ordner.appending(path: JournalExport.dateiname))
    guard case let .geladen(gelesen) = Exportdatei.lade(ordner: ordner.path) else {
        Issue.record("erwartet .geladen")
        return
    }
    #expect(gelesen.konten.first?.trades.first?.closeTime == zeit("2025-05-05T12:00:00"))
}

@Test func prozessFeedbackErlaubtEmpfehlungenZuWertenNicht() throws {
    // Tim 05.10.2026: Trade-Analyse mit Review zum Fehlermuster und dem, was besser laufen kann; Wertanalyse bleibt
    // beschreibend (Doc 02 Nr. 44/50).
    #expect(Rezept.text.contains("6. Review und besser machen:") && Rezept.text.contains("8. Genau ein messbares Ziel"))
    #expect(Rezept.text.contains("- Review des eigenen Vorgehens ist erwünscht"))
    #expect(Rezept.text.contains(Rezept.einschaetzungsRegel) && Rezept.text.contains("Marktrisiko, kein Fehler"))
    let trades = Ausgabe.trades(try Anfrage.lies(["monat": "2025-05"], export: export()), auswahl: .chronologisch,
                                muster: nil, anzahl: 10)
    #expect(trades.contains("## Hinweis für die Antwort (Henry)"))
    #expect(trades.contains("Einschätzungen, Empfehlungen, Kursziele und Szenarien sind erlaubt"))
    #expect(trades.contains(Rezept.hinweis) && Rezept.kursanalyseText.contains(Rezept.hinweis))
    let leer = Ausgabe.trades(try Anfrage.lies(["monat": "2025-05"], export: export()),
                              auswahl: .chronologisch, muster: nil, anzahl: 10, symbol: "XYZ")
    #expect(leer.contains("Keine passenden Trades.") && !leer.contains("## Hinweis für die Antwort"))
    #expect(!Rezept.kursanalyseText.contains("Review des eigenen") && Rezept.kursanalyseText.contains("6. Einschätzung:"))
    #expect(!Rezept.nachrichtenText.contains("Review des eigenen"))
}

@Test func reviewBekommtPlanStopUndChecklisteJeTrade() throws {
    // Review „nach Plan oder eigener Fehler“ (05.10.2026): Stop, Ziel und Playbook-Checkliste je Trade, fehlende
    // Quellen werden genannt.
    let mitPlan = Trade(id: "5001", symbol: "EURUSD", side: .buy, lots: 1, openTime: zeit("2025-05-05T09:00:00"),
                        closeTime: zeit("2025-05-05T10:00:00"), openPrice: Decimal(string: "1.08345")!,
                        closePrice: Decimal(string: "1.08245")!, stopLoss: Decimal(string: "1.08245")!,
                        takeProfit: Decimal(string: "1.08545")!, profit: -10)
    let ohneStop = trade("5002", "SAP", "2025-05-06T10:00:00", netto: -4)
    let karte = JournalExport.Playbookkarte(name: "Ausbruch", kriterien: [Kriterium(id: "a", text: "Trend H1"),
                                                                         Kriterium(id: "b", text: "Volumen"),
                                                                         Kriterium(id: "c", text: "News geprüft")],
                                            stopRegel: "unter Ausbruchskerze")
    let konto = JournalExport.Kontodaten(broker: "Kraken", kontonummer: "4242", waehrung: "EUR",
                                         trades: [mitPlan, ohneStop],
                                         journal: ["5001": Journalangaben(setup: "ausbruch ")],
                                         checklisten: ["5001": ["c", "b"]])
    let datei = JournalExport(konten: [konto], zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"), playbook: [karte])
    let gelesen = try JournalExport.lese(try datei.json())
    #expect(gelesen.playbook == [karte] && gelesen.konten[0].checklisten == ["5001": ["b", "c"]])
    #expect(gelesen.playbookkarte("AUSBRUCH")?.stopRegel == "unter Ausbruchskerze")

    let text = Ausgabe.trades(try Anfrage.lies(["monat": "2025-05"], export: gelesen), auswahl: .chronologisch,
                              muster: nil, anzahl: 10)
    #expect(text.contains("| Ticket | Einstieg | Ausstieg | Stop | Ziel | Checkliste |"))
    #expect(text.contains("| 5001 | 1,08345 | 1,08245 | 1,08245 | 1,08545 | 2 von 3, fehlt: „Trend H1“ |"))
    #expect(text.contains("| 5002 | 100 | 96 | – | – | kein Setup |"))
    #expect(text.contains("Fehlende Angaben (im Review offen nennen): Stop bei 1, Journaleintrag bei 1, "
                          + "Kerzen für den Ausstieg bei 2 von 2 Trades."))

    // Ältere Datei ohne Playbook und Checklisten: kein Urteil über die Checkliste.
    let alt = JournalExport(konten: [JournalExport.Kontodaten(broker: "Kraken", kontonummer: "4242", waehrung: "EUR",
                                                              trades: [mitPlan],
                                                              journal: ["5001": Journalangaben(setup: "Ausbruch")])],
                            zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    let altJSON = String(decoding: try alt.json(), as: UTF8.self)
    #expect(!altJSON.contains("playbook") && !altJSON.contains("checklisten"))
    let altText = Ausgabe.trades(try Anfrage.lies(["monat": "2025-05"], export: alt), auswahl: .chronologisch,
                                 muster: nil, anzahl: 10)
    #expect(altText.contains("| 5001 | 1,08345 | 1,08245 | 1,08245 | 1,08545 | – |"))
}
