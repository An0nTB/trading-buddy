import Foundation
import Testing
@testable import TradingCore

private let utc = TimeZone(secondsFromGMT: 0)!

private func d(_ text: String) -> Decimal { Decimal(string: text)! }

/// Treffer auf den sechs Hand-Trades aus KennzahlenTests, von Hand nachvollzogen.
@Test func fehlermusterAufHandTrades() {
    let befunde = Fehlermuster.pruefe(handTrades, geloeschteOrders: 7, zeitzone: utc)
    #expect(befunde.map(\.muster) == [.revancheTrade, .stopNichtEingehalten, .verliererLaufenLassen,
                                      .ohneStop, .staendigesUmplanen])
    let jeMuster = Dictionary(uniqueKeysWithValues: befunde.map { ($0.muster, $0) })

    // Trade 3: 10 Min. nach Verlust von Trade 2, 2 Lots bei Median 1.
    #expect(jeMuster[.revancheTrade]?.trades == ["3"])
    #expect(jeMuster[.revancheTrade]?.netto == -11)
    // Trade 5: −1,75 R liegt unter −1,2 R; Grundlage 4 Trades mit R.
    #expect(jeMuster[.stopNichtEingehalten]?.trades == ["5"])
    #expect(jeMuster[.stopNichtEingehalten]?.summeR == d("-1.75"))
    #expect(jeMuster[.stopNichtEingehalten]?.stichprobe == 4)
    // Verlierer Ø 22425 s, Gewinner Ø 9000 s: Faktor 2,4917.
    #expect(jeMuster[.verliererLaufenLassen]?.wert?.gerundet(4) == d("2.4917"))
    #expect(jeMuster[.verliererLaufenLassen]?.trades == ["2", "3", "5", "6"])
    #expect(jeMuster[.ohneStop]?.trades == ["3"])
    // 7 gelöscht von 13 Orders.
    #expect(jeMuster[.staendigesUmplanen]?.wert?.gerundet(4) == d("0.5385"))
    #expect(befunde.allSatisfy { !$0.genugDaten })
}

@Test func schwellenSindEinstellbar() {
    var s = Fehlermuster.Schwellen()
    s.ueberhandelnUeberMedian = 1   // Montag hat 3 Trades, Median der Tage ist 1.
    s.zielAnteil = d("1.5")         // Trade 4 erreichte sein Ziel genau, also 100 % < 150 %.
    // Früher markierte das den ganzen Montag (1, 2, 3). Seit Tim 05.10.2026 trägt der Median erst ab
    // 10 Tagen mit Trades; die Hand-Trades haben 4, also ohne eigenes Limit kein Überhandeln.
    let ohneLimit = Fehlermuster.pruefe(handTrades, zeitzone: utc, schwellen: s)
    #expect(!ohneLimit.contains { $0.muster == .ueberhandeln })
    // Mit eigenem Limit 2 je Tag ist nur die dritte Position des Montags zu viel, nicht der ganze Tag.
    s.maxTradesProTag = 2
    let befunde = Fehlermuster.pruefe(handTrades, zeitzone: utc, schwellen: s)
    let jeMuster = Dictionary(uniqueKeysWithValues: befunde.map { ($0.muster, $0) })
    #expect(jeMuster[.ueberhandeln]?.trades == ["3"])
    #expect(jeMuster[.ueberhandeln]?.stichprobe == 4)
    #expect(jeMuster[.ueberhandeln]?.wert == 2)
    #expect(jeMuster[.gewinneZuFrueh]?.trades == ["4"])
}

@Test func verbilligenUndGroesseNachSerie() {
    func t(_ id: String, _ offen: Double, _ zu: Double, kurs: Decimal, stop: Decimal, ergebnis: Decimal) -> Trade {
        let start = Date(timeIntervalSince1970: 1_748_851_200) // 02.06.2025 08:00 UTC
        return Trade(id: id, symbol: "de40", side: .buy, lots: 1,
                     openTime: start.addingTimeInterval(offen * 60), closeTime: start.addingTimeInterval(zu * 60),
                     openPrice: kurs, closePrice: kurs + ergebnis, stopLoss: stop, profit: ergebnis)
    }
    // A und B gewinnen, C eröffnet danach mit Risiko 30 (Median 10). D kauft unter dem Kurs von C nach.
    let trades = [
        t("A", 0, 10, kurs: 100, stop: 90, ergebnis: 5),
        t("B", 20, 30, kurs: 100, stop: 90, ergebnis: 5),
        t("C", 40, 90, kurs: 100, stop: 70, ergebnis: -10),
        t("D", 50, 90, kurs: 95, stop: 85, ergebnis: -5),
    ]
    let befunde = Fehlermuster.pruefe(trades, zeitzone: utc)
    let jeMuster = Dictionary(uniqueKeysWithValues: befunde.map { ($0.muster, $0) })
    #expect(jeMuster[.groesseNachGewinnserie]?.trades == ["C"])
    #expect(jeMuster[.verbilligen]?.trades == ["D"])
}

@Test func medianGeradeUndUngerade() {
    #expect(Fehlermuster.median([3, 1, 2]) == 2)
    #expect(Fehlermuster.median([4, 1, 3, 2]) == d("2.5"))
    #expect(Fehlermuster.median([]) == nil)
}

/// Erfundener Beispielauszug (Mai 2026, Tage in UTC). Sollwerte unabhängig mit Python gerechnet (04.10.2026).
@Test func fehlermusterBeispielMai2026() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MT4/beispiel-2026-05-31-monthly.html")
    let auszug = try MT4Statement.parse(html: String(contentsOf: url, encoding: .utf8),
                                        serverZeitzone: TimeZone(secondsFromGMT: 3 * 3600)!)
    let trades = auszug.closedPositions.map { Trade($0) }
    let befunde = Fehlermuster.pruefe(trades, geloeschteOrders: auszug.cancelledOrders.count, zeitzone: utc)
    #expect(befunde.map(\.muster) == [.revancheTrade, .ueberhandeln, .gewinneZuFrueh, .verliererLaufenLassen,
                                      .verbilligen, .schwankendeGroesse, .groesseNachGewinnserie])
    let jeMuster = Dictionary(uniqueKeysWithValues: befunde.map { ($0.muster, $0) })
    #expect(jeMuster[.revancheTrade]?.trades.count == 6)
    #expect(jeMuster[.revancheTrade]?.netto == d("-1.87"))
    // 20 Tage, Positionen je Tag im Median 5, Grenze 7. Früher zählten alle Trades der drei Tage über 7
    // (10 + 10 + 13 = 33); seit Tim 05.10.2026 nur die Positionen ab der 8. des Tages: 3 + 3 + 6 = 12
    // (nachgerechnet mit Python am Fixture, Eröffnung in UTC).
    #expect(jeMuster[.ueberhandeln]?.trades.count == 12)
    #expect(jeMuster[.ueberhandeln]?.stichprobe == 20)
    #expect(jeMuster[.ueberhandeln]?.wert == 7)
    #expect(jeMuster[.gewinneZuFrueh]?.trades.count == 7)
    #expect(jeMuster[.gewinneZuFrueh]?.stichprobe == 50)
    #expect(jeMuster[.verliererLaufenLassen]?.wert?.gerundet(4) == d("2.1129"))
    #expect(jeMuster[.verbilligen]?.trades.count == 6)
    #expect(jeMuster[.schwankendeGroesse]?.wert?.gerundet(4) == d("1.0164"))
    #expect(jeMuster[.groesseNachGewinnserie]?.trades.count == 21)
}
