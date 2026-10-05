import Foundation
import Testing
@testable import TradingCore

/// Angenommenes Risiko (geplantes Risiko statt Stop) in Fehlermustern, Regelprüfung und Best-Exit.
/// Erfundene Trades und Kerzen, Sollwerte von Hand gerechnet.

private let angenommenUTC = TimeZone(secondsFromGMT: 0)!
private let angenommenBasis: TimeInterval = 1_760_000_000

private func angenommenDez(_ text: String) -> Decimal { Decimal(string: text)! }

/// Kauf zu 100, Wert je Kurspunkt 10: Schluss 85 ergibt −150, Schluss 110 ergibt +100. Haltedauer 10 Minuten.
private func angenommenTrade(_ id: String, minute: Double, schluss: Decimal, stop: Decimal? = nil,
                             geplant: Decimal? = nil) -> Trade {
    let eroeffnung = Date(timeIntervalSince1970: angenommenBasis + minute * 60)
    let t = Trade(id: id, symbol: "Musterwert", side: .buy, lots: 10, openTime: eroeffnung,
                  closeTime: eroeffnung.addingTimeInterval(600), openPrice: 100, closePrice: schluss,
                  stopLoss: stop, profit: (schluss - 100) * 10)
    return t.mitGeplantemRisiko(geplant)
}

private func angenommenBefund(_ befunde: [Befund], _ muster: Fehlermuster) -> Befund? {
    befunde.first { $0.muster == muster }
}

// MARK: - Fehlermuster

@Test func angenommenVerlustUeberGeplantIstKeinStopBruch() {
    // s1: Stop 95, Risiko 50, R −3: Stop gebrochen. a1: ohne Stop, geplant 100, R −1,5: geplantes Risiko
    // überschritten, aber kein Stop-Bruch.
    let trades = [angenommenTrade("s1", minute: 0, schluss: 85, stop: 95),
                  angenommenTrade("a1", minute: 30, schluss: 85, geplant: 100)]
    let befunde = Fehlermuster.pruefe(trades, zeitzone: angenommenUTC)
    let stop = angenommenBefund(befunde, .stopNichtEingehalten)
    #expect(stop?.trades == ["s1"])
    #expect(stop?.stichprobe == 1)
    #expect(stop?.summeR == -3)

    let nurAngenommen = Fehlermuster.pruefe([trades[1]], zeitzone: angenommenUTC)
    #expect(angenommenBefund(nurAngenommen, .stopNichtEingehalten) == nil)

    // „Geplantes Risiko überschritten“ lässt sich getrennt zählen: R-Kennzahlen nur über angenommenes R.
    let angenommen = trades.filter { $0.risikoAngenommen }
    #expect(RKennzahlen(trades: angenommen).verlusteUeber1R == 1)
    #expect(RKennzahlen(trades: trades).verlusteUeber1R == 2)
}

@Test func angenommenSchwankendeGroesseNurMitStopRisiko() {
    // Stop-Risiken 50 und 200: Mittel 125, Streuung 75, Variationskoeffizient 0,6 über 0,5.
    // Zwei angenommene Risiken von je 125 hätten das auf 0,42 gedrückt; sie zählen nicht mit.
    let gestreut = [angenommenTrade("s1", minute: 0, schluss: 85, stop: 95),
                    angenommenTrade("s2", minute: 30, schluss: 85, stop: 80),
                    angenommenTrade("a1", minute: 60, schluss: 85, geplant: 125),
                    angenommenTrade("a2", minute: 90, schluss: 85, geplant: 125)]
    let befund = angenommenBefund(Fehlermuster.pruefe(gestreut, zeitzone: angenommenUTC), .schwankendeGroesse)
    #expect(befund?.stichprobe == 2)
    #expect(befund?.wert?.gerundet(4) == angenommenDez("0.6"))

    // Gleiche Stop-Risiken (je 50); die stark verschiedenen Standardwerte 10 und 500 sind keine Positionsgröße.
    let gleich = [angenommenTrade("s1", minute: 0, schluss: 85, stop: 95),
                  angenommenTrade("s2", minute: 30, schluss: 85, stop: 95),
                  angenommenTrade("a1", minute: 60, schluss: 85, geplant: 10),
                  angenommenTrade("a2", minute: 90, schluss: 85, geplant: 500)]
    #expect(angenommenBefund(Fehlermuster.pruefe(gleich, zeitzone: angenommenUTC), .schwankendeGroesse) == nil)
}

@Test func angenommenGroesseNachGewinnserieNurMitStopRisiko() {
    // Drei Gewinner mit Stop-Risiko 50, dann s4 mit Stop-Risiko 200 und a5 mit geplantem Risiko 500.
    // Median der Stop-Risiken 50, Grenze 75: s4 zählt, a5 nicht, weil 500 keine echte Positionsgröße ist.
    let trades = [angenommenTrade("w1", minute: 0, schluss: 110, stop: 95),
                  angenommenTrade("w2", minute: 20, schluss: 110, stop: 95),
                  angenommenTrade("w3", minute: 40, schluss: 110, stop: 95),
                  angenommenTrade("s4", minute: 60, schluss: 110, stop: 80),
                  angenommenTrade("a5", minute: 80, schluss: 110, geplant: 500)]
    let befund = angenommenBefund(Fehlermuster.pruefe(trades, zeitzone: angenommenUTC), .groesseNachGewinnserie)
    #expect(befund?.trades == ["s4"])
    #expect(befund?.stichprobe == 4)
}

// MARK: - Regelprüfung

@Test func angenommenRegelRisikoJeTradeNurAusStop() {
    let regeln = Handelsregeln(maxRisikoJeTrade: 80)
    // a1: geplant 100 über der Grenze, Verlust 30: kein Verstoß. s2: Stop 90, Risiko 100: Verstoß.
    // a3: geplant 50, aber Verlust 150 über der Grenze: Verstoß über den Verlust.
    let trades = [angenommenTrade("a1", minute: 0, schluss: 97, geplant: 100),
                  angenommenTrade("s2", minute: 20, schluss: 97, stop: 90),
                  angenommenTrade("a3", minute: 40, schluss: 85, geplant: 50)]
    let verstoesse = Regelpruefung.pruefe(trades, regeln: regeln, zeitzone: angenommenUTC)
    let kurz = verstoesse.map { "\($0.trade) \($0.art.rawValue)" }
    #expect(kurz == ["s2 risikoJeTrade", "a3 risikoJeTrade"])
}

// MARK: - Best-Exit

private func angenommenZeit(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "Z")! }

private func angenommenKerze(_ beginn: String, _ o: Decimal, _ h: Decimal, _ l: Decimal, _ c: Decimal) -> Zeitkerze {
    Zeitkerze(beginn: angenommenZeit(beginn), dauer: 60, open: o, high: h, low: l, close: c)
}

private func angenommenAusgaenge(_ b: BestExit) -> [BestExit.Ausgang] { b.stufen.map { $0.ausgang } }
private func angenommenErgebnisse(_ b: BestExit) -> [Decimal] { b.stufen.map { $0.r } }

// Kauf bei 100, Ausstieg 103, Kursergebnis 30: Wert je Punkt 10. Geplant 20 ergibt 1 R = 2 Punkte, wie ein
// Stop bei 98. Ziele: 1 R = 102, 1,5 R = 103, 2 R = 104, 3 R = 106.
private let angenommenKauf = Trade(id: "ab1", symbol: "XYZ", side: .buy, lots: 1,
                                   openTime: angenommenZeit("2026-05-04T10:00:00"),
                                   closeTime: angenommenZeit("2026-05-04T10:05:00"), openPrice: 100, closePrice: 103,
                                   profit: 30).mitGeplantemRisiko(20)

private let angenommenKaufKerzen = [
    angenommenKerze("2026-05-04T10:00:00", 100, 101, angenommenDez("99.5"), angenommenDez("100.5")),
    angenommenKerze("2026-05-04T10:01:00", angenommenDez("100.5"), angenommenDez("102.5"), 100, 102),
    angenommenKerze("2026-05-04T10:02:00", 102, angenommenDez("103.2"), 101, 103),
    angenommenKerze("2026-05-04T10:03:00", 103, angenommenDez("104.5"), angenommenDez("102.5"), 104),
    angenommenKerze("2026-05-04T10:04:00", 104, 104, angenommenDez("102.8"), 103),
]

/// Derselbe Trade mit echtem Stop bei 98 und ohne geplantes Risiko.
private func angenommenMitStop(_ id: String) -> Trade {
    var t = angenommenKauf.mitGeplantemRisiko(nil)
    t.id = id
    t.stopLoss = 98
    return t
}

@Test func angenommenBestExitKaufAusGeplantemRisiko() throws {
    let b = try #require(BestExit(trade: angenommenKauf, kerzen: angenommenKaufKerzen))
    #expect(b.risikoAngenommen)
    #expect(b.risiko == 20 && b.tatsaechlichR == angenommenDez("1.5") && b.kostenR == 0)
    #expect(angenommenAusgaenge(b) == [.ziel, .ziel, .ziel, .tatsaechlich])
    #expect(angenommenErgebnisse(b) == [1, angenommenDez("1.5"), 2, angenommenDez("1.5")])
    // Bestes Hoch 104,5: MFE 4,5 Punkte ÷ 2 Punkte = 2,25 R.
    #expect(b.theoretischesMaximumR == angenommenDez("2.25"))

    // Mit echtem Stop bei 98 dieselben Stufen, aber nicht angenommen.
    let s = try #require(BestExit(trade: angenommenMitStop("ab2"), kerzen: angenommenKaufKerzen))
    #expect(!s.risikoAngenommen)
    #expect(s.stufen == b.stufen && s.theoretischesMaximumR == b.theoretischesMaximumR)
}

@Test func angenommenBestExitStopAufGewinnseiteNimmtGeplantesRisiko() throws {
    // Stop 101 bei Kauf zu 100 (nachgezogen) gibt kein Stop-Risiko; 1 R kommt aus dem geplanten Risiko.
    var nachgezogen = angenommenKauf
    nachgezogen.stopLoss = 101
    let b = try #require(BestExit(trade: nachgezogen, kerzen: angenommenKaufKerzen))
    let ohneStop = try #require(BestExit(trade: angenommenKauf, kerzen: angenommenKaufKerzen))
    #expect(b.risikoAngenommen)
    #expect(b.stufen == ohneStop.stufen)
}

@Test func angenommenBestExitVerkaufMitDoppeltemRisiko() throws {
    // Verkauf bei 50, Ausstieg 48,5, Kursergebnis 15: Wert je Punkt 10. Geplant 20 ergibt 1 R = 2 Punkte,
    // tatsächlich 0,75 R. Ziele: 1 R = 48, 1,5 R = 47, 2 R = 46, 3 R = 44; gedachter Stop 52.
    let t = Trade(id: "ab4", symbol: "XYZ", side: .sell, lots: 1, openTime: angenommenZeit("2026-05-05T09:00:00"),
                  closeTime: angenommenZeit("2026-05-05T09:05:00"), openPrice: 50,
                  closePrice: angenommenDez("48.5"), profit: 15).mitGeplantemRisiko(20)
    let kerzen = [
        angenommenKerze("2026-05-05T09:00:00", 50, angenommenDez("50.5"), angenommenDez("49.8"), angenommenDez("49.9")),
        angenommenKerze("2026-05-05T09:01:00", angenommenDez("49.9"), 50, angenommenDez("48.9"), 49),
        angenommenKerze("2026-05-05T09:02:00", 49, 49, angenommenDez("48.4"), angenommenDez("48.5")),
        angenommenKerze("2026-05-05T09:03:00", angenommenDez("48.5"), angenommenDez("48.6"), angenommenDez("47.8"), 48),
        angenommenKerze("2026-05-05T09:04:00", 48, angenommenDez("48.9"), angenommenDez("48.2"), angenommenDez("48.5")),
    ]
    let b = try #require(BestExit(trade: t, kerzen: kerzen))
    #expect(b.risikoAngenommen && b.risiko == 20 && b.tatsaechlichR == angenommenDez("0.75"))
    // 48 um 09:03 erreicht, 47 nie; der Stop 52 nie.
    #expect(angenommenAusgaenge(b) == [.ziel, .tatsaechlich, .tatsaechlich, .tatsaechlich])
    let erwartet: [Decimal] = [1, angenommenDez("0.75"), angenommenDez("0.75"), angenommenDez("0.75")]
    #expect(angenommenErgebnisse(b) == erwartet)
    // Bestes Tief 47,8: MFE 2,2 Punkte ÷ 2 Punkte = 1,1 R.
    #expect(b.theoretischesMaximumR == angenommenDez("1.1"))
}

/// Kauf und Verkauf zu 100: keine Kursbewegung, Wert je Punkt unbekannt.
private func angenommenOhneBewegung(stop: Decimal? = nil) -> Trade {
    var t = angenommenKauf
    t.id = "ab3"
    t.closePrice = 100
    t.profit = 0
    t.stopLoss = stop
    return t
}

@Test func angenommenBestExitOhneKursbewegungAusgelassen() {
    #expect(BestExit(trade: angenommenOhneBewegung(), kerzen: angenommenKaufKerzen) == nil)
    // Auch mit Stop 98: Ohne Bewegung gibt es kein Stop-Risiko, das R ist angenommen und ohne Wert je Punkt.
    #expect(BestExit(trade: angenommenOhneBewegung(stop: 98), kerzen: angenommenKaufKerzen) == nil)
}

@Test func angenommenBestExitAuswertungZaehltAngenommene() {
    let trades = [angenommenMitStop("ab2"), angenommenKauf, angenommenOhneBewegung()]
    let kerzen = ["ab1": angenommenKaufKerzen, "ab2": angenommenKaufKerzen, "ab3": angenommenKaufKerzen]
    let a = BestExitAuswertung(trades: trades, kerzenJeTrade: kerzen, gleicheWaehrung: true)
    #expect(a.anzahl == 2 && a.anzahlRisikoAngenommen == 1)
    // Ohne Kursbewegung fehlt der Abstand für 1 R: ausgelassen ohne Risiko, nicht ohne Kerzen.
    #expect(a.ohneRisiko == 1 && a.ohneKerzen == 0)
    #expect(a.summeTatsaechlichR == 3)

    let leer = BestExitAuswertung([], gleicheWaehrung: true)
    #expect(leer.anzahlRisikoAngenommen == 0)
}

// MARK: - Fremdwährung

@Test func angenommenFremdwaehrungNachAngleich() {
    // Kauf in USD zu 100, Schluss 85, Wert je Punkt 10 USD: −150 USD. Geplantes Risiko 100 EUR (Kontowährung).
    // Referenzkurs 1 EUR = 1,25 USD am 02.03.2026: −120 EUR, R −1,2. Vor dem Angleich mischt R USD und EUR.
    let schluss = ISO8601DateFormatter().date(from: "2026-03-02T10:10:00Z")!
    let ohneStop = Trade(id: "fw1", symbol: "Musterwert", side: .buy, lots: 10,
                         openTime: schluss.addingTimeInterval(-600), closeTime: schluss, openPrice: 100,
                         closePrice: 85, profit: -150, produktart: .aktie, waehrung: "USD").mitGeplantemRisiko(100)
    var mitStop = ohneStop
    mitStop.id = "fw2"
    mitStop.stopLoss = 95
    let kurse = Referenzkurse(kurse: [Journaltag("2026-03-02")!: ["USD": angenommenDez("1.25")]])

    #expect(ohneStop.rMultiple == angenommenDez("-1.5"))
    let a = Waehrungsangleich([ohneStop, mitStop], kontowaehrung: "EUR", kurse: kurse)
    #expect(a.trades.count == 2 && a.ohneKurs.isEmpty)
    #expect(a.trades[0].netProfit == -120 && a.trades[0].geplantesRisiko == 100)
    #expect(a.trades[0].risikoAngenommen && a.trades[0].rMultiple == angenommenDez("-1.2"))
    // Mit Stop folgt das Risiko dem umgerechneten Wert je Punkt (8 EUR): 5 Punkte = 40 EUR, R bleibt −3.
    #expect(a.trades[1].stopRisiko == 40 && a.trades[1].rMultiple == -3 && !a.trades[1].risikoAngenommen)
}
