import Foundation
import Testing
@testable import TradingCore

/// Leistungsscore und Merkmalauswertung (Tim 05.10.2026). Erfundene Trades, Zeitzone Europe/Berlin,
/// Sollwerte von Hand nachgerechnet.
private let scoreZone = TimeZone(identifier: "Europe/Berlin")!

private func scoreZeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter.date(from: iso + "Z")!
}

private func scoreDez(_ text: String) -> Decimal { Decimal(string: text)! }

/// Kauf zu 100, Ergebnis = Kursbewegung; mit Stop 90 ist 1 R = 10.
private func scoreTrade(_ id: String, _ offen: String, _ zu: String, _ ergebnis: Decimal,
                        stop: Decimal? = nil) -> Trade {
    Trade(id: id, symbol: "DE40", side: .buy, lots: 1, openTime: scoreZeit(offen), closeTime: scoreZeit(zu),
          openPrice: 100, closePrice: 100 + ergebnis, stopLoss: stop, profit: ergebnis)
}

/// Zehn Tage (1.–10.10.2026) mit je zwei Trades, Gewinner +15, Verlierer −10:
/// GG, VV, VG, GG, VV, GV, GG, VV, GG, VV. Kapital 15, 30, 20, 10, 0, 15, 30, 45, 35, 25, 40, 30, 45, 60, …, 50.
/// Trefferquote 0,5; Payoff 15 ÷ 10 = 1,5; Profitfaktor 150 ÷ 100 = 1,5; 6 von 10 Tagen im Plus;
/// größter Rückgang 30 (von 30 auf 0) ÷ Gewinne 150 = 0,2.
private func scoreZehnTage() -> [Trade] {
    let tage: [[Decimal]] = [[15, 15], [-10, -10], [-10, 15], [15, 15], [-10, -10],
                             [15, -10], [15, 15], [-10, -10], [15, 15], [-10, -10]]
    var trades: [Trade] = []
    for (i, ergebnisse) in tage.enumerated() {
        let tag = String(format: "2026-10-%02d", i + 1)
        trades.append(scoreTrade("S\(i)a", tag + "T08:00:00", tag + "T08:30:00", ergebnisse[0]))
        trades.append(scoreTrade("S\(i)b", tag + "T10:00:00", tag + "T10:30:00", ergebnisse[1]))
    }
    return trades
}

@Test func tiefeScoreKomponentenUndGesamt() throws {
    let score = try #require(Leistungsscore(trades: scoreZehnTage(), zeitzone: scoreZone))
    #expect(score.anzahl == 20)
    #expect(score.komponenten.map(\.schluessel) == ["trefferquote", "payoff", "profitfaktor", "bestaendigkeit",
                                                    "drawdown"])
    // Trefferquote 0,5 zwischen 0,4 → 50 und 0,6 → 100: 75. Payoff 1,5: 75. Profitfaktor 1,5: genau 50.
    // Beständigkeit 0,6 zwischen 0,5 → 50 und 0,7 → 100: 75. Drawdown 0,2: 100 − 0,8 × 40 = 68.
    let werte: [Decimal] = [75, 75, 50, 75, 68]
    #expect(score.komponenten.map(\.wert) == werte)
    let roh: [Decimal?] = [scoreDez("0.5"), scoreDez("1.5"), scoreDez("1.5"), scoreDez("0.6"), scoreDez("0.2")]
    #expect(score.komponenten.map(\.rohwert) == roh)
    // (15 × 75 + 15 × 75 + 25 × 50 + 15 × 75 + 15 × 68) ÷ 85 = 5645 ÷ 85.
    #expect(score.gesamt == Decimal(5645) / Decimal(85))
    #expect(score.komponenten[2].gewicht == Decimal(25) / Decimal(85))
    #expect(score.wert(.regeltreue) == nil)

    // Mit Regeltreue 0,9 (zwischen 0,75 → 50 und 1 → 100: 80): (5645 + 15 × 80) ÷ 100 = 68,45.
    let mitTreue = try #require(Leistungsscore(trades: scoreZehnTage(), zeitzone: scoreZone,
                                               regeltreue: scoreDez("0.9")))
    #expect(mitTreue.wert(.regeltreue) == 80)
    #expect(mitTreue.gesamt == scoreDez("68.45"))
    #expect(mitTreue.komponenten.last?.gewicht == scoreDez("0.15"))
}

@Test func tiefeScoreRaender() {
    // 19 Trades: unter der Mindestanzahl.
    let neunzehn = Array(scoreZehnTage().dropLast())
    #expect(Leistungsscore(trades: neunzehn, zeitzone: scoreZone) == nil)
    #expect(Leistungsscore(trades: [], zeitzone: scoreZone, mindestanzahl: 0) == nil)
    #expect(Leistungsscore(trades: neunzehn, zeitzone: scoreZone, mindestanzahl: 19) != nil)

    // Nur Gewinner: Payoff und Profitfaktor unendlich, kein Rückgang: überall 100.
    var gewinner: [Trade] = []
    for i in 0..<20 {
        let tag = String(format: "2026-10-%02d", i + 1)
        gewinner.append(scoreTrade("G\(i)", tag + "T08:00:00", tag + "T09:00:00", 5))
    }
    let voll = Leistungsscore(trades: gewinner, zeitzone: scoreZone)
    #expect(voll?.gesamt == 100)
    #expect(voll?.komponenten.first { $0.komponente == .payoff }?.rohwert == nil)

    // Skalierung: unter dem ersten und über dem letzten Anker gekappt, dazwischen linear.
    #expect(Leistungsscore.skaliert(scoreDez("0.8"), .profitfaktor) == 0)
    #expect(Leistungsscore.skaliert(3, .profitfaktor) == 100)
    #expect(Leistungsscore.skaliert(2, .profitfaktor) == 75)
    #expect(Leistungsscore.skaliert(scoreDez("0.75"), .drawdown) == 15)
    #expect(Leistungsscore.anteilProfitableTage([], zeitzone: scoreZone) == 0)
    let summe: Decimal = Leistungsscore.gewichte.values.reduce(0, +)
    #expect(summe == 100)
}

// MARK: - Merkmale

private let merkmalTrades: [Trade] = [
    scoreTrade("T1", "2026-10-05T07:00:00", "2026-10-05T07:30:00", 20, stop: 90),
    scoreTrade("T2", "2026-10-05T08:00:00", "2026-10-05T08:30:00", -10, stop: 90),
    scoreTrade("T3", "2026-10-05T09:00:00", "2026-10-05T09:30:00", -15),
    scoreTrade("T4", "2026-10-06T09:00:00", "2026-10-06T09:30:00", 5),
    scoreTrade("T5", "2026-10-06T10:00:00", "2026-10-06T10:30:00", 7),
]

@Test func tiefeMerkmaleTagsOhneGrossKlein() {
    let tags = ["T1": ["FOMO", "Ausbruch"], "T2": ["fomo"], "T3": [" Fomo ", "FOMO"], "T4": [""],
                "fremd": ["Geist"]]
    let auswertung = Merkmalauswertung(trades: merkmalTrades, merkmale: tags)
    #expect(auswertung.merkmale.map(\.merkmal) == ["Ausbruch", "FOMO"])  // nach Netto: 20 vor −5
    #expect(auswertung.ohneMerkmal == 2)  // T4 nur leer, T5 ohne Eintrag

    let fomo = auswertung.merkmale[1]
    #expect(fomo.anzahl == 3)  // T3 trägt FOMO zweimal, zählt einmal
    #expect(fomo.netto == -5)
    #expect(fomo.trefferquote == Decimal(1) / Decimal(3))
    #expect(fomo.durchschnittR == scoreDez("0.5"))  // (2 − 1) ÷ 2, T3 ohne Stop
    #expect(fomo.verlierer == 2)
    #expect(fomo.anteilAnVerlierern == 1)
    #expect(fomo.tradeIDs == ["T1", "T2", "T3"])

    let ausbruch = auswertung.merkmale[0]
    #expect(ausbruch.netto == 20)
    #expect(ausbruch.durchschnittR == 2)
    #expect(ausbruch.anteilAnVerlierern == 0)
}

@Test func tiefeMerkmaleZustandUndRaender() {
    let zustand = ["T1": ["4"], "T2": ["2"], "T3": ["2"], "T4": ["4"], "T5": ["3"]]
    let auswertung = Merkmalauswertung(trades: merkmalTrades, merkmale: zustand)
    #expect(auswertung.merkmale.map(\.merkmal) == ["4", "3", "2"])
    #expect(auswertung.merkmale.map(\.netto) == [25, 7, -25])
    #expect(auswertung.merkmale.map(\.anzahl) == [2, 1, 2])
    #expect(auswertung.merkmale[2].trefferquote == 0)
    #expect(auswertung.merkmale[2].anteilAnVerlierern == 1)
    #expect(auswertung.ohneMerkmal == 0)

    let leer = Merkmalauswertung(trades: [], merkmale: [:])
    #expect(leer.merkmale.isEmpty)
    #expect(leer.ohneMerkmal == 0)
    let ohneVerlierer = Merkmalauswertung(trades: [merkmalTrades[4]], merkmale: ["T5": ["ruhig"]])
    #expect(ohneVerlierer.merkmale.first?.anteilAnVerlierern == nil)
    #expect(Merkmalauswertung.haeufigste(["fomo": 1, "FOMO": 1], ersatz: "x") == "FOMO")
}
