import Foundation
import Testing
@testable import TradingCore

/// Sieben Hand-Trades; Sollwerte unabhängig mit Python gerechnet (02.10.2026).
private func pbTrade(_ id: String, _ netto: Decimal) -> Trade {
    let start = Date(timeIntervalSince1970: 1_775_000_000)
    return Trade(id: id, symbol: "DAX", side: .buy, lots: 1, openTime: start, closeTime: start.addingTimeInterval(600),
                 openPrice: 100, closePrice: 100, profit: netto)
}

private let trend = Kriterium(id: "k1", text: "Trend auf H1 intakt")
private let volumen = Kriterium(id: "k2", text: "Volumen über Schnitt")
private let seit = Date(timeIntervalSince1970: 1_775_000_000)
private let playbook = [
    Setup(name: "Pullback", kriterien: [trend, volumen], status: .aktiv, statusSeit: seit),
    Setup(name: "Ausbruch", statusSeit: seit),
    Setup(name: "Range", status: .pausiert, statusSeit: seit),
]
private let pbTrades = [pbTrade("P1", 100), pbTrade("P2", -50), pbTrade("P3", 60), pbTrade("P4", -40),
                        pbTrade("A1", 30), pbTrade("X1", -10), pbTrade("O1", 20)]
private let checklisten: [String: Checkliste] = [
    "P1": Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"]),
    "P2": Checkliste(setup: "Pullback", erfuellt: ["k1"]),
    "P3": Checkliste(setup: "Pullback", erfuellt: ["k1", "k2"]),
    "P4": Checkliste(setup: "Pullback"),
    "A1": Checkliste(setup: "Ausbruch"),
    "X1": Checkliste(setup: "Pulback"),
]

@Test func playbookJeSetup() throws {
    let a = PlaybookAuswertung(trades: pbTrades, playbook: playbook, checklisten: checklisten)
    #expect(a.setups.map(\.setup) == ["Pullback", "Ausbruch", "Range"])
    let pullback = try #require(a.setups.first)
    #expect(pullback.kennzahlen.anzahl == 4)
    #expect(pullback.kennzahlen.netto == 70)
    #expect(pullback.vollstaendig.anzahl == 2)
    #expect(pullback.vollstaendig.netto == 160)
    #expect(pullback.unvollstaendig.netto == -90)
    #expect(pullback.regeltreue == Decimal(string: "0.5"))
    // Ohne Kriterien auf der Karte gibt es keine Regeltreue; ohne Trades ebenso.
    #expect(a.setups[1].regeltreue == nil)
    #expect(a.setups[2].kennzahlen.anzahl == 0)
    #expect(a.setups[2].regeltreue == nil)
}

@Test func playbookJeKriterium() {
    let a = PlaybookAuswertung(trades: pbTrades, playbook: playbook, checklisten: checklisten)
    // Volumen: Ø 80 mit, Ø −45 ohne → 125; Trend: Ø 110/3 mit, −40 ohne → 230/3.
    #expect(a.kriterien.map(\.kriterium.id) == ["k2", "k1"])
    #expect(a.kriterien.first?.effekt == 125)
    #expect(a.kriterien.last?.effekt?.gerundet(4) == Decimal(string: "76.6667"))
    let keineSchluesse = a.kriterien.allSatisfy { !$0.genugDaten }
    #expect(keineSchluesse)
}

@Test func playbookUnbekannteUndOhneSetup() {
    let a = PlaybookAuswertung(trades: pbTrades, playbook: playbook, checklisten: checklisten)
    #expect(Array(a.unbekannteSetups.keys) == ["Pulback"])
    #expect(a.unbekannteSetups["Pulback"]?.netto == -10)
    #expect(a.ohneSetup.anzahl == 1)
    #expect(a.ohneSetup.netto == 20)
}

@Test func playbookUeberstehtJSON() throws {
    let daten = try JSONEncoder().encode(playbook)
    #expect(try JSONDecoder().decode([Setup].self, from: daten) == playbook)
    let liste = try JSONEncoder().encode(checklisten)
    #expect(try JSONDecoder().decode([String: Checkliste].self, from: liste) == checklisten)
}
