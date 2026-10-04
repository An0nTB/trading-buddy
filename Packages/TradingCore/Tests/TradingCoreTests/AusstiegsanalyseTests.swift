import Foundation
import Testing
@testable import TradingCore

/// Ausstiegsanalyse (Doc 39, F7). Erfundene Kerzen, Sollwerte von Hand gerechnet.
private func zeit(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "Z")! }

private func kerze(_ beginn: String, _ o: Decimal, _ h: Decimal, _ l: Decimal, _ c: Decimal,
                   dauer: Int = 60) -> Zeitkerze {
    Zeitkerze(beginn: zeit(beginn), dauer: dauer, open: o, high: h, low: l, close: c)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private let kauf = Trade(id: "k1", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-03-02T10:00:30"),
                         closeTime: zeit("2026-03-02T10:04:20"), openPrice: 100, closePrice: 103,
                         stopLoss: 98, profit: 30)

private let minutenkerzen = [
    kerze("2026-03-02T10:03:00", 103.5, 200, 102.5, 103),  // wird von der späteren Kerze gleichen Beginns ersetzt
    kerze("2026-03-02T10:00:00", 100, dez("100.5"), dez("99.5"), dez("100.2")),
    kerze("2026-03-02T10:01:00", dez("100.2"), 101, dez("98.5"), dez("100.8")),
    kerze("2026-03-02T10:02:00", dez("100.8"), 104, dez("100.5"), dez("103.5")),
    kerze("2026-03-02T10:03:00", dez("103.5"), dez("103.8"), dez("102.5"), 103),
    kerze("2026-03-02T10:04:00", 103, dez("103.2"), dez("102.8"), 103),
    kerze("2026-03-02T10:05:00", 103, dez("105.5"), dez("102.9"), 105),
    kerze("2026-03-02T10:30:00", 105, 105, 101, 101),
    kerze("2026-03-02T12:00:00", 90, 90, 90, 90),  // nach dem Nachlauf von einer Stunde
]

@Test func ausstiegKaufMitMinutenkerzen() throws {
    let a = try #require(Ausstiegsanalyse(trade: kauf, kerzen: minutenkerzen))
    #expect(a.tradeID == "k1" && a.ergebnis == .win && a.kerzenDauer == 60 && a.anzahlKerzen == 5)
    // 30 + 60 + 60 + 60 + 20 Sekunden von 230; Ränder unter einer Minute gelten nicht als unscharf.
    #expect(a.abdeckung == 1 && !a.unscharf)
    // Bestes Hoch 104 um 10:02, tiefstes Tief 98,5 um 10:01; Ausstieg bei +3.
    #expect(a.erzielt == 3 && a.mfe == 4 && a.mae == dez("1.5"))
    #expect(a.zeitMFE == zeit("2026-03-02T10:02:00") && a.zeitMAE == zeit("2026-03-02T10:01:00"))
    #expect(a.mfeAnteil == dez("0.04") && a.maeAnteil == dez("0.015"))
    // Stop-Abstand 2: MAE 0,75 R, MFE 2 R.
    #expect(a.maeR == dez("0.75") && a.mfeR == 2 && a.effizienz == dez("0.75"))
    // Wert je Kurspunkt 30 ÷ 3 = 10: (4 − 3) × 10.
    #expect(a.liegengelassen == 10)
    // Nach dem Ausstieg (103): Hoch 105,5 um 10:05, Tief 101 um 10:30; 12:00 liegt außerhalb der Stunde.
    #expect(a.nachAusstiegFuer == dez("2.5") && a.nachAusstiegGegen == 2)
    let kurz = try #require(Ausstiegsanalyse(trade: kauf, kerzen: minutenkerzen, nachlauf: 120))
    #expect(kurz.nachAusstiegFuer == dez("2.5") && kurz.nachAusstiegGegen == dez("0.1"))
}

private let verkauf = Trade(id: "v1", symbol: "XYZ", side: .sell, lots: 1, openTime: zeit("2026-03-03T09:15:00"),
                            closeTime: zeit("2026-03-03T11:40:00"), openPrice: 50, closePrice: dez("50.5"),
                            stopLoss: 51, profit: -5)

private let stundenkerzen = [
    kerze("2026-03-03T09:00:00", dez("50.2"), dez("50.3"), dez("49.4"), dez("49.5"), dauer: 3_600),
    kerze("2026-03-03T10:00:00", dez("49.5"), dez("50.1"), dez("48.8"), 50, dauer: 3_600),
    kerze("2026-03-03T11:00:00", 50, dez("50.9"), dez("49.9"), dez("50.6"), dauer: 3_600),
]

@Test func ausstiegVerkaufMitStundenkerzenUnscharf() throws {
    let a = try #require(Ausstiegsanalyse(trade: verkauf, kerzen: stundenkerzen))
    // Die erste Kerze beginnt 15 Minuten vor dem Einstieg: unscharf.
    #expect(a.ergebnis == .loss && a.kerzenDauer == 3_600 && a.anzahlKerzen == 3 && a.unscharf && a.abdeckung == 1)
    // Verkauf: bestes Tief 48,8 (+1,2) um 10:00, schlechtestes Hoch 50,9 (−0,9) um 11:00; Ausstieg −0,5.
    #expect(a.erzielt == dez("-0.5") && a.mfe == dez("1.2") && a.mae == dez("0.9"))
    #expect(a.zeitMFE == zeit("2026-03-03T10:00:00") && a.zeitMAE == zeit("2026-03-03T11:00:00"))
    #expect(a.mfeR == dez("1.2") && a.maeR == dez("0.9"))
    #expect(a.effizienz?.gerundet(4) == dez("-0.4167"))
    // Wert je Kurspunkt −5 ÷ −0,5 = 10: (1,2 + 0,5) × 10.
    #expect(a.liegengelassen == 17)
    #expect(a.nachAusstiegFuer == nil && a.nachAusstiegGegen == nil)

    let gewinner = try #require(Ausstiegsanalyse(trade: kauf, kerzen: minutenkerzen))
    let summe = Ausstiegsauswertung([gewinner, a], gleicheWaehrung: true)
    #expect(summe.anzahl == 2 && summe.anzahlUnscharf == 1)
    #expect(summe.medianEffizienz?.gerundet(4) == dez("0.1667"))
    #expect(summe.medianMaeRGewinner == dez("0.75") && summe.medianMfeR == dez("1.6"))
    #expect(summe.verliererMitR == 1 && summe.verliererMitEinemRPlus == 1 && summe.summeLiegengelassen == 27)
    #expect(Ausstiegsauswertung([gewinner, a], gleicheWaehrung: false).summeLiegengelassen == nil)
}

@Test func ausstiegGrenzfaelle() throws {
    var ohneUhrzeit = kauf
    ohneUhrzeit.nurDatum = true
    #expect(Ausstiegsanalyse(trade: ohneUhrzeit, kerzen: minutenkerzen) == nil)
    #expect(Ausstiegsanalyse(trade: kauf, kerzen: Array(minutenkerzen.suffix(2))) == nil)
    #expect(Ausstiegsanalyse(trade: kauf, kerzen: []) == nil)

    // Nie im Plus: keine Effizienz, kein Zeitpunkt für MFE; ohne Stop kein R.
    let verlierer = Trade(id: "k2", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-03-02T10:00:00"),
                          closeTime: zeit("2026-03-02T10:00:00"), openPrice: 100, closePrice: 99, profit: -10)
    let a = try #require(Ausstiegsanalyse(trade: verlierer, kerzen: [kerze("2026-03-02T10:00:00", 100, 100,
                                                                             dez("98.5"), 99)]))
    #expect(a.anzahlKerzen == 1 && a.abdeckung == 1 && a.mfe == 0 && a.mae == dez("1.5"))
    #expect(a.effizienz == nil && a.zeitMFE == nil && a.maeR == nil && a.mfeR == nil)
    #expect(a.liegengelassen == 10)

    // Ohne Kursbewegung kein Wert je Kurspunkt.
    var flach = kauf
    flach.closePrice = 100
    flach.profit = 0
    #expect(try #require(Ausstiegsanalyse(trade: flach, kerzen: minutenkerzen)).liegengelassen == nil)
}

@Test func mt4VerlaufBeideFormate() throws {
    let mt4 = "2026.05.06,10:42,197.840,197.866,197.812,197.829,28\n2026.05.06,10:41,197.851,197.873,197.836,197.840,41\n"
    let plus3 = TimeZone(secondsFromGMT: 3 * 3_600)!
    let k = try MT4Verlauf.parse(text: mt4, serverZeitzone: plus3)
    #expect(k.count == 2 && k[0].beginn == zeit("2026-05-06T07:41:00") && k[0].dauer == 60)
    #expect(k[0].open == dez("197.851") && k[0].high == dez("197.873") && k[0].low == dez("197.836"))
    #expect(k[1].close == dez("197.829"))

    let mt5 = "<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>\n"
        + "2025.05.05\t12:00:00\t1.15\t1.3\t1.1\t1.2\t12\t0\t5\n"
        + "2025.05.05\t11:00:00\t1.1\t1.2\t1.0\t1.15\t10\t0\t5\n"
    let h = try MT4Verlauf.parse(text: mt5, serverZeitzone: TimeZone(secondsFromGMT: 0)!)
    #expect(h.count == 2 && h[0].beginn == zeit("2025-05-05T11:00:00") && h[0].dauer == 3_600)
    #expect(try MT4Verlauf.parse(text: mt5, serverZeitzone: TimeZone(secondsFromGMT: 0)!, dauer: 60)[1].dauer == 60)

    #expect(throws: MT4ImportFehler.self) { try MT4Verlauf.parse(text: "2025.05.05,11:51,1,2", serverZeitzone: plus3) }
    #expect(throws: MT4ImportFehler.self) {
        try MT4Verlauf.parse(text: "2025.05.05,11:51,1,1,2,1,0", serverZeitzone: plus3)
    }
    #expect(try MT4Verlauf.parse(text: "", serverZeitzone: plus3).isEmpty)
}

@Test func zeitkerzeCodableMitKursenAlsText() throws {
    let k = kerze("2026-03-02T10:00:00", dez("100.25"), dez("100.5"), dez("99.5"), dez("0.1"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let daten = try encoder.encode([k])
    #expect(try decoder.decode([Zeitkerze].self, from: daten) == [k])
    let text = String(decoding: daten, as: UTF8.self)
    #expect(text.contains("\"open\":\"100.25\"") && text.contains("\"close\":\"0.1\"") && text.contains("\"dauer\":60"))
}
