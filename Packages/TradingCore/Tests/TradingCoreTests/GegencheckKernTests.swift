import Foundation
import Testing
@testable import TradingCore

/// Befunde K1–K7 aus dem Gesamt-Gegencheck (Doc 36). Erfundene Trades, Sollwerte von Hand (02.10.2026).
private func gcZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private let gcUTC = TimeZone(secondsFromGMT: 0)!

private func gcTrade(_ id: String, _ auf: String, _ zu: String, netto: Decimal, symbol: String = "SAP",
                     nurDatum: Bool = false, waehrung: String? = nil) -> Trade {
    Trade(id: id, symbol: symbol, side: .buy, lots: 1, openTime: gcZeit(auf), closeTime: gcZeit(zu),
          openPrice: 100, closePrice: 100, profit: netto, nurDatum: nurDatum, waehrung: waehrung)
}

// K1: Je Trade seine Währung.

@Test func gegencheckPositionsbildungUebernimmtWaehrung() throws {
    func a(_ id: String, _ zeit: String, _ seite: Side, _ betrag: Decimal) -> Ausfuehrung {
        Ausfuehrung(id: id, zeit: gcZeit(zeit), kennung: "BTC/USD", name: "BTC", seite: seite, menge: 1,
                    preis: abs(betrag), betrag: betrag, waehrung: "usd", produktart: .krypto)
    }
    let ergebnis = Positionsbildung.bilde([a("K", "2026-03-02T10:00:00Z", .buy, -100),
                                           a("V", "2026-03-06T10:00:00Z", .sell, 150)])
    let t = try #require(ergebnis.trades.first)
    #expect(t.waehrung == "USD" && t.profit == 50)
    #expect(t.waehrung(kontowaehrung: "eur") == "USD")
    #expect(gcTrade("E", "2026-03-02T10:00:00Z", "2026-03-02T11:00:00Z", netto: 1).waehrung(kontowaehrung: "eur") == "EUR")
}

@Test func gegencheckToepfeRechnenJeTradeWaehrung() throws {
    let usd = gcTrade("U", "2026-03-02T10:00:00Z", "2026-03-06T10:00:00Z", netto: 50, waehrung: "usd")
    let eur = gcTrade("E", "2026-03-02T10:00:00Z", "2026-03-06T11:00:00Z", netto: 10)
    // Euro-Konto: der USD-Trade zählt ohne Kurs nicht als Euro.
    let ohne = try #require(Steuerorientierung.toepfe([usd, eur], kontowaehrung: "EUR", jahr: 2026).first)
    #expect(ohne.gewinne == 10 && ohne.anzahl == 2 && ohne.ohneEuro == 1)
    // Mit Kurs 1,25 USD je Euro: 50 USD = 40 Euro.
    let kurse = Referenzkurse(kurse: [Journaltag("2026-03-06")!: ["USD": Decimal(string: "1.25")!]])
    let mit = try #require(Steuerorientierung.toepfe([usd, eur], kontowaehrung: "EUR", jahr: 2026, kurse: kurse).first)
    #expect(mit.gewinne == 50 && mit.ohneEuro == 0)
}

@Test func gegencheckTradeCodableMitWaehrung() throws {
    let usd = gcTrade("U", "2026-03-02T10:00:00Z", "2026-03-06T10:00:00Z", netto: 50, waehrung: "USD")
    let ohne = gcTrade("E", "2026-03-02T10:00:00Z", "2026-03-06T11:00:00Z", netto: 10)
    let daten = try JSONEncoder().encode([usd, ohne])
    #expect(try JSONDecoder().decode([Trade].self, from: daten) == [usd, ohne])
    let text = String(decoding: daten, as: UTF8.self)
    #expect(text.components(separatedBy: "\"waehrung\"").count == 2)
}

// K2: Bitpanda setzt Krypto nur für Kryptowährungen.

@Test func gegencheckBitpandaProduktartNachKlasse() throws {
    let csv = """
    Transaction ID,Timestamp,Transaction Type,In/Out,Amount Fiat,Fiat,Amount Asset,Asset,Asset market price,\
    Asset class,Fee,Fee asset
    SYN-1,2026-03-02T10:00:00+01:00,buy,incoming,100.00,EUR,0.001,BTC,100000.00,Cryptocurrency,0.00,EUR
    SYN-2,2026-03-02T11:00:00+01:00,buy,incoming,200.00,EUR,1,AAPL,200.00,Stock (derivative),0.00,EUR
    """
    let k = try BitpandaCSV.lies(csv)
    #expect(k.ausfuehrungen.map(\.id) == ["SYN-1", "SYN-2"])
    #expect(k.ausfuehrungen.map(\.produktart) == [.krypto, .unbekannt])
}

// K3: Trades ohne Uhrzeit fehlen auch im Vergleichsrest.

@Test func gegencheckMusterRestOhneTradesOhneUhrzeit() {
    let trades = [
        gcTrade("X1", "2026-03-02T09:00:00Z", "2026-03-02T09:30:00Z", netto: 10),
        gcTrade("X2", "2026-03-02T10:00:00Z", "2026-03-02T10:30:00Z", netto: 10),
        gcTrade("Y1", "2026-03-03T09:00:00Z", "2026-03-03T09:30:00Z", netto: -20),
        gcTrade("Y2", "2026-03-03T10:00:00Z", "2026-03-03T10:30:00Z", netto: 30),
        gcTrade("Z1", "2026-03-04T00:00:00Z", "2026-03-04T00:00:00Z", netto: -100, symbol: "ALV", nurDatum: true),
        gcTrade("Z2", "2026-03-04T00:00:00Z", "2026-03-04T00:00:00Z", netto: -100, symbol: "BAS", nurDatum: true),
    ]
    // Mit Uhrzeit: 4 Trades, netto +30. Nummer 1: X1, Y1 (−10); Nummer 2: X2, Y2 (+40).
    // Rest zu 1: (30 + 10) / 2 = 20, Effekt −5 − 20 = −25. Rest zu 2: (30 − 40) / 2 = −5, Effekt 20 + 5 = 25.
    let muster = MusterFinder.finde(trades, zeitzone: gcUTC, aufteilungen: [.tradeNummerAmTag], mindestanzahl: 2)
    #expect(muster.map(\.schluessel) == ["1", "2"])
    #expect(muster.map(\.anzahlRest) == [2, 2])
    #expect(muster.map(\.erwartungswertRest) == [20, -5])
    #expect(muster.map(\.effekt) == [-25, 25])
}

// K4: Plan und Tage nur mit Trades ohne Uhrzeit.

@Test func gegencheckPlanwirkungOhneUhrzeit() throws {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let erstellt = gcZeit("2026-03-01T00:00:00Z")
    func notiz(_ tag: String, _ plan: String) -> Tagesnotiz {
        Tagesnotiz(tag: Journaltag(tag)!, plan: "Plan", planErstellt: gcZeit(plan), erstellt: erstellt)
    }
    let trades = [
        gcTrade("A", "2026-03-02T00:00:00Z", "2026-03-02T00:00:00Z", netto: 10, nurDatum: true),
        gcTrade("B", "2026-03-03T00:00:00Z", "2026-03-03T00:00:00Z", netto: 20, nurDatum: true),
        gcTrade("C", "2026-03-04T00:00:00Z", "2026-03-04T00:00:00Z", netto: -30, nurDatum: true),
        gcTrade("D", "2026-03-05T00:00:00Z", "2026-03-05T00:00:00Z", netto: 5, nurDatum: true),
        gcTrade("E", "2026-03-05T09:00:00Z", "2026-03-05T09:30:00Z", netto: 5, symbol: "DAX"),
    ]
    let notizen = [
        notiz("2026-03-02", "2026-03-01T20:00:00Z"), // Vorabend: sicher vor dem Trade, mit Plan
        notiz("2026-03-03", "2026-03-03T08:00:00Z"), // im Lauf des Tages: unklar, zählt nirgends
        notiz("2026-03-04", "2026-03-05T08:00:00Z"), // erst am Folgetag: ohne Plan
        notiz("2026-03-05", "2026-03-05T07:00:00Z"), // vor dem Trade mit Uhrzeit (09:00): mit Plan
    ]
    let w = Planwirkung(trades: trades, notizen: notizen, zeitzone: berlin)
    #expect(w.tageMitPlan == 2 && w.tradesMitPlan == 3 && w.nettoMitPlan == 20)
    #expect(w.tageOhnePlan == 1 && w.tradesOhnePlan == 1 && w.nettoOhnePlan == -30)
    #expect(w.tageUnklar == 1)
    #expect(w.tageMitPlanListe.map(\.description) == ["2026-03-02", "2026-03-05"])
}

// K5: Teilverkäufe einer Position zählen als ein Trade.

@Test func gegencheckTeilverkaeufeZaehlenEinmal() throws {
    let p1 = gcTrade("P1", "2026-03-02T09:00:00Z", "2026-03-02T10:00:00Z", netto: -10)
    let p2 = gcTrade("P2", "2026-03-02T09:00:00Z", "2026-03-02T11:00:00Z", netto: -10)
    let p3 = gcTrade("P3", "2026-03-02T09:00:00Z", "2026-03-02T12:00:00Z", netto: -10)
    let n = gcTrade("N", "2026-03-02T13:00:00Z", "2026-03-02T13:30:00Z", netto: 5)
    let m = gcTrade("M", "2026-03-02T14:00:00Z", "2026-03-02T14:30:00Z", netto: 1)
    let trades = [p1, p2, p3, n, m]
    // Drei Eröffnungen am Tag: nur M ist die dritte. Vor N steht ein Verlust in Folge (eine Position), nicht drei.
    let regeln = Handelsregeln(maxTradesJeTag: 2, stoppNachVerlusten: 2)
    let verstoesse = Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: gcUTC)
    #expect(verstoesse.map(\.trade) == ["M"])
    #expect(verstoesse.map(\.art) == [.tradesJeTag])
    let stand = try #require(Regelpruefung.tagesstaende(trades, regeln: regeln, zeitzone: gcUTC).first)
    #expect(stand.trades == 3 && stand.netto == -24 && stand.verlusteInFolge == 0 && stand.verstoesse == 1)
    #expect(Regelpruefung.verlusteInFolge([p1, p2, p3]) == 1)
    let andere = gcTrade("X", "2026-03-02T10:30:00Z", "2026-03-02T10:45:00Z", netto: -5, symbol: "ALV")
    #expect(Regelpruefung.verlusteInFolge([p1, andere, p2]) == 2)

    let nummern = Kennzahlen.aufschluesseln(trades, nach: .tradeNummerAmTag, zeitzone: gcUTC)
    let anzahl = Dictionary(uniqueKeysWithValues: nummern.map { ($0.schluessel, $0.kennzahlen.anzahl) })
    #expect(anzahl == ["1": 3, "2": 1, "3": 1])
}

@Test func gegencheckUeberhandelnOhneTeilverkaeufe() {
    // Eine Position in vier Teilen am 02.03., je ein Trade an drei weiteren Tagen.
    // Früher: Tage 4, 1, 1, 1, Median 1, Grenze 3, der 02.03. galt als Überhandeln. Jetzt 1, 1, 1, 1.
    let teile = (1...4).map { gcTrade("P\($0)", "2026-03-02T09:00:00Z", "2026-03-02T1\($0):00:00Z", netto: 5) }
    let einzeln = ["03", "04", "05"].map { gcTrade("T\($0)", "2026-03-\($0)T09:00:00Z", "2026-03-\($0)T10:00:00Z", netto: 5) }
    let befunde = Fehlermuster.pruefe(teile + einzeln, zeitzone: gcUTC)
    #expect(!befunde.contains { $0.muster == .ueberhandeln })
    // Seit Tim 05.10.2026 rechnet die Regel bei 4 Tagen keinen Median mehr; die Prüfung oben träfe also
    // auch ohne Zusammenfassen nicht. Mit eigenem Limit 1 je Tag bleibt der 02.03. weiter unauffällig,
    // weil die vier Teile eine Position sind.
    var s = Fehlermuster.Schwellen()
    s.maxTradesProTag = 1
    let mitLimit = Fehlermuster.pruefe(teile + einzeln, zeitzone: gcUTC, schwellen: s)
    #expect(!mitLimit.contains { $0.muster == .ueberhandeln })
    #expect(Fehlermuster.tradesJeTag(teile + einzeln, zeitzone: gcUTC).values.allSatisfy { $0 == 1 })
}

// K7: Zellen weit rechts blähen Zeilen nicht auf.

@Test func gegencheckXLSXSpalteXFDWirdUebergangen() {
    let xml = """
    <worksheet><sheetData>\
    <row r="1"><c r="A1"><v>1</v></c><c r="XFD1"><v>2</v></c></row>\
    <row r="2"><c r="AMJ2"><v>3</v></c></row>\
    </sheetData></worksheet>
    """
    let zeilen = XLSXMappe.zeilen(Data(xml.utf8), texte: [])
    #expect(zeilen.map(\.count) == [1, 1_024])
    #expect(zeilen.first == ["1"] && zeilen.last?.last == "3")
}
