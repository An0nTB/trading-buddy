import Foundation
import Testing
@testable import TradingCore

/// Tagesnotiz, Bildverweise und verpasste Trades (Doc 18 F4). Sollwerte von Hand gerechnet (02.10.2026).
private let berlinZone = TimeZone(identifier: "Europe/Berlin")!

private func utcZeitpunkt(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func notizTrade(_ id: String, _ offen: String, netto: Decimal) -> Trade {
    let zeit = utcZeitpunkt(offen)
    return Trade(id: id, symbol: "DAX", side: .buy, lots: 1, openTime: zeit, closeTime: zeit.addingTimeInterval(600),
                 openPrice: 100, closePrice: 101, profit: netto)
}

@Test func kalendertagLesenSchreibenPruefen() throws {
    let tag = try #require(Journaltag("2026-10-02"))
    #expect(tag.description == "2026-10-02")
    #expect(Journaltag("2026-02-30") == nil)
    #expect(Journaltag("2026-2-3") == nil)
    #expect(Journaltag("2026-10-02x") == nil)
    #expect(Journaltag(jahr: 2028, monat: 2, tag: 29)?.description == "2028-02-29")
    #expect(Journaltag(jahr: 2026, monat: 1, tag: 5)?.description == "2026-01-05")
    // 22:30 UTC ist in Berlin schon der nächste Tag.
    #expect(Journaltag(utcZeitpunkt("2026-10-01T22:30:00Z"), zeitzone: berlinZone) == tag)
    // Tag der Zeitumstellung: Beginn um Mitternacht Berlin, noch Winterzeit (UTC+1).
    let umstellung = try #require(Journaltag("2026-03-29"))
    #expect(umstellung.beginn(in: berlinZone) == utcZeitpunkt("2026-03-28T23:00:00Z"))
    let fruehere = try #require(Journaltag("2026-09-30"))
    #expect(fruehere < tag)
    let daten = try JSONEncoder().encode([tag])
    #expect(String(decoding: daten, as: UTF8.self) == #"["2026-10-02"]"#)
    #expect(try JSONDecoder().decode([Journaltag].self, from: daten) == [tag])
    let falsch = Data(#"["2026-13-01"]"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode([Journaltag].self, from: falsch) }
}

@Test func bildverweisNurRelativImBilderordner() {
    #expect(Bildverweis.istGueltig("2026-10/3F2A9C.png"))
    #expect(Bildverweis.istGueltig("bild.JPG"))
    #expect(Bildverweis.istGueltig("a/b/c.heic"))
    #expect(!Bildverweis.istGueltig(""))
    #expect(!Bildverweis.istGueltig("/Users/tim/bild.png"))
    #expect(!Bildverweis.istGueltig("~/bild.png"))
    #expect(!Bildverweis.istGueltig("../geheim.png"))
    #expect(!Bildverweis.istGueltig("2026/../../x.png"))
    #expect(!Bildverweis.istGueltig("2026//x.png"))
    #expect(!Bildverweis.istGueltig("./x.png"))
    #expect(!Bildverweis.istGueltig("a\\b.png"))
    #expect(!Bildverweis.istGueltig("notiz.txt"))
    #expect(!Bildverweis.istGueltig("ohneendung"))
}

@Test func planVorDemHandelGegenOhnePlan() throws {
    let trades = [
        notizTrade("A1", "2026-03-02T08:00:00Z", netto: 30),
        notizTrade("A2", "2026-03-02T10:00:00Z", netto: -10),
        // 23:30 UTC am 2. März ist 00:30 am 3. März in Berlin.
        notizTrade("B1", "2026-03-02T23:30:00Z", netto: -40),
        notizTrade("C1", "2026-03-04T08:00:00Z", netto: 10),
        notizTrade("D1", "2026-03-05T08:00:00Z", netto: -6),
    ]
    let erstellt = utcZeitpunkt("2026-03-01T12:00:00Z")
    let tag02 = try #require(Journaltag("2026-03-02"))
    let tag03 = try #require(Journaltag("2026-03-03"))
    let tag05 = try #require(Journaltag("2026-03-05"))
    let tag06 = try #require(Journaltag("2026-03-06"))
    let notizen = [
        // Plan vor dem ersten Trade (07:00 UTC vor 08:00 UTC).
        Tagesnotiz(tag: tag02, plan: "Nur Ausbrüche über 18.000",
                   planErstellt: utcZeitpunkt("2026-03-02T07:00:00Z"), erstellt: erstellt),
        // Plan erst nach dem Trade geschrieben.
        Tagesnotiz(tag: tag03, plan: "Ruhig bleiben",
                   planErstellt: utcZeitpunkt("2026-03-03T09:00:00Z"), erstellt: erstellt),
        // Leerer Plan zählt nicht.
        Tagesnotiz(tag: tag05, plan: "  \n",
                   planErstellt: utcZeitpunkt("2026-03-05T06:00:00Z"), rueckblick: "Zu früh rein", erstellt: erstellt),
        // Tag ohne Trades fällt heraus.
        Tagesnotiz(tag: tag06, plan: "Kein Handel",
                   planErstellt: utcZeitpunkt("2026-03-06T06:00:00Z"), erstellt: erstellt),
    ]
    let w = Planwirkung(trades: trades, notizen: notizen, zeitzone: berlinZone)
    #expect(w.tageMitPlan == 1 && w.tradesMitPlan == 2 && w.nettoMitPlan == 20)
    #expect(w.tageOhnePlan == 3 && w.tradesOhnePlan == 3 && w.nettoOhnePlan == -36)
    #expect(w.nettoJeTagMitPlan == 20)
    #expect(w.nettoJeTagOhnePlan == -12)
    #expect(w.tageMitPlanListe.map(\.description) == ["2026-03-02"])
    #expect(!w.genugDaten)
    let leer = Planwirkung(trades: [], notizen: notizen, zeitzone: berlinZone)
    #expect(leer.nettoJeTagMitPlan == nil && leer.nettoJeTagOhnePlan == nil)
}

@Test func verpassteTradesJeGrund() {
    let zeit = utcZeitpunkt("2026-03-02T09:00:00Z")
    let verpasst = [
        VerpassterTrade(id: "v1", zeit: zeit, symbol: "DAX", seite: .buy, setup: "Pullback", grund: .zoegern,
                        ergebnisR: 2),
        VerpassterTrade(id: "v2", zeit: zeit, symbol: "DAX", seite: .sell, grund: .zoegern),
        VerpassterTrade(id: "v3", zeit: zeit, symbol: "EURUSD", seite: .buy, setup: "Ausbruch", grund: .zuSpaet,
                        ergebnisR: -1),
        VerpassterTrade(id: "v4", zeit: zeit, symbol: "DAX", seite: .buy, grund: .regelSperre, ergebnisR: 3),
        VerpassterTrade(id: "v5", zeit: zeit, symbol: "Gold", seite: .sell, setup: "Pullback", grund: .sonstiges,
                        ergebnisR: Decimal(string: "0.5")),
    ]
    let a = VerpassteAuswertung(verpasst)
    #expect(a.anzahl == 5 && a.gewollt == 1)
    #expect(a.entgangenR == Decimal(string: "1.5"))
    let gruende: [VerpassterTrade.Grund] = a.jeGrund.map(\.grund)
    #expect(gruende == [.zoegern, .zuSpaet, .regelSperre, .sonstiges])
    let anzahlen: [Int] = a.jeGrund.map(\.anzahl)
    #expect(anzahlen == [2, 1, 1, 1])
    let mitSchaetzung: [Int] = a.jeGrund.map(\.mitSchaetzung)
    #expect(mitSchaetzung == [1, 1, 1, 1])
    let summen: [Decimal] = a.jeGrund.map(\.summeR)
    #expect(summen == [2, -1, 3, Decimal(string: "0.5")!])
    #expect(a.jeSetup == ["Pullback": 2, "Ausbruch": 1])
    #expect(VerpassteAuswertung([]).jeGrund.isEmpty)
}
