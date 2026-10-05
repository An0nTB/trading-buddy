import Foundation
import Testing
@testable import TradingCore

/// Best-Exit-Analyse: feste R-Ziele gegen den tatsächlichen Ausstieg. Erfundene Kerzen und Trades,
/// Sollwerte von Hand gerechnet.
private func zeit(_ text: String) -> Date { ISO8601DateFormatter().date(from: text + "Z")! }

private func kerze(_ beginn: String, _ o: Decimal, _ h: Decimal, _ l: Decimal, _ c: Decimal) -> Zeitkerze {
    Zeitkerze(beginn: zeit(beginn), dauer: 60, open: o, high: h, low: l, close: c)
}

private func dez(_ text: String) -> Decimal { Decimal(string: text)! }

private func ausgaenge(_ b: BestExit) -> [BestExit.Ausgang] { b.stufen.map(\.ausgang) }
private func ergebnisse(_ b: BestExit) -> [Decimal] { b.stufen.map(\.r) }
private func differenzen(_ b: BestExit) -> [Decimal] { b.stufen.map(\.differenz) }
private func unscharfe(_ b: BestExit) -> [Bool] { b.stufen.map(\.unscharf) }

// Kauf bei 100, Stop 98 (1 R = 2 Punkte), Ausstieg 103 (+1,5 R); Wert je Punkt 30 ÷ 3 = 10, Risiko 20.
// Ziele: 1 R = 102, 1,5 R = 103, 2 R = 104, 3 R = 106.
private let kaufZiel = Trade(id: "b1", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-04-06T10:00:00"),
                             closeTime: zeit("2026-04-06T10:05:00"), openPrice: 100, closePrice: 103,
                             stopLoss: 98, profit: 30)

private let kaufZielKerzen = [
    kerze("2026-04-06T10:00:00", 100, 101, dez("99.5"), dez("100.5")),
    kerze("2026-04-06T10:01:00", dez("100.5"), dez("102.5"), 100, 102),
    kerze("2026-04-06T10:02:00", 102, dez("103.2"), 101, 103),
    kerze("2026-04-06T10:03:00", 103, dez("104.5"), dez("102.5"), 104),
    kerze("2026-04-06T10:04:00", 104, 104, dez("102.8"), 103),
    kerze("2026-04-06T10:05:00", 103, 110, 90, 103),  // nach dem Ausstieg, zählt nicht
]

@Test func bestExitKaufTrifftZielVorStop() throws {
    let b = try #require(BestExit(trade: kaufZiel, kerzen: kaufZielKerzen))
    #expect(b.tradeID == "b1" && b.risiko == 20 && b.tatsaechlichR == dez("1.5") && b.kostenR == 0)
    #expect(b.stufen.map(\.ziel) == BestExit.standardZiele)
    // 1 R um 10:01, 1,5 R um 10:02, 2 R um 10:03; 3 R nie, Stop nie: dort das tatsächliche Ergebnis.
    #expect(ausgaenge(b) == [.ziel, .ziel, .ziel, .tatsaechlich])
    #expect(ergebnisse(b) == [1, dez("1.5"), 2, dez("1.5")])
    #expect(differenzen(b) == [dez("-0.5"), 0, dez("0.5"), 0])
    #expect(b.stufen.map(\.differenzBetrag) == [-10, 0, 10, 0])
    #expect(unscharfe(b) == [false, false, false, false])
    // Bestes Hoch 104,5: MFE 4,5 Punkte = 2,25 R.
    #expect(b.theoretischesMaximumR == dez("2.25") && b.differenzTheoretischesMaximum == dez("0.75"))
    #expect(!b.kerzenUnscharf && b.abdeckung == 1)
}

// Wie oben, aber 10:01 fällt bis 97,9 unter den Stop, bevor 102 erreicht ist; Kommission −2 = −0,1 R.
private let kaufStop = Trade(id: "b2", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-04-07T10:00:00"),
                             closeTime: zeit("2026-04-07T10:03:00"), openPrice: 100, closePrice: 103,
                             stopLoss: 98, commission: -2, profit: 30)

private let kaufStopKerzen = [
    kerze("2026-04-07T10:00:00", 100, 101, 99, dez("99.5")),
    kerze("2026-04-07T10:01:00", dez("99.5"), dez("101.5"), dez("97.9"), 101),
    kerze("2026-04-07T10:02:00", 101, dez("104.5"), 101, 103),
]

@Test func bestExitKaufTrifftStopZuerst() throws {
    let b = try #require(BestExit(trade: kaufStop, kerzen: kaufStopKerzen))
    // Netto 28 ÷ Risiko 20 = 1,4 R; jede Variante trägt dieselben Kosten von −0,1 R.
    #expect(b.tatsaechlichR == dez("1.4") && b.kostenR == dez("-0.1"))
    #expect(ausgaenge(b) == [.stop, .stop, .stop, .stop])
    #expect(ergebnisse(b) == Array(repeating: dez("-1.1"), count: 4))
    #expect(differenzen(b) == Array(repeating: dez("-2.5"), count: 4))
    #expect(b.stufen.allSatisfy { $0.differenzBetrag == -50 && !$0.unscharf })
    // MFE 4,5 Punkte = 2,25 R, abzüglich 0,1 R Kosten.
    #expect(b.theoretischesMaximumR == dez("2.15") && b.differenzTheoretischesMaximum == dez("0.75"))
}

// Verkauf bei 50, Stop 51 (1 R = 1 Punkt), Ausstieg 48,5 (+1,5 R); Wert je Punkt 15 ÷ 1,5 = 10, Risiko 10.
// Ziele: 1 R = 49, 1,5 R = 48,5, 2 R = 48, 3 R = 47.
private let verkaufZiel = Trade(id: "b3", symbol: "XYZ", side: .sell, lots: 1,
                                openTime: zeit("2026-04-08T09:00:00"), closeTime: zeit("2026-04-08T09:05:00"),
                                openPrice: 50, closePrice: dez("48.5"), stopLoss: 51, profit: 15)

private let verkaufKerzen = [
    kerze("2026-04-08T09:00:00", 50, dez("50.5"), dez("49.8"), dez("49.9")),
    kerze("2026-04-08T09:01:00", dez("49.9"), 50, dez("48.9"), 49),
    kerze("2026-04-08T09:02:00", 49, 49, dez("48.4"), dez("48.5")),
    kerze("2026-04-08T09:03:00", dez("48.5"), dez("48.6"), dez("47.8"), 48),
    kerze("2026-04-08T09:04:00", 48, dez("48.9"), dez("48.2"), dez("48.5")),
]

@Test func bestExitVerkaufSpiegelbildlich() throws {
    let b = try #require(BestExit(trade: verkaufZiel, kerzen: verkaufKerzen))
    #expect(b.risiko == 10 && b.tatsaechlichR == dez("1.5"))
    #expect(ausgaenge(b) == [.ziel, .ziel, .ziel, .tatsaechlich])
    #expect(ergebnisse(b) == [1, dez("1.5"), 2, dez("1.5")])
    #expect(b.stufen.map(\.differenzBetrag) == [-5, 0, 5, 0])
    // Bestes Tief 47,8: MFE 2,2 Punkte = 2,2 R.
    #expect(b.theoretischesMaximumR == dez("2.2"))

    // Beim Verkauf zählt das Hoch für den Stop: 51,1 in der ersten Kerze beendet jede Stufe mit −1 R.
    var mitStop = verkaufKerzen
    mitStop[0] = kerze("2026-04-08T09:00:00", 50, dez("51.1"), dez("49.8"), dez("49.9"))
    let s = try #require(BestExit(trade: verkaufZiel, kerzen: mitStop))
    #expect(ausgaenge(s) == [.stop, .stop, .stop, .stop])
    #expect(ergebnisse(s) == [-1, -1, -1, -1])
}

// Kauf bei 100, Stop 98, Ausstieg 101 (+0,5 R); die Kerze um 10:01 reicht von 97,8 bis 104,2.
private let kaufBeides = Trade(id: "b4", symbol: "XYZ", side: .buy, lots: 1,
                               openTime: zeit("2026-04-09T10:00:00"), closeTime: zeit("2026-04-09T10:02:00"),
                               openPrice: 100, closePrice: 101, stopLoss: 98, profit: 10)

private let kaufBeidesKerzen = [
    kerze("2026-04-09T10:00:00", 100, dez("100.5"), dez("99.5"), 100),
    kerze("2026-04-09T10:01:00", 100, dez("104.2"), dez("97.8"), 101),
]

@Test func bestExitGleicheKerzeStopUndZielUnscharf() throws {
    let b = try #require(BestExit(trade: kaufBeides, kerzen: kaufBeidesKerzen))
    #expect(b.tatsaechlichR == dez("0.5"))
    // 102, 103 und 104 liegen in derselben Kerze wie der Stop: vorsichtig Stop, unscharf.
    // 106 erreicht die Kerze nicht: eindeutig Stop.
    #expect(ausgaenge(b) == [.stop, .stop, .stop, .stop])
    #expect(ergebnisse(b) == [-1, -1, -1, -1])
    #expect(unscharfe(b) == [true, true, true, false])
    #expect(differenzen(b) == Array(repeating: dez("-1.5"), count: 4))
    #expect(b.theoretischesMaximumR == dez("2.1"))
}

@Test func bestExitWederStopNochZielUndEigeneZiele() throws {
    let kerzen = [
        kerze("2026-04-09T10:00:00", 100, dez("101.5"), 99, 101),
        kerze("2026-04-09T10:01:00", 101, dez("101.5"), dez("100.5"), 101),
    ]
    // Ziele ≤ 0 und doppelte fallen weg, sortiert aufsteigend: 1 R (102) und 2 R (104), beide nie erreicht.
    let b = try #require(BestExit(trade: kaufBeides, kerzen: kerzen, ziele: [2, 1, 2, -1, 0]))
    #expect(b.stufen.map(\.ziel) == [1, 2])
    #expect(ausgaenge(b) == [.tatsaechlich, .tatsaechlich])
    #expect(ergebnisse(b) == [dez("0.5"), dez("0.5")] && differenzen(b) == [0, 0])
    #expect(unscharfe(b) == [false, false])
}

private let ohneStop = Trade(id: "b5", symbol: "XYZ", side: .buy, lots: 1, openTime: zeit("2026-04-06T10:00:00"),
                             closeTime: zeit("2026-04-06T10:05:00"), openPrice: 100, closePrice: 103, profit: 30)

@Test func bestExitOhneRisikoOderKerzenAusgelassen() {
    #expect(BestExit(trade: ohneStop, kerzen: kaufZielKerzen) == nil)
    // Stop auf der Gewinnseite (nachgezogen): kein Risiko.
    var nachgezogen = kaufZiel
    nachgezogen.stopLoss = 101
    #expect(BestExit(trade: nachgezogen, kerzen: kaufZielKerzen) == nil)
    #expect(BestExit(trade: kaufZiel, kerzen: []) == nil)
    var ohneUhrzeit = kaufZiel
    ohneUhrzeit.nurDatum = true
    #expect(BestExit(trade: ohneUhrzeit, kerzen: kaufZielKerzen) == nil)
}

@Test func bestExitAuswertungSummenUndBesteStufe() throws {
    var ohneKerzen = kaufZiel
    ohneKerzen.id = "b6"
    let trades = [kaufZiel, kaufStop, verkaufZiel, kaufBeides, ohneStop, ohneKerzen]
    let kerzen = ["b1": kaufZielKerzen, "b2": kaufStopKerzen, "b3": verkaufKerzen, "b4": kaufBeidesKerzen,
                  "b5": kaufZielKerzen]
    let a = BestExitAuswertung(trades: trades, kerzenJeTrade: kerzen, gleicheWaehrung: true)
    #expect(a.anzahl == 4 && a.ohneRisiko == 1 && a.ohneKerzen == 1 && a.anzahlKerzenUnscharf == 0)
    #expect(a.einzeln.map(\.tradeID) == ["b1", "b2", "b3", "b4"])
    #expect(a.ziele == BestExit.standardZiele && a.stufen.map(\.anzahl) == [4, 4, 4, 4])
    // Tatsächlich 1,5 + 1,4 + 1,5 + 0,5 = 4,9 R.
    #expect(a.summeTatsaechlichR == dez("4.9") && a.durchschnittTatsaechlichR == dez("1.225"))

    // 1 R: 1 − 1,1 + 1 − 1 = −0,1; 1,5 R: 0,9; 2 R: 1,9; 3 R: 1,5 − 1,1 + 1,5 − 1 = 0,9.
    #expect(a.stufen.map(\.summeR) == [dez("-0.1"), dez("0.9"), dez("1.9"), dez("0.9")])
    let schnitte: [Decimal?] = [dez("-0.025"), dez("0.225"), dez("0.475"), dez("0.225")]
    #expect(a.stufen.map(\.durchschnittR) == schnitte)
    #expect(a.stufen.map(\.differenzR) == [-5, -4, -3, -4])
    #expect(a.stufen.map(\.zielErreicht) == [2, 2, 2, 0])
    #expect(a.stufen.map(\.stopZuerst) == [2, 2, 2, 2])
    #expect(a.stufen.map(\.ohneEntscheidung) == [0, 0, 0, 2])
    let quoten: [Decimal?] = [dez("0.5"), dez("0.5"), dez("0.5"), dez("0")]
    #expect(a.stufen.map(\.trefferquote) == quoten)
    #expect(a.stufen.map(\.anzahlUnscharf) == [1, 1, 1, 0])
    #expect(a.besteStufe == 2)
    // 2 R in Beträgen: +10 − 50 + 5 − 30 = −65.
    #expect(a.stufen[2].differenzBetrag == -65)
    // Obergrenze: 2,25 + 2,15 + 2,2 + 2,1 = 8,7 R.
    #expect(a.summeTheoretischesMaximumR == dez("8.7") && a.differenzTheoretischesMaximum == dez("3.8"))

    let gemischt = BestExitAuswertung(trades: trades, kerzenJeTrade: kerzen, gleicheWaehrung: false)
    #expect(gemischt.stufen.allSatisfy { $0.differenzBetrag == nil })

    let leer = BestExitAuswertung([], gleicheWaehrung: true)
    #expect(leer.anzahl == 0 && leer.besteStufe == nil && leer.summeTatsaechlichR == 0)
    #expect(leer.durchschnittTatsaechlichR == nil && leer.stufen.allSatisfy { $0.trefferquote == nil })
}
