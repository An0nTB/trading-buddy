import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// A3 (Doc 38): Kursanalyse aus den Tageskerzen der App, mit eigenen Trades im Wert.

private let utc = TimeZone(secondsFromGMT: 0)!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

/// 20 Werktage vom 05.05. bis 30.05.2025, Schluss 101 bis 120, dazu der laufende 02.06. mit 130.
private func kerzen() -> [Kerze] {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = utc
    var liste: [Kerze] = []
    var tag = zeit("2025-05-05T00:00:00")
    var vorher: Decimal = 100
    while liste.count < 20 {
        if !kalender.isDateInWeekend(tag) {
            let schluss = vorher + 1
            liste.append(Kerze(tag: Journaltag(tag, zeitzone: utc), open: vorher, high: schluss + 1, low: vorher - 1,
                               close: schluss))
            vorher = schluss
        }
        tag = kalender.date(byAdding: .day, value: 1, to: tag)!
    }
    liste.append(Kerze(tag: Journaltag("2025-06-02")!, open: 120, high: 131, low: 119, close: 130, laufend: true))
    return liste
}

private func trade(_ id: String, _ symbol: String, netto: Decimal, waehrung: String? = "USD") -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: zeit("2025-05-12T09:00:00"),
          closeTime: zeit("2025-05-12T10:00:00"), openPrice: 100, closePrice: 100 + netto, profit: netto,
          waehrung: waehrung)
}

private func export(mitKursen: Bool = true) -> JournalExport {
    JournalExport(
        konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR",
                       trades: [trade("a", "BTC/USD", netto: 30), trade("b", "BTC/USD", netto: -10),
                                trade("c", "ETH/USD", netto: 5)])],
        zeitzone: TimeZone(identifier: "Europe/Berlin")!, erstellt: zeit("2025-06-02T12:00:00"),
        kursverlauf: mitKursen ? [.init(symbol: "BTCUSD", quelle: "kraken", waehrung: "usd",
                                        stand: zeit("2025-06-02T11:00:00"), kerzen: kerzen())] : [])
}

@Test func kursanalyseMitKennzahlenDesRechenkerns() throws {
    let text = Ausgabe.kursanalyse(export(), symbol: "btc-usd")
    let erwartet = try #require(Kursanalyse(kerzen: kerzen()))
    #expect(text.contains("# Henry · Kursanalyse BTCUSD (12 Monate)"))
    #expect(text.contains("Kurse: Tageskerzen von kraken in USD, abgerufen 02.06.2025 13:00, 20 abgeschlossene Tage "
        + "bis 2025-05-30 (UTC-Kalendertage)."))
    #expect(text.contains("| Letzter Schluss (2025-05-30) | 120,00 USD |"))
    #expect(text.contains("| Aktueller Kurs (laufender Tag, kein Schluss) | 130,00 USD |"))
    #expect(text.contains("| Veränderung 1 Woche | \(Format.prozent(erwartet.veraenderung[.woche])) |"))
    #expect(text.contains("| Veränderung 12 Monate | – |"))
    #expect(text.contains("| Schwankung aufs Jahr (12 Monate) | \(Format.prozent(erwartet.schwankungJahr)) |"))
    #expect(text.contains("| Durchschnittliche Tagesspanne (ATR 14) | \(Format.zahl(erwartet.atr14!)) USD ("))
    #expect(text.contains("| Größter Rückgang vom Hoch (12 Monate) | 0,0 % |") && !text.contains("(letzte 12 Monate)"))
    #expect(text.contains("| Kraken …4242 | USD | 2 | 20,00 | 50,0 % | – |"))
    #expect(!text.contains("| Kraken …4242 | USD | 3 |"))
    #expect(text.contains("hole_nachrichten mit begriff=BTCUSD und tage=7"))
    #expect(text.contains("## Rezept für die Kursanalyse (Henry)") && text.contains("keine Kauf- oder Verkaufssignale"))
    #expect(Ausgabe.kursanalyse(export(), symbol: "BTCUSD", monate: 0).contains("Kursanalyse BTCUSD (1 Monat)"))
    #expect(Ausgabe.datenstand(export()).contains("Kursverläufe (Tageskerzen) für 1 Werte: BTCUSD (hole_kursanalyse)."))
}

@Test func ohneKursverlaufNurEigeneTrades() {
    let fremd = Ausgabe.kursanalyse(export(), symbol: "ETH/USD")
    #expect(fremd.contains("Kein Kursverlauf in der App für ETH/USD. Kursverläufe gibt es für: BTCUSD."))
    #expect(fremd.contains("| Kraken …4242 | USD | 1 | 5,00 |") && !fremd.contains("## Kennzahlen"))
    #expect(Ausgabe.kursanalyse(export(mitKursen: false), symbol: "BTCUSD")
        .contains("Die App hat noch keine Kurse geladen."))
    #expect(Ausgabe.kursanalyse(export(), symbol: " ") == "SYMBOL FEHLT: `symbol` angeben, z. B. eines von: BTCUSD.")
    #expect(Ausgabe.kursanalyse(export(), symbol: "SOL").contains("Keine geschlossenen Trades seit"))
}

@Test func kursreiheUeberstehtDieRundreise() throws {
    let original = export()
    let json = String(decoding: try original.json(), as: UTF8.self)
    #expect(json.contains("\"laufend\":true") && json.contains("\"close\":\"120\""))
    #expect(try JournalExport.lese(Data(json.utf8)).kursverlauf == original.kursverlauf)
    // Eine unlesbare Kerze kostet nur die Kerzen dieser Reihe.
    let kaputt = json.replacingOccurrences(of: "\"close\":\"120\"", with: "\"close\":\"x\"")
    let gelesen = try JournalExport.lese(Data(kaputt.utf8))
    #expect(kaputt != json && gelesen.kursverlauf?.first?.kerzen.isEmpty == true && gelesen.konten[0].trades.count == 3)
    #expect(Ausgabe.kursanalyse(gelesen, symbol: "BTCUSD").contains("Für BTCUSD liegen keine abgeschlossenen Tageskerzen vor."))
}

/// Tägliche Kerzen über 400 Tage bis `ende`, Schluss steigt um 1 je Kerze; `wochenende` wie Krypto,
/// sonst nur Werktage wie eine Börse. Optional eine laufende Kerze am Tag nach `ende`.
private func langeReihe(bis ende: String, wochenende: Bool, laufend: Bool) -> JournalExport.Kursreihe {
    var kalender = Calendar(identifier: .gregorian)
    kalender.timeZone = utc
    let letzter = zeit(ende + "T00:00:00")
    var liste: [Kerze] = []
    var schluss: Decimal = 100
    for zurueck in stride(from: 400, through: 0, by: -1) {
        let tag = kalender.date(byAdding: .day, value: -zurueck, to: letzter)!
        guard wochenende || !kalender.isDateInWeekend(tag) else { continue }
        schluss += 1
        liste.append(Kerze(tag: Journaltag(tag, zeitzone: utc), open: schluss - 1, high: schluss + 1, low: schluss - 2,
                           close: schluss))
    }
    if laufend {
        let morgen = Journaltag(kalender.date(byAdding: .day, value: 1, to: letzter)!, zeitzone: utc)
        liste.append(Kerze(tag: morgen, open: schluss, high: schluss + 5, low: schluss, close: schluss + 3, laufend: true))
    }
    return .init(symbol: "X", quelle: "test", waehrung: "usd", stand: letzter, kerzen: liste)
}

@Test func veraenderungMitLaufenderKerzeUndOhneHandelstagAmStichtag() throws {
    // Befund G3 (Doc 49): Der Ausschnitt muss die Basis am oder bis 7 Tage vor dem Zieltag enthalten.
    let spannen: [(monate: Int, spanne: Kursanalyse.Spanne)] = [(1, .monat), (3, .quartal), (12, .jahr)]
    let faelle = [("2026-10-01", true, true), ("2026-10-03", false, false), ("2026-10-04", false, false),
                  ("2026-10-05", false, false), ("2026-10-06", false, true)]
    for (ende, wochenende, laufend) in faelle {
        let reihe = langeReihe(bis: ende, wochenende: wochenende, laufend: laufend)
        let voll = try #require(Kursanalyse(kerzen: reihe.kerzen))
        for (monate, spanne) in spannen {
            let ausschnitt = try #require(Ausgabe.analyse(reihe, monate: monate))
            #expect(ausschnitt.veraenderung[spanne] != nil, "\(ende) \(monate) Monate")
            #expect(ausschnitt.veraenderung[spanne] == voll.veraenderung[spanne], "\(ende) \(monate) Monate")
            #expect(ausschnitt.aktuellerKurs == voll.aktuellerKurs && ausschnitt.letzterTag == voll.letzterTag)
        }
    }
    let krypto = Ausgabe.kursanalyse(JournalExport(konten: [], zeitzone: utc, erstellt: zeit("2026-10-02T12:00:00"),
                                                   kursverlauf: [langeReihe(bis: "2026-10-01", wochenende: true,
                                                                            laufend: true)]), symbol: "X")
    #expect(!krypto.contains("| Veränderung 12 Monate | – |") && !krypto.contains("| Veränderung 1 Monat | – |"))
}

@Test func kennzahlenImmerUeberZwoelfMonate() throws {
    // Doc 59 B3: Bei monate unter 12 galten 52-Wochen-Abstände, Schwankung und Rückgang nur fürs Fenster.
    let reihe = langeReihe(bis: "2026-10-01", wochenende: true, laufend: false)
    let datei = JournalExport(konten: [], zeitzone: utc, erstellt: zeit("2026-10-02T12:00:00"), kursverlauf: [reihe])
    let voll = Ausgabe.kursanalyse(datei, symbol: "X")
    let kurz = Ausgabe.kursanalyse(datei, symbol: "X", monate: 3)
    let jahr = try #require(Ausgabe.analyse(reihe, monate: 12))
    for zeile in ["| Abstand zum 52-Wochen-Tief | \(Format.prozent(jahr.abstandTief52W)) |",
                  "| Schwankung aufs Jahr (12 Monate) | \(Format.prozent(jahr.schwankungJahr)) |",
                  "| Veränderung 12 Monate | \(Format.prozent(jahr.veraenderung[.jahr])) |"] {
        #expect(voll.contains(zeile) && kurz.contains(zeile), "\(zeile)")
    }
    #expect(kurz.contains("| Größter Rückgang vom Hoch (letzte 3 Monate) |") && !voll.contains("(letzte "))
    #expect(kurz.contains("\(jahr.anzahlKerzen) abgeschlossene Tage"))
}

@Test func beispielkontoUndNaeherungInDerKursanalyse() throws {
    // Doc 59 B2: erfundene Trades des Beispielkontos nicht neben echte Kurse. B8: Näherung der Kursreihe nennen.
    var datei = export()
    datei.konten.append(.init(broker: "Kraken", kontonummer: "0001", waehrung: "EUR",
                              trades: [trade("x", "BTC/USD", netto: 99)], beispiel: true))
    datei.kursverlauf?[0].naeherung = "Krypto-CFD des Brokers, Kurs von Kraken als Näherung"
    let gelesen = try JournalExport.lese(try datei.json())
    #expect(gelesen.konten.map(\.istBeispiel) == [false, true] && gelesen.kursverlauf == datei.kursverlauf)
    let text = Ausgabe.kursanalyse(gelesen, symbol: "BTCUSD")
    #expect(text.contains("| Kraken …4242 | USD | 2 | 20,00 |") && !text.contains("…0001"))
    #expect(text.contains("1 Trades des Beispielkontos der App sind erfunden und hier weggelassen"))
    #expect(text.contains("Näherung: Krypto-CFD des Brokers, Kurs von Kraken als Näherung. Die Kennzahlen beschreiben "
        + "diesen Kurs, nicht den gehandelten Wert selbst."))
    // Ohne die Felder (ältere App) wie bisher.
    let alt = Ausgabe.kursanalyse(export(), symbol: "BTCUSD")
    #expect(!alt.contains("Beispielkontos") && !alt.contains("Näherung:"))
    let altJSON = String(decoding: try export().json(), as: UTF8.self)
    #expect(!altJSON.contains("beispiel") && !altJSON.contains("naeherung"))
}
