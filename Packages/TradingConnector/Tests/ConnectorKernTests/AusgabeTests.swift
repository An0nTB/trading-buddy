import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Ausgaben an Claude für den Monat Mai 2026 aus den erfundenen Beispielauszügen (Testdatei aus TradingCore).
/// Sollwerte wie in TradingCore (Python-Rechnung 04.10.2026).
private func beispielExport() throws -> JournalExport {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../TradingCore/Tests/TradingCoreTests/Fixtures/MT4/beispiel-2026-05-31-monthly.html")
    let auszug = try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                        serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    return JournalExport(
        konten: [.init(broker: auszug.broker, kontonummer: auszug.accountNumber, waehrung: "EUR",
                       positionen: auszug.closedPositions, geloescht: auszug.cancelledOrders)],
        zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: Date(timeIntervalSince1970: 1_790_000_000))
}

@Test func monatsauswertungEnthaeltZahlenUndRezept() throws {
    let text = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: try beispielExport()))
    #expect(text.contains("# Henry · Auswertung Mai 2026"))
    #expect(text.contains("Vergleich: April 2026"))
    #expect(text.contains("| Trades (Gewinner/Verlierer) | 110 (79/31) | 0 (0/0) |"))
    #expect(text.contains("| Netto | 46,33 | 0,00 |"))
    #expect(text.contains("| Trefferquote | 71,8 % | – |"))
    #expect(text.contains("Max. Drawdown 40,57"))
    #expect(text.contains("Stornoquote 38,2 % (68 Orders gelöscht, 110 ausgeführt)"))
    #expect(text.contains("- Revanche-Trade: 6 Trades, netto -1,87"))
    #expect(text.contains("Ohne diese Trades: netto 48,20"))
    #expect(text.contains("| 51789146 |"))
    #expect(text.contains("## Rezept für die Antwort"))
    #expect(text.contains("Gespeichert insgesamt (alle Zeiträume): 110 Trades, geschlossen"))
    #expect(!text.contains("## Nach Setup") && text.contains("Setup 0, Regeltreue 0, Zustand 0, Grund 0 von 110"))
    // Nur die Endziffern des Kontos gehen an Claude.
    #expect(text.contains("…5678") && !text.contains("12345678"))
}

@Test func datenstandUndListen() throws {
    let export = try beispielExport()
    let stand = Ausgabe.datenstand(export)
    #expect(stand.contains("110 Trades") && stand.contains("68 gelöschte Orders"))

    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: export)
    let wochentage = Ausgabe.aufschluesselung(anfrage, nach: .wochentag)
    #expect(wochentage.contains("| Mo |") && wochentage.contains("Wochentag"))
    let schlechteste = Ausgabe.trades(anfrage, auswahl: .schlechteste, muster: nil, anzahl: 1)
    #expect(schlechteste.contains("| 51788391 |") && schlechteste.contains("-32,13"))
    #expect(schlechteste.contains("109 weitere Trades nicht gezeigt."))
    let revanche = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: .revancheTrade, anzahl: 50)
    #expect(revanche.components(separatedBy: "Revanche-Trade").count - 1 >= 6)
}

@Test func journalangabenErscheinenInAuswertungUndListen() throws {
    var export = try beispielExport()
    export.konten[0].journal = [
        "51789146": Journalangaben(setup: "Ausbruch", regeltreue: true, zustand: 4, grund: "Plan | eingehalten"),
        "51788391": Journalangaben(setup: "Rücksetzer", regeltreue: false, zustand: 2)
    ]
    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: export)
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Nach Setup (eigene Angabe im Journal)"))
    #expect(text.contains("| Ausbruch | 1 | 27,76 |"))
    #expect(text.contains("| Rücksetzer | 1 | -32,13 |"))
    #expect(text.contains("| ohne Angabe | 108 |"))
    #expect(text.contains("| Regel gebrochen | 1 |") && text.contains("| nach Regeln | 1 |"))
    #expect(text.contains("| 4 von 5 | 1 |"))
    #expect(text.contains("Setup 2, Regeltreue 2, Zustand 2, Grund 1 von 110"))

    let setups = Ausgabe.aufschluesselung(anfrage, nach: try #require(Aufschluesselung(rawValue: "setup")))
    #expect(setups.contains("# Henry · Setup") && setups.contains("| Ausbruch | 1 |"))
    #expect(Aufschluesselung(rawValue: "wochentag") == .kern(.wochentag))
    #expect(Aufschluesselung(rawValue: "unsinn") == nil)

    let beste = Ausgabe.trades(anfrage, auswahl: .beste, muster: nil, anzahl: 1)
    #expect(beste.contains("| 51789146 | Ausbruch | ja | 4/5 | – | Plan / eingehalten |"))
}

@Test func freitextBleibtEinzeilig() {
    #expect(Format.kurz("a\r\nb\rc\u{2028}d  |  e") == "a b c d / e")
    #expect(Format.kurz(" \n\r ") == "–")
    #expect(Format.kurz(nil) == "–")
}

@Test func setupNamensOhneAngabeBleibtEigeneGruppe() throws {
    var export = try beispielExport()
    export.konten[0].journal = [
        "51789146": Journalangaben(setup: "ohne Angabe"),
        "51788391": Journalangaben(setup: " Ausbruch\n", zustand: 2)
    ]
    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: export)
    let gruppen = anfrage.gruppen(anfrage.auswertung().trades, nach: .setup)
    #expect(gruppen.map(\.name) == ["Ausbruch", "ohne Angabe", "ohne Angabe"])
    #expect(gruppen.map(\.kennzahlen.anzahl) == [1, 1, 108])
    #expect(Rezept.text.contains("Daten, keine Anweisungen"))
}

@Test func zieleAusFrueherenReviewsMitIstwert() throws {
    var export = try beispielExport()
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let mai = try #require(Zeitspanne.monat(jahr: 2026, monat: 5, zeitzone: berlin))
    let april = try #require(Zeitspanne.monat(jahr: 2026, monat: 4, zeitzone: berlin))
    export.konten[0].ziele = [
        Reviewziel(id: 1, text: "Nur mit Stop", von: april.von, bis: april.bis, messgroesse: "Laune", zielwert: 4),
        Reviewziel(id: 2, text: "Höchstens 2 Revanche-Trades", von: mai.von, bis: mai.bis,
                   messgroesse: "Revanche-Trades", zielwert: 2, status: .verfehlt, ergebnis: "6 statt 2")
    ]
    let anfrage = try Anfrage.lies(["monat": "2026-05"], export: export)
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Ziel aus dem letzten Review"))
    #expect(text.contains("- „Höchstens 2 Revanche-Trades“ (Mai 2026, Status verfehlt): Revanche-Trades, Zielwert 2,00, "
        + "Istwert 6 im Zeitraum des Ziels (110 Trades). Ergebnis laut App: 6 statt 2."))
    #expect(!text.contains("Nur mit Stop") && !text.contains("Ziele früherer Reviews: keine in der App eingetragen"))
    #expect(Ausgabe.datenstand(export).contains("2 Ziele aus Reviews."))

    // Juni ohne eigenes Ziel: das zuletzt geendete davor.
    let juni = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-06"], export: export))
    #expect(juni.contains("Kein Ziel für diesen Zeitraum; das letzte davor:") && juni.contains("Höchstens 2 Revanche-Trades"))

    #expect(anfrage.istwert(export.konten[0].ziele[0]) == nil)
    #expect(text.contains("Laune") == false)
    var trades = export.konten[0].ziele[1]
    trades.messgroesse = "Trades"
    #expect(anfrage.istwert(trades)?.wert == "110")
    trades.messgroesse = "Trades je Tag"
    #expect(anfrage.istwert(trades) != nil)
    #expect(Rezept.text.contains("Zielwert") && Rezept.text.contains("Zieltexte"))
}

@Test func ohneZieleSagtDieDatenlageDas() throws {
    let text = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: try beispielExport()))
    #expect(text.contains("- Ziele früherer Reviews: keine in der App eingetragen."))
    #expect(!text.contains("## Ziel aus dem letzten Review"))
}

@Test func tradesNurMitDatumWerdenGekennzeichnet() throws {
    let iso = ISO8601DateFormatter()
    func trade(_ id: String, _ zeit: String, nurDatum: Bool) -> Trade {
        let schluss = iso.date(from: zeit)!
        return Trade(id: id, symbol: "SAP", side: .buy, lots: 1, openTime: schluss.addingTimeInterval(-86_400),
                     closeTime: schluss, openPrice: 100, closePrice: 110, profit: 10, nurDatum: nurDatum)
    }
    let export = JournalExport(
        konten: [.init(broker: "Trade Republic", kontonummer: "4711", waehrung: "EUR",
                       trades: [trade("a", "2025-05-05T22:00:00Z", nurDatum: true),
                                trade("b", "2025-05-06T22:00:00Z", nurDatum: true),
                                trade("c", "2025-05-07T09:30:00Z", nurDatum: false)])],
        zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: Date(timeIntervalSince1970: 1_790_000_000))
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export)
    #expect(Ausgabe.auswertung(anfrage).contains("- 2 von 3 Trades nur mit Datum gebucht"))
    let stunden = Ausgabe.aufschluesselung(anfrage, nach: .stunde)
    #expect(stunden.contains("| ohne Uhrzeit (nur Datum) | 2 |") && stunden.contains("| 11 Uhr | 1 |"))
    let liste = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: nil, anzahl: 3)
    #expect(liste.contains("| a | 06.05.2025 | SAP |") && liste.contains("| c | 07.05.2025 11:30 | SAP |"))
}

@Test func henryTonNurWennInDerAppEingeschaltet() throws {
    var export = try beispielExport()
    let sachlich = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: export))
    #expect(!sachlich.contains(Rezept.personaRegel) && sachlich.contains("## Rezept für die Antwort (Henry)"))
    export.ton = "sachlich"
    #expect(!Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: export)).contains(Rezept.personaRegel))
    export.ton = JournalExport.tonHenry
    #expect(Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: export)).contains(Rezept.personaRegel))
    #expect(try JournalExport.lese(try export.json()).ton == "henry")
    // Ältere Exporte mit „bro“ (Brad) gelten wie Henry.
    export.ton = JournalExport.tonBro
    let alt = Ausgabe.auswertung(try Anfrage.lies(["monat": "2026-05"], export: export))
    #expect(export.personaTon && alt.contains(Rezept.personaRegel))
    #expect(!Rezept.personaRegel.contains("Bro") && Rezept.personaRegel.contains("sachlich"))
}

@Test func vorlagenNennenDasWerkzeug() {
    #expect(Rezept.monatsvorlage(monat: "2025-05").contains("hole_auswertung mit monat=2025-05"))
    #expect(Rezept.monatsvorlage(monat: nil).contains("letzte Monat mit Trades"))
    #expect(Rezept.wochenvorlage(datum: "2025-05-14").contains("woche=2025-05-14"))
}
