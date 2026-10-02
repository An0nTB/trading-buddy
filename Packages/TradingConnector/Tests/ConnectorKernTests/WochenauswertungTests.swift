import Foundation
import Testing
import TradingCore
@testable import ConnectorKern

/// Connector 0.12.0: Wochenauswertung über `Zeitraumbericht` (Rechenkern 0.20.0, Doc 47), Kalenderwoche `kw`,
/// Ergebnis je Tag, Prop-Firm-Verstöße und Steuer-Orientierung wie in der App.

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "Z")! }

private func trade(_ id: String, _ schluss: String, netto: Decimal, stop: Decimal? = 90, waehrung: String? = nil,
                   art: Produktart = .aktie) -> Trade {
    Trade(id: id, symbol: waehrung == nil ? "SAP" : "BTCUSD", side: .buy, lots: 1,
          openTime: zeit(schluss).addingTimeInterval(-600), closeTime: zeit(schluss),
          openPrice: 100, closePrice: 100 + netto, stopLoss: stop, profit: netto, produktart: art, waehrung: waehrung)
}

// KW 19/2025 ist Montag 05.05. bis Sonntag 11.05.2025; x liegt davor im selben Steuerjahr, y danach.
private let woche = [trade("x", "2025-04-10T10:00:00", netto: -20),
                     trade("a", "2025-05-05T10:00:00", netto: 10),
                     trade("b", "2025-05-06T10:00:00", netto: -4, stop: nil),
                     trade("c", "2025-05-06T12:00:00", netto: 6),
                     trade("u", "2025-05-07T12:00:00", netto: 50, waehrung: "USD", art: .krypto),
                     trade("y", "2025-05-20T10:00:00", netto: 100)]

private func export(regeln: Handelsregeln? = nil, mitKurs: Bool = false) throws -> JournalExport {
    var datei = JournalExport(konten: [.init(broker: "Kraken", kontonummer: "4242", waehrung: "EUR", trades: woche,
                                             regeln: regeln)],
                              zeitzone: berlin, erstellt: zeit("2026-10-01T20:00:00"))
    if mitKurs {
        let tag = try #require(Journaltag("2025-05-07"))
        datei.referenzkurse = [JournalExport.Tageskurse(tag: tag, kurse: ["USD": try #require(Decimal(string: "1.25"))])]
    }
    return datei
}

@Test func kalenderwocheAlsArgumentUndTitel() throws {
    let datei = try export()
    let kw19 = try #require(Zeitspanne.kalenderwoche(jahr: 2025, woche: 19, zeitzone: berlin))
    for text in ["2025-W19", "2025-w19", " 2025-19 "] {
        #expect(try Anfrage.lies(["kw": text], export: datei).zeitraum == kw19)
    }
    // Gleiche Woche wie über einen Tag mit `woche`.
    #expect(try Anfrage.lies(["woche": "2025-05-08"], export: datei).zeitraum == kw19)
    for falsch in ["2025-W54", "2025", "W19", "2025-W19-1"] {
        #expect(throws: AnfrageFehler.ungueltigeKalenderwoche(falsch)) {
            try Anfrage.lies(["kw": falsch], export: datei)
        }
    }
    #expect(AnfrageFehler.ungueltigeKalenderwoche("2025-W54").text
        == "UNGÜLTIGE KALENDERWOCHE: „2025-W54“. Format JJJJ-Www nach ISO, etwa 2026-W40.")

    let text = Ausgabe.auswertung(try Anfrage.lies(["kw": "2025-W19"], export: datei))
    #expect(text.contains("KW 19/2025 (05.05.2025 bis 11.05.2025)") && text.contains("KW 18/2025 (28.04.2025 bis "))
    // Monate und freie Spannen behalten ihren Titel.
    #expect(Format.zeitraum(try #require(Zeitspanne.monat(jahr: 2025, monat: 5, zeitzone: berlin)), berlin) == "Mai 2025")
    let frei = try Anfrage.lies(["von": "2025-05-05", "bis": "2025-05-07"], export: datei)
    #expect(Format.zeitraum(frei.zeitraum, berlin) == "05.05.2025 bis 07.05.2025")
}

@Test func wocheRechnetWieDerZeitraumberichtDerApp() throws {
    let anfrage = try Anfrage.lies(["kw": "2025-W19"], export: try export())
    let b = anfrage.bericht()
    let app = Zeitraumbericht(trades: woche.filter { $0.waehrung == nil }, zeitraum: anfrage.zeitraum, zeitzone: berlin,
                              kontowaehrung: "EUR", musterAnzahl: .max)
    #expect(b.auswertung.kennzahlen == app.auswertung.kennzahlen && b.tage == app.tage)
    #expect(b.auswertung.kennzahlen == anfrage.auswertung().kennzahlen && b.auswertung.kennzahlen.netto == 12)
    #expect(b.tage.map(\.anzahl) == [1, 2] && b.tage.map(\.netto) == [10, 2])

    let text = Ausgabe.auswertung(anfrage)
    #expect(text.contains("## Tage (Schlusstag der Trades)"))
    #expect(text.contains(" 05.05.2025 | 1 | 10,00 |") && text.contains(" 06.05.2025 | 2 | 2,00 |"))
    #expect(text.contains("2 Handelstage, davon 2 im Plus und 0 im Minus."))
    // Ohne Kurs bleibt der USD-Trade draußen, wie bisher.
    #expect(!text.contains("07.05.2025 | 1 |"))
}

@Test func wocheMitUmrechnungZaehltDenUmgerechnetenTag() throws {
    let anfrage = try Anfrage.lies(["kw": "2025-W19"], export: try export(mitKurs: true))
    #expect(anfrage.umgerechnet == ["USD": 1])
    let b = anfrage.bericht()
    // 50 USD zu 1,25 = 40 EUR.
    #expect(b.auswertung.kennzahlen.netto == 52 && b.umgerechnet == 1 && b.tage.last?.netto == 40)
    #expect(b.auswertung.kennzahlen == anfrage.auswertung().kennzahlen)
    #expect(Ausgabe.auswertung(anfrage).contains(" 07.05.2025 | 1 | 40,00 |"))
}

@Test func steuerOrientierungNurInDerKontowaehrung() throws {
    let datei = try export(mitKurs: true)
    let text = Ausgabe.auswertung(try Anfrage.lies(["kw": "2025-W19"], export: datei))
    #expect(text.contains("## Steuer-Orientierung 2025 bis Ende des Zeitraums in EUR (keine Steuerberechnung)"))
    // Aktien: x, a, b, c bis Sonntag 11.05., y erst danach; Krypto: u zum Kurs in Euro.
    #expect(text.contains("| Aktien | 4 | 16,00 | \(Format.zahl(Decimal(-24))) | \(Format.zahl(Decimal(-8))) |"))
    #expect(text.contains("| Krypto (Haltefrist ein Jahr) | 1 | 40,00 | 0,00 | 40,00 |"))
    #expect(text.contains("maßgeblich sind Steuerbescheinigung und Steuerberatung") && !text.contains("ohne Euro-Kurs"))

    // Ohne Kurs in der Datei fehlt der Krypto-Trade in den Summen und wird genannt.
    let ohneKurs = Ausgabe.auswertung(try Anfrage.lies(["kw": "2025-W19"], export: try export()))
    #expect(ohneKurs.contains("| Krypto (Haltefrist ein Jahr) | 1 | 0,00 | 0,00 | 0,00 |"))
    #expect(ohneKurs.contains("1 Trades ohne Euro-Kurs fehlen in den Summen."))

    // Mit fremder Währung kein Steuerabschnitt.
    let usd = Ausgabe.auswertung(try Anfrage.lies(["kw": "2025-W19", "waehrung": "USD"], export: datei))
    #expect(!usd.contains("## Steuer-Orientierung") && usd.contains("## Tage (Schlusstag der Trades)"))
    #expect(Rezept.text.contains("„Steuer-Orientierung“ nur nennen, wenn danach gefragt wird"))
}

@Test func propFirmVerstoesseStattDesHinweises() throws {
    let firma = PropFirmRegeln(name: "Test", startkapital: 10_000, zeitzone: "Europe/Berlin", stopPflicht: true)
    let anfrage = try Anfrage.lies(["kw": "2025-W19"], export: try export(regeln: Handelsregeln(propFirm: firma)))
    let text = Ausgabe.auswertung(anfrage)
    #expect(anfrage.bericht().propFirmVerstoesse.map(\.trade) == ["b"])
    #expect(text.contains("Prop-Firm-Regeln, Trades mit Verstoß: Ohne Stop 1. Tages- und Gesamtverlust nur auf "
        + "realisierten Salden, offene Verluste fehlen; maßgeblich ist die Prüfung der Firma."))
    #expect(!text.contains("ihre Prüfung zeigt die App"))

    let sauber = try Anfrage.lies(["kw": "2025-W21"], export: try export(regeln: Handelsregeln(propFirm: firma)))
    #expect(Ausgabe.auswertung(sauber).contains("Prop-Firm-Regeln: kein Verstoß im Zeitraum (1 Trades geprüft)."))
    // In fremder Währung bleibt der Hinweis auf die App.
    let regeln = Handelsregeln(propFirm: firma)
    let usd = try Anfrage.lies(["kw": "2025-W19", "waehrung": "USD"], export: try export(regeln: regeln))
    #expect(Ausgabe.auswertung(usd).contains("ihre Prüfung zeigt die App"))
}

@Test func wochenvorlageOhneDatumNimmtDieLetzteAbgeschlosseneWoche() {
    // Freitag 02.10.2026, 00:30 in Berlin: letzte abgeschlossene Woche ist KW 39 (21.09. bis 27.09.2026).
    let text = Rezept.wochenvorlage(datum: nil, heute: zeit("2026-10-01T22:30:00"), zeitzone: berlin)
    #expect(text.contains("kw=2026-W39") && text.contains("KW 39/2026"))
    // Montag 05.01.2026 früh: die Woche davor ist KW 1/2026 (29.12.2025 bis 04.01.2026).
    #expect(Rezept.wochenvorlage(datum: "", heute: zeit("2026-01-05T06:00:00"), zeitzone: berlin).contains("kw=2026-W01"))
    #expect(Rezept.wochenvorlage(datum: "2025-05-14").contains("woche=2025-05-14"))
}
