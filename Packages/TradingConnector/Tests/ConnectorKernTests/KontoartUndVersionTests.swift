import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.20.0, Auftrag E1, E7, E8 und E9 (Tim 17.10.2026): Demo und Echtgeld getrennt, Stand des
/// Kill-Kriteriums je Setup aus dem Export, Warnung bei anderem Rechenkern der App, Statusdatei für die App.
/// Erfundene Trades.

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

/// Trade ohne Stop mit geplantem Risiko 10: R = netto ÷ 10.
private func trade(_ id: String, _ tag: String, netto: Decimal, waehrung: String? = nil) -> Trade {
    var t = Trade(id: id, symbol: "DE40", side: .buy, lots: 1, openTime: zeit(tag + "T09:00:00"),
                  closeTime: zeit(tag + "T09:30:00"), openPrice: 100, closePrice: 100 + netto, profit: netto)
        .mitGeplantemRisiko(10)
    t.waehrung = waehrung
    return t
}

private func ausbruch(_ ids: [String]) -> [String: Journalangaben] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, Journalangaben(setup: "Ausbruch")) })
}

/// XTB-Demo mit drei Ausbruch-Trades (-5, +2, -1), IBKR-Echtgeld mit einem (+4), dazu das Beispielkonto.
private func beispielExport() -> JournalExport {
    let demo = [trade("d1", "2026-10-05", netto: -5), trade("d2", "2026-10-06", netto: 2),
                trade("d3", "2026-10-07", netto: -1)]
    let echt = [trade("e1", "2026-10-06", netto: 4)]
    let erfunden = [trade("b1", "2026-09-01", netto: 50)]
    return JournalExport(
        konten: [.init(broker: "XTB", kontonummer: "501234", waehrung: "EUR", trades: demo,
                       journal: ausbruch(["d1", "d2", "d3"]), kontoart: .demo),
                 .init(broker: "IBKR", kontonummer: "U7775678", waehrung: "EUR", trades: echt,
                       journal: ausbruch(["e1"])),
                 .init(broker: "Henry", kontonummer: "0000", waehrung: "EUR", trades: erfunden,
                       journal: ausbruch(["b1"]), beispiel: true)],
        zeitzone: berlin, erstellt: zeit("2026-10-08T18:00:00"))
}

private let karte = Setup(name: "Ausbruch", pruefungNachTrades: 3)

/// Wie die App (`ExportOrdner.export`): Karte mit Standard-Risiko und Prüfstand, über die Datei gelesen.
private func mitPlaybook(_ export: JournalExport) throws -> JournalExport {
    var e = export
    e.playbook = [JournalExport.Playbookkarte(karte, standardRisiko: 10, pruefung: e.setuppruefungen([karte]))]
    return try JournalExport.lese(try e.json())
}

@Test func setuppruefungZaehltDemoUndEchtgeldGetrenntOhneBeispielkonto() throws {
    let staende = beispielExport().setuppruefungen([karte])
    let demo = try #require(staende.first { $0.kontoart == "demo" })
    let echt = try #require(staende.first { $0.kontoart == "echt" })
    #expect(staende.count == 2)
    // (-0,5 + 0,2 - 0,1) ÷ 3: fällig und nicht positiv.
    #expect(demo.anzahl == 3 && demo.faellig && demo.nichtBestanden)
    #expect(demo.anzahlMitR == 3 && demo.anzahlRAngenommen == 3)
    // Das Beispielkonto (b1, +5 R) zählt nicht mit.
    #expect(echt.anzahl == 1 && !echt.faellig && !echt.nichtBestanden)
}

@Test func fremdwaehrungOhneKursZaehltOhneAngenommenesR() {
    let usd = trade("u1", "2026-10-05", netto: 30, waehrung: "USD")
    let export = JournalExport(
        konten: [.init(broker: "IBKR", kontonummer: "U7775678", waehrung: "EUR", trades: [usd],
                       journal: ausbruch(["u1"]))],
        zeitzone: berlin, erstellt: zeit("2026-10-08T18:00:00"))
    let stand = export.setuppruefungen([karte])
    // Gezählt ja, aber 30 USD gegen 10 Euro geplantes Risiko gäbe ein falsches R.
    #expect(stand.first?.anzahl == 1 && stand.first?.anzahlMitR == 0 && stand.first?.erwartungswertR == nil)
}

@Test func playbookkarteMitStandardRisikoUndPruefungUeberDieDatei() throws {
    let export = try mitPlaybook(beispielExport())
    let k = try #require(export.playbook?.first)
    #expect(k.standardRisiko == 10 && k.pruefungNachTrades == 3)
    #expect(k.pruefung?.map(\.kontoart) == ["demo", "echt"])
    #expect(export.konten.map(\.art) == [.demo, .echt, .echt])
}

@Test func demoKontoHeisstSoUndLaesstSichWaehlen() throws {
    let export = try mitPlaybook(beispielExport())
    #expect(export.bezeichnung(export.konten[0]) == "XTB …1234 (Demo)")
    #expect(export.bezeichnung(export.konten[1]) == "IBKR …5678 (Echtgeld)")
    #expect(export.bezeichnung(export.konten[2]) == "Henry …0000 (Beispielkonto)")
    let demo = try Anfrage.lies(["konto": "demo", "monat": "2026-10"], export: export)
    #expect(demo.konto.kontonummer == "501234")
    // Der reine Kurzname (Frag Henry) trifft weiter.
    #expect(try Anfrage.lies(["konto": "IBKR …5678", "monat": "2026-10"], export: export).konto.broker == "IBKR")
    #expect(try Anfrage.lies(["konto": "echtgeld", "monat": "2026-10"], export: export).konto.broker == "IBKR")

    let text = Ausgabe.auswertung(demo)
    #expect(text.contains("Konto XTB …1234 (Demo), Beträge in EUR. Demo- oder Paper-Konto ohne echtes Geld"))
    #expect(text.contains("## Prüfung der Setups (Kill-Kriterium; alle Demo-Konten, alle Zeiträume, gezählt in der App)"))
    #expect(text.contains("| Ausbruch | 3 | 3 | -0,13 R (3, davon 3 angenommen) | FÄLLIG, Kill-Kriterium erreicht |"))
    #expect(text.contains("und das Setup geht nach der eigenen Regel nicht auf Echtgeld."))
    #expect(text.contains("Antwort: Fällige Prüfungen im Review"))

    // Im Echtgeld-Konto nur dessen Stand, ohne Demo-Satz.
    let echt = Ausgabe.tiefenanalyse(try Anfrage.lies(["konto": "IBKR", "monat": "2026-10"], export: export))
    #expect(echt.contains("alle Echtgeld-Konten") && echt.contains("| Ausbruch | 1 | 3 |"))
    #expect(echt.contains("noch 2 Trades bis zur Prüfung") && !echt.contains("Demo- oder Paper-Konto"))
}

@Test func statusNenntKontoartUndPruefstand() throws {
    let export = try mitPlaybook(beispielExport())
    let text = Verbindungsstatus.text(.geladen(export), ordner: "/x", jetzt: zeit("2026-10-08T19:00:00"))
    #expect(text.contains("Konten: XTB …1234 Demo/Paper, IBKR …5678 Echtgeld, Henry …0000 Beispielkonto."))
    #expect(text.contains("Prüfung der Setups (Kill-Kriterium nach N Trades, Erwartungswert in R nach Kosten): "
        + "Ausbruch (Demo) 3 von 3 Trades, Erwartungswert -0,13 R: FÄLLIG, Kill-Kriterium erreicht; "
        + "Ausbruch (Echtgeld) 1 von 3 Trades."))
    #expect(!text.contains("WARNUNG"))
}

@Test func warnungBeiAnderemRechenkern() throws {
    var export = beispielExport()
    #expect(Verbindungsstatus.versionswarnung(export) == nil)
    #expect(Verbindungsstatus.mitVersionswarnung("Text", export: export) == "Text")
    // App nach Update neuer als die Erweiterung (Tims Befund 17.10.: Erweiterung 0.18.1 mit Kern 0.26.1).
    export.rechenkern = "99.0.0"
    let warnung = try #require(Verbindungsstatus.versionswarnung(export))
    #expect(warnung.hasPrefix("WARNUNG, ERWEITERUNG VERALTET: Henry rechnet mit Rechenkern 99.0.0"))
    #expect(warnung.contains("Claude Desktop neu starten"))
    #expect(Verbindungsstatus.mitVersionswarnung("Text", export: export) == warnung + "\n\nText")
    let status = Verbindungsstatus.text(.geladen(export), ordner: "/x", jetzt: zeit("2026-10-08T19:00:00"))
    #expect(status.contains(warnung))
}

@Test func versionenAlsZahlenVerglichen() {
    #expect(Verbindungsstatus.istNeuer("0.29.0", als: "0.26.1"))
    #expect(Verbindungsstatus.istNeuer("0.10.0", als: "0.9.9"))
    #expect(!Verbindungsstatus.istNeuer("0.9", als: "0.9.0"))
    #expect(!Verbindungsstatus.istNeuer("0.26.1", als: "0.29.0"))
}

@Test func erweiterungMeldetIhrenStandImExportOrdner() throws {
    let ordner = FileManager.default.temporaryDirectory.appending(path: "henry-stand-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: ordner) }
    let jetzt = zeit("2026-10-17T16:30:00")
    #expect(Exportdatei.meldeStand(ordner: ordner.path, jetzt: jetzt))
    let stand = try Erweiterungsstand.lese(try Data(contentsOf: ordner.appending(path: Erweiterungsstand.dateiname)))
    #expect(stand == Erweiterungsstand(erweiterung: Verbindungsstatus.connectorVersion, rechenkern: TradingCore.version,
                                       format: JournalExport.aktuellesFormat, geschrieben: jetzt))
    #expect(stand.passtZurApp)
    // Feldnamen sind mit AP11 abgesprochen; die App liest sie.
    let json = String(decoding: try stand.json(), as: UTF8.self)
    #expect(json == "{\"erweiterung\":\"\(Verbindungsstatus.connectorVersion)\",\"format\":2,"
        + "\"geschrieben\":\"2026-10-17T16:30:00Z\",\"rechenkern\":\"\(TradingCore.version)\"}")
    // Ohne Ordner oder mit fehlendem Ordner schreibt sie nichts.
    #expect(!Exportdatei.meldeStand(ordner: nil))
    #expect(!Exportdatei.meldeStand(ordner: ordner.appending(path: "fehlt").path))
}

@Test func betragsgrenzenFallenInFremderWaehrungWeg() throws {
    let usd = trade("u1", "2026-10-05", netto: 30, waehrung: "USD")
    let stand = Kontostandbezug(betrag: 5_000, seit: zeit("2026-10-01T00:00:00"))
    let regeln = Handelsregeln(maxMonatsverlust: 100, maxMonatsverlustProzent: 2, maxOffenePositionen: 2,
                               maxOffenesRisiko: 50, kontostand: stand)
    let export = JournalExport(
        konten: [.init(broker: "IBKR", kontonummer: "U7775678", waehrung: "EUR", trades: [usd], regeln: regeln)],
        zeitzone: berlin, erstellt: zeit("2026-10-08T18:00:00"))
    let r = try #require(try Anfrage.lies(["waehrung": "USD", "monat": "2026-10"], export: export).konto.regeln)
    // Beträge und der Kontostand stehen in Euro; die Anzahl offener Positionen gilt weiter.
    #expect(r.maxMonatsverlust == nil && r.maxOffenesRisiko == nil && r.kontostand == nil)
    #expect(r.maxOffenePositionen == 2)
}
