import Foundation
import Testing
@testable import TradingCore

/// 80 ausgedachte Trades nach fester Formel. Sollwerte unabhängig in Python gerechnet
/// (decimal, gleiche SplitMix64-Formel), Skript im Prüfprotokoll des PR.
/// Trade i: Symbol „de40“ bei i mod 5 < 3 (48 Trades), sonst „xauusd“ (32);
/// Richtung buy bei geradem i (40), sonst sell (40);
/// Ergebnis (i × 37 mod 23) − 10, bei „de40“ plus `bonus`; keine Kosten.
private func musterTrades(bonus: Int) -> [Trade] {
    let start = Date(timeIntervalSince1970: 1_748_851_200) // 02.06.2025 08:00 UTC
    return (0..<80).map { i in
        let symbol = i % 5 < 3 ? "de40" : "xauusd"
        let basis = (i * 37) % 23 - 10
        let ergebnis = Decimal(basis + (symbol == "de40" ? bonus : 0))
        let eroeffnung = start.addingTimeInterval(Double(i) * 7 * 3600)
        let id = (i < 10 ? "t0" : "t") + String(i)
        return Trade(id: id, symbol: symbol, side: i % 2 == 0 ? .buy : .sell, lots: 1,
                     openTime: eroeffnung, closeTime: eroeffnung.addingTimeInterval(1800),
                     openPrice: 100, closePrice: 100, profit: ergebnis)
    }
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let symbolUndRichtung: [Aufteilung] = [.symbol, .richtung]

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

@Test func zufallsgeneratorTrifftReferenzwerte() {
    // Referenzfolge SplitMix64 für Startwert 1234567 (Vigna, splitmix64.c), in Python bestätigt.
    var generator = Zufallsgenerator(seed: 1_234_567)
    let folge: [UInt64] = (0..<5).map { _ in generator.next() }
    let soll: [UInt64] = [6_457_827_717_110_365_317, 3_203_168_211_198_807_973, 9_817_491_932_198_370_423,
                          4_593_380_528_125_082_431, 16_408_922_859_458_223_821]
    #expect(folge == soll)
}

@Test func musterNachEffektSortiert() {
    let trades = musterTrades(bonus: 2)
    let muster = MusterFinder.finde(trades, zeitzone: utc, aufteilungen: symbolUndRichtung)
    let namen: [String] = muster.map(\.schluessel)
    #expect(namen == ["de40", "xauusd", "buy", "sell"])

    let de40 = muster[0]
    #expect(de40.aufteilung == .symbol)
    #expect(de40.anzahl == 48 && de40.anzahlRest == 32)
    #expect(de40.kennzahlen.netto == 119)
    #expect(de40.erwartungswert.gerundet(4) == d("2.4792"))      // 119 ÷ 48
    #expect(de40.erwartungswertRest == d("1.21875"))             // 39 ÷ 32
    #expect(de40.effekt.gerundet(4) == d("1.2604"))
    #expect(muster[1].effekt.gerundet(4) == d("-1.2604"))

    let buy = muster[2]
    #expect(buy.anzahl == 40 && buy.anzahlRest == 40)
    #expect(buy.effekt == d("-0.2"))                              // 75 ÷ 40 − 83 ÷ 40
    #expect(muster[3].effekt == d("0.2"))
}

@Test func kleineGruppenFallenHeraus() {
    let trades = musterTrades(bonus: 2)
    // Ab 41: Richtung hat 40 je Gruppe, Symbol hat einen Rest von 32.
    let streng = MusterFinder.finde(trades, zeitzone: utc, aufteilungen: symbolUndRichtung, mindestanzahl: 41)
    #expect(streng.isEmpty)
    // Alle Aufteilungen: jede Gruppe und jeder Rest mit mindestens 30 Trades.
    let alle = MusterFinder.finde(trades, zeitzone: utc)
    let zuKlein = alle.filter { $0.anzahl < 30 || $0.anzahlRest < 30 }
    #expect(!alle.isEmpty)
    #expect(zuKlein.isEmpty)
    let betraege: [Decimal] = alle.map { abs($0.effekt) }
    #expect(betraege == betraege.sorted(by: >))
}

@Test func zufallsanteilSchwacherUndStarkerEffekt() throws {
    let schwach = musterTrades(bonus: 2)
    let schwachesMuster = MusterFinder.finde(schwach, zeitzone: utc, aufteilungen: symbolUndRichtung)
    #expect(schwachesMuster[0].zufallsanteil(trades: schwach, laeufe: 500, seed: 7) == d("0.454"))
    #expect(schwachesMuster[2].zufallsanteil(trades: schwach, laeufe: 500, seed: 7) == d("0.912"))

    let stark = musterTrades(bonus: 8)
    let starkesMuster = MusterFinder.finde(stark, zeitzone: utc, aufteilungen: symbolUndRichtung)
    let erstes = try #require(starkesMuster.first)
    #expect(erstes.schluessel == "de40")
    #expect(erstes.effekt.gerundet(4) == d("7.2604"))
    #expect(erstes.zufallsanteil(trades: stark, laeufe: 500, seed: 7) == 0)
    // Andere Trades als beim Finden: keine Aussage.
    #expect(erstes.zufallsanteil(trades: Array(stark.prefix(50))) == nil)
}

@Test func monteCarloBandbreite() throws {
    let trades = musterTrades(bonus: 2)
    let mc = try #require(MonteCarlo(trades: trades, laeufe: 200, seed: 42))
    #expect(mc.laeufe == 200)
    #expect(mc.endstand == Bandbreite<Decimal>(unten: 60, mitte: 160, oben: 255))
    #expect(mc.maxDrawdown == Bandbreite<Decimal>(unten: 16, mitte: 27, oben: 49))
    #expect(mc.laengsteVerlustserie == Bandbreite<Int>(unten: 2, mitte: 4, oben: 6))

    let standard = try #require(MonteCarlo(trades: trades))
    #expect(standard.endstand == Bandbreite<Decimal>(unten: 57, mitte: 158, oben: 255))
    #expect(standard.maxDrawdown == Bandbreite<Decimal>(unten: 17, mitte: 29, oben: 54))
    #expect(standard.laengsteVerlustserie == Bandbreite<Int>(unten: 3, mitte: 4, oben: 7))
}

@Test func monteCarloUnabhaengigVonReihenfolgeUndLeer() throws {
    let trades = musterTrades(bonus: 2)
    let vorwaerts = try #require(MonteCarlo(trades: trades, laeufe: 100, seed: 3))
    let rueckwaerts = try #require(MonteCarlo(trades: trades.reversed(), laeufe: 100, seed: 3))
    #expect(vorwaerts == rueckwaerts)
    #expect(MonteCarlo(trades: []) == nil)
    #expect(MonteCarlo(trades: trades, laeufe: 0) == nil)
}
