import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Ausgaben an Claude für den echten GBE-Monat Mai 2025 (Testdatei aus TradingCore, pseudonymisiert).
/// Sollwerte wie in TradingCore (Python-Rechnung 01.10.2026).
private func gbeExport() throws -> JournalExport {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../TradingCore/Tests/TradingCoreTests/Fixtures/MT4/gbe-2025-05-31-monthly.html")
    let auszug = try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                        serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    return JournalExport(
        konten: [.init(broker: auszug.broker, kontonummer: auszug.accountNumber, waehrung: "EUR",
                       positionen: auszug.closedPositions, geloescht: auszug.cancelledOrders)],
        zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: Date(timeIntervalSince1970: 1_790_000_000))
}

@Test func monatsauswertungEnthaeltZahlenUndRezept() throws {
    let text = Ausgabe.auswertung(try Anfrage.lies(["monat": "2025-05"], export: try gbeExport()))
    #expect(text.contains("# Trading Buddy · Auswertung Mai 2025"))
    #expect(text.contains("Vergleich: April 2025"))
    #expect(text.contains("| Trades (Gewinner/Verlierer) | 83 (54/29) | 0 (0/0) |"))
    #expect(text.contains("| Netto | 7,14 | 0,00 |"))
    #expect(text.contains("| Trefferquote | 65,1 % | – |"))
    #expect(text.contains("Max. Drawdown 37,20"))
    #expect(text.contains("Stornoquote 40,7 % (57 Orders gelöscht, 83 ausgeführt)"))
    #expect(text.contains("- Revanche-Trade: 13 Trades, netto -2,06"))
    #expect(text.contains("Ohne diese Trades: netto 9,20"))
    #expect(text.contains("| 90000076 |"))
    #expect(text.contains("## Rezept für die Antwort"))
    #expect(text.contains("Gespeichert insgesamt (alle Zeiträume): 83 Trades, geschlossen"))
    #expect(!text.contains("## Nach Setup") && text.contains("Setup 0, Regeltreue 0, Zustand 0, Grund 0 von 83"))
    // Nur die Endziffern des Kontos gehen an Claude.
    #expect(text.contains("…0001") && !text.contains("100001"))
}

@Test func datenstandUndListen() throws {
    let export = try gbeExport()
    let stand = Ausgabe.datenstand(export)
    #expect(stand.contains("83 Trades") && stand.contains("57 gelöschte Orders"))

    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export)
    let wochentage = Ausgabe.aufschluesselung(anfrage, nach: .wochentag)
    #expect(wochentage.contains("| Mo |") && wochentage.contains("Wochentag"))
    let schlechteste = Ausgabe.trades(anfrage, auswahl: .schlechteste, muster: nil, anzahl: 1)
    #expect(schlechteste.contains("| 90000016 |") && schlechteste.contains("-12,92"))
    #expect(schlechteste.contains("82 weitere Trades nicht gezeigt."))
    let revanche = Ausgabe.trades(anfrage, auswahl: .chronologisch, muster: .revancheTrade, anzahl: 50)
    #expect(revanche.components(separatedBy: "Revanche-Trade").count - 1 >= 13)
}

@Test func journalangabenErscheinenInAuswertungUndListen() throws {
    var export = try gbeExport()
    export.konten[0].journal = [
        "90000076": Journalangaben(setup: "Ausbruch", regeltreue: true, zustand: 4, grund: "Plan | eingehalten"),
        "90000016": Journalangaben(setup: "Rücksetzer", regeltreue: false, zustand: 2)
    ]
    let anfrage = try Anfrage.lies(["monat": "2025-05"], export: export)
    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Nach Setup (eigene Angabe im Journal)"))
    #expect(text.contains("| Ausbruch | 1 | 22,91 |"))
    #expect(text.contains("| Rücksetzer | 1 | -12,92 |"))
    #expect(text.contains("| ohne Angabe | 81 |"))
    #expect(text.contains("| Regel gebrochen | 1 |") && text.contains("| nach Regeln | 1 |"))
    #expect(text.contains("| 4 von 5 | 1 |"))
    #expect(text.contains("Setup 2, Regeltreue 2, Zustand 2, Grund 1 von 83"))

    let setups = Ausgabe.aufschluesselung(anfrage, nach: try #require(Aufschluesselung(rawValue: "setup")))
    #expect(setups.contains("# Trading Buddy · Setup") && setups.contains("| Ausbruch | 1 |"))
    #expect(Aufschluesselung(rawValue: "wochentag") == .kern(.wochentag))
    #expect(Aufschluesselung(rawValue: "unsinn") == nil)

    let beste = Ausgabe.trades(anfrage, auswahl: .beste, muster: nil, anzahl: 1)
    #expect(beste.contains("| 90000076 | Ausbruch | ja | 4/5 | – | Plan / eingehalten |"))
}

@Test func vorlagenNennenDasWerkzeug() {
    #expect(Rezept.monatsvorlage(monat: "2025-05").contains("hole_auswertung mit monat=2025-05"))
    #expect(Rezept.monatsvorlage(monat: nil).contains("letzte Monat mit Trades"))
    #expect(Rezept.wochenvorlage(datum: "2025-05-14").contains("woche=2025-05-14"))
}
