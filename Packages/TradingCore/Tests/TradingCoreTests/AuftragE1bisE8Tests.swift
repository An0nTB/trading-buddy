import Foundation
import Testing
@testable import TradingCore

/// Prüfkriterien aus Tims Auftrag vom 17.10.2026 (E1 bis E8), wörtlich als Tests. Erfundene Trades, Zeiten in
/// Berlin (Oktober UTC+2). 15.10.2026 ist ein Donnerstag, 16.10. ein Freitag, 19.10. ein Montag.
private func zeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func trade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, symbol: String = "DE40",
                   kurs: (Decimal, Decimal) = (100, 100), stop: Decimal? = nil) -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: zeit(auf), closeTime: zeit(zu),
          openPrice: kurs.0, closePrice: kurs.1, stopLoss: stop, profit: netto)
}

private let berlin = TimeZone(identifier: "Europe/Berlin")!
private func kurz(_ v: [Regelverstoss]) -> [String] { v.map { "\($0.trade) \($0.art.rawValue)" } }

// MARK: E2 Prozent vom Kontostand

@Test func e2TagesgrenzeEinsKommaFuenfProzentVon1200() {
    // „Tagesgrenze 1,5 % bei 1.200 € meldet ab 18 € Tagesverlust.“
    let regeln = Handelsregeln(maxTagesverlustProzent: Decimal(string: "1.5"),
                               kontostand: Kontostandbezug(betrag: 1200, seit: zeit("2026-10-01T00:00:00Z")))
    let genau18 = [trade("A1", "2026-10-19T07:00:00Z", "2026-10-19T07:30:00Z", netto: -18),
                   trade("A2", "2026-10-19T08:00:00Z", "2026-10-19T08:30:00Z", netto: 5)]
    #expect(kurz(Regelpruefung.pruefe(genau18, regeln: regeln, zeitzone: berlin)) == ["A2 tagesverlust"])
    let darunter = [trade("B1", "2026-10-19T07:00:00Z", "2026-10-19T07:30:00Z", netto: Decimal(string: "-17.99")!),
                    trade("B2", "2026-10-19T08:00:00Z", "2026-10-19T08:30:00Z", netto: 5)]
    #expect(Regelpruefung.pruefe(darunter, regeln: regeln, zeitzone: berlin).isEmpty)
}

@Test func e2KontostandWirdMitErgebnissenFortgeschrieben() {
    let bezug = Kontostandbezug(betrag: 1200, seit: zeit("2026-10-15T00:00:00Z"))
    let trades = [trade("G1", "2026-10-15T07:00:00Z", "2026-10-15T08:00:00Z", netto: 200),
                  trade("V1", "2026-10-14T07:00:00Z", "2026-10-14T08:00:00Z", netto: -100)]
    #expect(bezug.stand(bei: zeit("2026-10-16T00:00:00Z"), trades: trades) == 1400)
    // Vor dem Startwert: Ergebnisse dazwischen werden abgezogen.
    #expect(bezug.stand(bei: zeit("2026-10-14T00:00:00Z"), trades: trades) == 1300)
    // Nach dem Gewinn gilt 1,5 % von 1.400 € = 21 €: 18 € Verlust reichen dann nicht.
    let regeln = Handelsregeln(maxTagesverlustProzent: Decimal(string: "1.5"), kontostand: bezug)
    let folgetag = trades + [trade("H1", "2026-10-16T07:00:00Z", "2026-10-16T07:30:00Z", netto: -18),
                             trade("H2", "2026-10-16T08:00:00Z", "2026-10-16T08:30:00Z", netto: 1)]
    #expect(Regelpruefung.pruefe(folgetag, regeln: regeln, zeitzone: berlin).isEmpty)
}

@Test func e2EngereGrenzeGiltUndOhneKontostandNurBetrag() {
    #expect(Handelsregeln.grenze(betrag: 30, prozent: Decimal(string: "1.5"), stand: 1200) == 18)
    #expect(Handelsregeln.grenze(betrag: 10, prozent: Decimal(string: "1.5"), stand: 1200) == 10)
    #expect(Handelsregeln.grenze(betrag: nil, prozent: Decimal(string: "1.5"), stand: nil) == nil)
    #expect(Handelsregeln.grenze(betrag: nil, prozent: 1, stand: -5) == nil)
}

@Test func e2RisikoJeTradeInProzent() {
    // 0,5 % von 1.200 € = 6 €; Stop 7 Punkte bei 1 € je Punkt ist darüber.
    let regeln = Handelsregeln(maxRisikoJeTradeProzent: Decimal(string: "0.5"),
                               kontostand: Kontostandbezug(betrag: 1200, seit: zeit("2026-10-01T00:00:00Z")))
    let t = [trade("R1", "2026-10-19T07:00:00Z", "2026-10-19T07:30:00Z", netto: 3, kurs: (100, 103), stop: 93)]
    #expect(kurz(Regelpruefung.pruefe(t, regeln: regeln, zeitzone: berlin)) == ["R1 risikoJeTrade"])
}

// MARK: E3 Monatsverlust

@Test func e3MonatsverlustAbUeberschreitenImKalendermonat() {
    let regeln = Handelsregeln(maxMonatsverlust: 60)
    let trades = [trade("M1", "2026-10-05T07:00:00Z", "2026-10-05T08:00:00Z", netto: -40),
                  trade("M2", "2026-10-12T07:00:00Z", "2026-10-12T08:00:00Z", netto: -20),
                  trade("M3", "2026-10-19T07:00:00Z", "2026-10-19T08:00:00Z", netto: 10),
                  // Neuer Monat: Zählung beginnt neu.
                  trade("M4", "2026-11-02T08:00:00Z", "2026-11-02T09:00:00Z", netto: 10)]
    #expect(kurz(Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin)) == ["M3 monatsverlust"])
    // 6 % von 1.000 € zu Monatsbeginn = 60 €, gleiches Ergebnis.
    let prozent = Handelsregeln(maxMonatsverlustProzent: 6,
                                kontostand: Kontostandbezug(betrag: 1000, seit: zeit("2026-10-01T00:00:00Z")))
    #expect(kurz(Regelpruefung.pruefe(trades, regeln: prozent, zeitzone: berlin)) == ["M3 monatsverlust"])
}

// MARK: E4 Trades je Tag je Setup

@Test func e4DreiDEPlusDreiUSKeinVerstossDerVierteDEschon() {
    let karten = [Setup(name: "Day-DE", maxTradesJeTag: 3), Setup(name: "Day-US", maxTradesJeTag: 3)]
    var trades: [Trade] = []
    var setups: [String: String] = [:]
    for n in 0..<3 {
        let de = trade("DE\(n + 1)", "2026-10-19T0\(7 + n):00:00Z", "2026-10-19T0\(7 + n):30:00Z", netto: 5)
        let us = trade("US\(n + 1)", "2026-10-19T1\(4 + n):00:00Z", "2026-10-19T1\(4 + n):30:00Z", netto: 5,
                       symbol: "US500")
        trades += [de, us]
        setups[de.id] = "Day-DE"
        setups[us.id] = "day-us " // Schreibweise im Journal zählt nicht
    }
    let regeln = Handelsregeln(maxTradesJeTag: 6)
    #expect(Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin, setups: setups, playbook: karten).isEmpty)
    let vierter = trade("DE4", "2026-10-19T10:15:00Z", "2026-10-19T10:45:00Z", netto: 5)
    setups[vierter.id] = "Day-DE"
    let v = Regelpruefung.pruefe(trades + [vierter], regeln: regeln, zeitzone: berlin, setups: setups,
                                 playbook: karten)
    #expect(kurz(v) == ["DE4 tradesJeSetup", "US3 tradesJeTag"])
}

// MARK: E5 Haltedauer

@Test func e5DayTradeUeberNachtIstVerstossHaltedauer() {
    let karten = [Setup(name: "Day-DE", haltedauer: .gleicherTag), Setup(name: "Swing", haltedauer: .keinWochenende)]
    let trades = [trade("N1", "2026-10-19T18:00:00Z", "2026-10-20T07:30:00Z", netto: 5),
                  trade("N2", "2026-10-19T07:00:00Z", "2026-10-19T15:00:00Z", netto: 5),
                  trade("S1", "2026-10-15T09:00:00Z", "2026-10-16T09:00:00Z", netto: 5, symbol: "SAP"),
                  trade("S2", "2026-10-16T09:00:00Z", "2026-10-19T09:00:00Z", netto: 5, symbol: "SAP")]
    let setups = ["N1": "Day-DE", "N2": "Day-DE", "S1": "Swing", "S2": "Swing"]
    let v = Regelpruefung.pruefe(trades, regeln: Handelsregeln(), zeitzone: berlin, setups: setups, playbook: karten)
    #expect(kurz(v) == ["S2 haltedauer", "N1 haltedauer"])
    #expect(v.first { $0.trade == "N1" }?.art == .haltedauer)
}

@Test func e5OffenerDayTradeAmFolgetagIstVerstoss() {
    let karten = [Setup(name: "Day-DE", haltedauer: .gleicherTag)]
    let offen = [OffenerTrade(id: "O1", openTime: zeit("2026-10-19T18:00:00Z"))]
    let amAbend = Regelpruefung.pruefe([], regeln: Handelsregeln(), zeitzone: berlin, setups: ["O1": "Day-DE"],
                                       playbook: karten, offene: offen, jetzt: zeit("2026-10-19T21:00:00Z"))
    #expect(amAbend.isEmpty)
    let morgens = Regelpruefung.pruefe([], regeln: Handelsregeln(), zeitzone: berlin, setups: ["O1": "Day-DE"],
                                       playbook: karten, offene: offen, jetzt: zeit("2026-10-20T06:00:00Z"))
    #expect(kurz(morgens) == ["O1 haltedauer"])
}

// MARK: E6 Offene Positionen und offenes Risiko

@Test func e6VierteOffenePositionBeiGrenzeDreiIstVerstoss() {
    let regeln = Handelsregeln(maxOffenePositionen: 3)
    let trades = [trade("P1", "2026-10-15T09:00:00Z", "2026-10-20T09:00:00Z", netto: 5, symbol: "SAP"),
                  trade("P2", "2026-10-15T10:00:00Z", "2026-10-20T09:00:00Z", netto: 5, symbol: "ALV"),
                  // P3 schließt vor P5: Danach ist wieder Platz.
                  trade("P3", "2026-10-15T11:00:00Z", "2026-10-16T09:00:00Z", netto: 5, symbol: "BAS"),
                  trade("P5", "2026-10-19T09:00:00Z", "2026-10-20T09:00:00Z", netto: 5, symbol: "MBG")]
    let offen = [OffenerTrade(id: "P4", openTime: zeit("2026-10-15T12:00:00Z"))]
    // P4 ist die vierte neben P1 bis P3. Bei P5 ist P3 zu, aber P1, P2 und P4 sind offen: wieder die vierte.
    let v = Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin, offene: offen)
    #expect(kurz(v) == ["P4 offenePositionen", "P5 offenePositionen"])
    // Ohne P4 bleiben bei P5 nur P1 und P2 offen.
    #expect(Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin).isEmpty)
}

@Test func e6OffenesRisikoUeberDerGrenze() {
    // Swing: höchstens 6 % offenes Risiko; bei 1.000 € sind das 60 €.
    let regeln = Handelsregeln(maxOffenesRisikoProzent: 6,
                               kontostand: Kontostandbezug(betrag: 1000, seit: zeit("2026-10-01T00:00:00Z")))
    let trades = [trade("Q1", "2026-10-15T09:00:00Z", "2026-10-20T09:00:00Z", netto: 50, symbol: "SAP",
                        kurs: (100, 150), stop: 70)]
    let offen = [OffenerTrade(id: "Q2", openTime: zeit("2026-10-16T09:00:00Z"), risiko: 25),
                 OffenerTrade(id: "Q3", openTime: zeit("2026-10-16T10:00:00Z"), risiko: 10)]
    // Q1 30 €, Q2 25 € = 55 €; mit Q3 65 € über 60 €.
    #expect(kurz(Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: berlin, offene: offen)) == ["Q3 offenesRisiko"])
}

// MARK: E7 Kill-Kriterium

@Test func e7ExportEnthaeltAnzahlErwartungswertUndFaelligkeit() throws {
    let karte = Setup(name: "Day-DE", pruefungNachTrades: 50)
    // 50 Demo-Trades: 20 mal +2 R, 30 mal −1 R; Erwartungswert (40 − 30) / 50 = 0,2 R.
    var demo: [Trade] = []
    for n in 0..<50 {
        let gewinn = n < 20
        let auf = zeit("2026-10-01T08:00:00Z").addingTimeInterval(Double(n) * 3600)
        demo.append(Trade(id: "D\(n)", symbol: "DE40", side: .buy, lots: 1, openTime: auf,
                          closeTime: auf.addingTimeInterval(600), openPrice: 100, closePrice: gewinn ? 120 : 90,
                          stopLoss: 90, profit: gewinn ? 20 : -10))
    }
    let setups = Dictionary(uniqueKeysWithValues: demo.map { ($0.id, "Day-DE") })
    let echt = [trade("E1", "2026-10-02T08:00:00Z", "2026-10-02T09:00:00Z", netto: -10, kurs: (100, 90), stop: 90)]
    let stand = Setuppruefung.berechne(playbook: [karte], konten: [(.demo, demo, setups), (.echt, echt, ["E1": "Day-DE"])])
    #expect(stand.map(\.kontoart) == ["echt", "demo"])
    let d = try #require(stand.first { $0.kontoart == "demo" })
    #expect(d.anzahl == 50)
    #expect(d.erwartungswertR == Decimal(string: "0.2"))
    #expect(d.faellig)
    #expect(!d.nichtBestanden)
    let e = try #require(stand.first { $0.kontoart == "echt" })
    #expect(!e.faellig)

    let export = JournalExport(konten: [], zeitzone: berlin, erstellt: zeit("2026-10-19T00:00:00Z"),
                               playbook: [JournalExport.Playbookkarte(karte, standardRisiko: 12, pruefung: stand)])
    let json = String(decoding: try export.json(), as: UTF8.self)
    #expect(json.contains("\"pruefung\":[{\"anzahl\":50"))
    #expect(json.contains("\"faellig\":true"))
    #expect(json.contains("\"erwartungswertR\":0.2"))
    // E8: Standard-Risiko je Setup in der Playbookkarte.
    #expect(json.contains("\"standardRisiko\":12"))
    let gelesen = try JournalExport.lese(try export.json())
    #expect(gelesen.playbook?.first?.pruefung?.count == 2)
    #expect(gelesen.playbook?.first?.setupRegeln.pruefungNachTrades == 50)
}

// MARK: E1 Demo oder Echtgeld

@Test func e1KennzeichenImExportUndAeltereDateiGiltAlsEchtgeld() throws {
    let demo = JournalExport.Kontodaten(broker: "XTB", kontonummer: "1234567", waehrung: "EUR", trades: [],
                                        kontoart: .demo)
    let export = JournalExport(konten: [demo], zeitzone: berlin, erstellt: zeit("2026-10-19T00:00:00Z"))
    let json = String(decoding: try export.json(), as: UTF8.self)
    #expect(json.contains("\"kontoart\":\"demo\""))
    #expect(try JournalExport.lese(try export.json()).konten.first?.art == .demo)
    let alt = json.replacingOccurrences(of: ",\"kontoart\":\"demo\"", with: "")
    #expect(!alt.contains("kontoart"))
    #expect(try JournalExport.lese(Data(alt.utf8)).konten.first?.art == .echt)
}
